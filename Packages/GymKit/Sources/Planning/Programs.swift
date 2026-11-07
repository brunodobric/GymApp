import Catalog
import Foundation
import Models
import SwiftData

// Gotovi programi (docs/SPECIFIKACIJA.md, "Gotovi programi i preporuka").
// Program zadaje strukturu: treninge, vježbe kao obrasce kretanja i broj serija. Ponavljanja i pauze
// slijede iz cilja i iskustva (`ProgramPrescription`), a konkretna vježba iz opreme koju korisnik ima.
// Podloga: ACSM 2026 (Currier i sur.), Pelland i sur. 2026, Schoenfeld i sur. 2016, 2019 i 2021.

/// Uloga vježbe u treningu: određuje raspon ponavljanja i pauzu.
public enum ExerciseRole: String, Equatable, Sendable {
    /// Glavna višezglobna vježba, na početku treninga, s najvećim opterećenjem.
    case main
    /// Pomoćna višezglobna vježba.
    case secondary
    /// Izolacijska vježba. Preskače se kad za nju nema opreme.
    case isolation
}

/// Jedna izvedba obrasca kretanja: vježba iz kataloga i oprema bez koje se ne može.
public struct ExerciseOption: Equatable, Sendable {
    public let catalogId: String
    public let inputType: ExerciseInputType
    /// Potrebna oprema. Prazno znači samo vlastita težina. Šipka za zgibove je `.other`.
    public let equipment: Set<Equipment>

    public init(catalogId: String, inputType: ExerciseInputType, equipment: Set<Equipment>) {
        self.catalogId = catalogId
        self.inputType = inputType
        self.equipment = equipment
    }

    public func isAvailable(with available: Set<Equipment>) -> Bool {
        equipment.isSubset(of: available)
    }
}

public struct ProgramExercise: Equatable, Sendable {
    /// Izvedbe po redu prednosti: bira se prva za koju korisnik ima opremu.
    public let options: [ExerciseOption]
    public let role: ExerciseRole
    public let sets: Int

    public init(options: [ExerciseOption], role: ExerciseRole, sets: Int) {
        self.options = options
        self.role = role
        self.sets = sets
    }

    /// Prva izvedba za dostupnu opremu, ili nil kad nijedna nije moguća.
    public func option(for available: Set<Equipment>) -> ExerciseOption? {
        options.first { $0.isAvailable(with: available) }
    }
}

public struct ProgramWorkout: Equatable, Sendable {
    public let key: String
    public let name: String
    public let exercises: [ProgramExercise]
}

public enum ProgramStep: Equatable, Sendable {
    case workout(String)
    case restDay
}

/// Gotov program: skup treninga, njihov redoslijed i za koga je.
public struct Program: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    /// Treninga tjedno kad se niz prati po danima podsjetnika.
    public let daysPerWeek: Int
    /// Broj dana tjedno za koje program odgovara (preporuka).
    public let suitableDays: ClosedRange<Int>
    public let goals: Set<TrainingGoal>
    public let levels: Set<ExperienceLevel>
    public let workouts: [ProgramWorkout]
    /// Niz jednog ciklusa. Može trajati više tjedana (A/B izmjena), tada ima `daysPerWeek × weeks` treninga.
    public let sequence: [ProgramStep]
    public let weeks: Int

    /// Program se može izvesti kad glavne i pomoćne vježbe imaju izvedbu za dostupnu opremu.
    public func isAvailable(with available: Set<Equipment>) -> Bool {
        workouts.allSatisfy { workout in
            workout.exercises.allSatisfy { $0.role == .isolation || $0.option(for: available) != nil }
        }
    }
}

/// Ponavljanja, pauza i broj serija za jednu vježbu programa.
public struct Prescription: Equatable, Sendable {
    public let sets: Int
    public let repsMin: Int
    public let repsMax: Int
    public let restSeconds: Int
}

/// Doziranje prema cilju i iskustvu. Snaga: glavne vježbe 3–6 ponavljanja (≥80 % 1RM). Hipertrofija:
/// 6–15 ponavljanja blizu otkaza. Opća kondicija: 8–15 ponavljanja i serija manje (ACSM 2026; Schoenfeld i sur.
/// 2021). Pauze 2–3 min za višezglobne vježbe (Schoenfeld i sur. 2016). Početnik radi seriju manje
/// izolacijskih vježbi: kod početnika i manji volumen daje napredak, a tehnika glavnih vježbi je važnija.
public enum ProgramPrescription {
    public static func make(role: ExerciseRole, sets: Int, goal: TrainingGoal?, level: ExperienceLevel?) -> Prescription {
        let goal = goal ?? .hypertrophy
        var sets = sets
        if goal == .generalFitness { sets -= 1 }
        if level == .beginner, role == .isolation { sets -= 1 }
        sets = max(2, sets)

        switch (goal, role) {
        case (.strength, .main): return Prescription(sets: sets, repsMin: 3, repsMax: 6, restSeconds: 180)
        case (.strength, .secondary): return Prescription(sets: sets, repsMin: 5, repsMax: 8, restSeconds: 150)
        case (.strength, .isolation): return Prescription(sets: sets, repsMin: 8, repsMax: 12, restSeconds: 90)
        case (.hypertrophy, .main), (.recomposition, .main):
            return Prescription(sets: sets, repsMin: 6, repsMax: 10, restSeconds: 150)
        case (.hypertrophy, .secondary), (.recomposition, .secondary):
            return Prescription(sets: sets, repsMin: 8, repsMax: 12, restSeconds: 120)
        case (.hypertrophy, .isolation), (.recomposition, .isolation):
            return Prescription(sets: sets, repsMin: 10, repsMax: 15, restSeconds: 90)
        case (.generalFitness, .main): return Prescription(sets: sets, repsMin: 8, repsMax: 12, restSeconds: 120)
        case (.generalFitness, .secondary): return Prescription(sets: sets, repsMin: 10, repsMax: 15, restSeconds: 90)
        case (.generalFitness, .isolation): return Prescription(sets: sets, repsMin: 12, repsMax: 15, restSeconds: 60)
        }
    }
}

public enum ProgramLibrary {

    // MARK: Knjižnica

    private static let allGoals = Set(TrainingGoal.allCases)

    public static let all: [Program] = [
        Program(
            id: "basic-full-body-2", name: "Osnovni full body (2 dana)",
            summary: "Dva kratka treninga cijelog tijela tjedno. Dovoljno za zdravlje i napredak kad nema više vremena.",
            daysPerWeek: 2, suitableDays: 1...2, goals: allGoals, levels: Set(ExperienceLevel.allCases),
            workouts: [basicA, basicB],
            sequence: [.restDay, .workout("basicA"), .restDay, .restDay, .workout("basicB"), .restDay, .restDay],
            weeks: 1
        ),
        Program(
            id: "beginner-full-body-3", name: "Početnički full body (3 dana)",
            summary: "Treninzi A i B naizmjence, tri puta tjedno. Malo vježbi, svaki mišić tri puta tjedno.",
            daysPerWeek: 3, suitableDays: 3...3, goals: allGoals, levels: [.beginner],
            workouts: [beginnerA, beginnerB],
            sequence: [
                .workout("beginnerA"), .restDay, .workout("beginnerB"), .restDay, .workout("beginnerA"), .restDay, .restDay,
                .workout("beginnerB"), .restDay, .workout("beginnerA"), .restDay, .workout("beginnerB"), .restDay, .restDay,
            ],
            weeks: 2
        ),
        Program(
            id: "full-body-3", name: "Full body (3 dana)",
            summary: "Tri različita treninga cijelog tijela tjedno, svaki mišić dva do tri puta.",
            daysPerWeek: 3, suitableDays: 3...3, goals: allGoals, levels: [.intermediate, .advanced],
            workouts: [fullBodyA, fullBodyB, fullBodyC],
            sequence: [.workout("fullA"), .restDay, .workout("fullB"), .restDay, .workout("fullC"), .restDay, .restDay],
            weeks: 1
        ),
        Program(
            id: "upper-lower-4", name: "Upper/Lower (4 dana)",
            summary: "Dva dana gornjeg i dva dana donjeg dijela tijela tjedno, svaki mišić dvaput.",
            daysPerWeek: 4, suitableDays: 4...4, goals: allGoals, levels: Set(ExperienceLevel.allCases),
            workouts: [upperA, lowerA, upperB, lowerB],
            sequence: [
                .workout("upperA"), .workout("lowerA"), .restDay, .workout("upperB"), .workout("lowerB"), .restDay, .restDay,
            ],
            weeks: 1
        ),
        Program(
            id: "upper-lower-ppl-5", name: "Upper/Lower + PPL (5 dana)",
            summary: "Gornji i donji dio tijela, dan odmora, pa guranje, povlačenje i noge. Svaki mišić dvaput tjedno.",
            daysPerWeek: 5, suitableDays: 5...5, goals: [.hypertrophy, .recomposition, .strength],
            levels: [.intermediate, .advanced],
            workouts: [upperA, lowerA, pushB, pullA, legsB],
            sequence: [
                .workout("upperA"), .workout("lowerA"), .restDay,
                .workout("pushB"), .workout("pullA"), .workout("legsB"), .restDay,
            ],
            weeks: 1
        ),
        Program(
            id: "ppl-6", name: "Push/Pull/Legs (6 dana)",
            summary: "Guranje, povlačenje i noge dvaput tjedno, s dvije varijante svakog treninga.",
            daysPerWeek: 6, suitableDays: 6...7, goals: [.hypertrophy, .recomposition], levels: [.intermediate, .advanced],
            workouts: [pushA, pullA, legsA, pushB, pullB, legsB],
            sequence: [
                .workout("pushA"), .workout("pullA"), .workout("legsA"),
                .workout("pushB"), .workout("pullB"), .workout("legsB"), .restDay,
            ],
            weeks: 1
        ),
    ]

    /// Dani u tjednu (Calendar.weekday, 1 = nedjelja) za fiksne podsjetnike, s odmorom između treninga
    /// gdje god je moguće.
    public static func defaultWeekdays(daysPerWeek: Int) -> [Int] {
        switch daysPerWeek {
        case ...1: [4]
        case 2: [3, 6]
        case 3: [2, 4, 6]
        case 4: [2, 3, 5, 6]
        case 5: [2, 3, 5, 6, 7]
        case 6: [2, 3, 4, 5, 6, 7]
        default: [1, 2, 3, 4, 5, 6, 7]
        }
    }
}

/// Stvara predloške i raspored iz gotovog programa. Nazive vježbi daje pozivatelj (katalog je na jeziku korisnika).
public struct ProgramInstaller {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// - Parameters:
    ///   - profile: cilj i iskustvo određuju ponavljanja i pauze, a oprema izvedbu vježbe.
    ///     Bez opreme u profilu vrijedi teretana (sva oprema).
    ///   - name: naziv rasporeda na jeziku sučelja (zadano: hrvatski naziv programa)
    ///   - workoutName: naziv treninga na jeziku sučelja (zadano: hrvatski naziv)
    @discardableResult
    public func install(
        _ program: Program,
        profile: TrainingProfile = TrainingProfile(),
        name: String? = nil,
        workoutName: (ProgramWorkout) -> String = { $0.name },
        exerciseName: (String) -> String
    ) throws -> Schedule {
        let templates = TemplateEngine(context: context)
        let schedules = ScheduleEngine(context: context)
        let available = profile.availableEquipment
        var created: [String: WorkoutTemplate] = [:]

        for workout in program.workouts {
            let template = try templates.createTemplate(name: workoutName(workout))
            for item in workout.exercises {
                // Glavne i pomoćne vježbe uvijek postoje (ako oprema ne odgovara, ide prva izvedba),
                // a izolacijska se preskače.
                guard let choice = item.option(for: available) ?? (item.role == .isolation ? nil : item.options.first) else {
                    continue
                }
                let dose = ProgramPrescription.make(role: item.role, sets: item.sets, goal: profile.goal, level: profile.experience)
                let ref = ExerciseRef(catalogId: choice.catalogId, name: exerciseName(choice.catalogId))
                let exercise = try templates.addExercise(ref, inputType: choice.inputType, to: template, setCount: dose.sets)
                exercise.restSeconds = dose.restSeconds
                if choice.inputType != .duration && choice.inputType != .durationDistance {
                    for set in exercise.orderedSets {
                        set.targetReps = dose.repsMin
                        set.targetRepsMax = dose.repsMax
                    }
                }
            }
            created[workout.key] = template
        }
        try context.save()

        let schedule = try schedules.createSchedule(name: name ?? program.name)
        for step in program.sequence {
            switch step {
            case .workout(let key):
                if let template = created[key] { try schedules.addWorkout(template, to: schedule) }
            case .restDay:
                try schedules.addRestDay(to: schedule)
            }
        }
        // Fiksni dani za podsjetnike: inače bi "3 dana" s jednim danom razmaka bila 4 treninga tjedno.
        // Vrijeme podsjetnika ostaje prazno, pa se ništa ne zakazuje dok ga korisnik ne postavi.
        schedule.reminderMode = .fixedDays
        let days = profile.daysPerWeek.flatMap { program.suitableDays.contains($0) ? min($0, program.daysPerWeek) : nil }
        schedule.weekdays = ProgramLibrary.defaultWeekdays(daysPerWeek: days ?? program.daysPerWeek)
        try context.save()
        return schedule
    }
}
