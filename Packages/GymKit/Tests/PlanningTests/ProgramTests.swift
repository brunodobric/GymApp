import Catalog
import Foundation
import Models
import SwiftData
import Testing
@testable import Planning

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private func loadCatalog() throws -> ExerciseCatalog {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Catalog/catalog.json")
    return try ExerciseCatalog(data: Data(contentsOf: url))
}

private func program(_ id: String) throws -> Program {
    try #require(ProgramLibrary.all.first { $0.id == id })
}

/// Oprema svih preseta i prazan odabir (teretana).
private let equipmentChoices: [Set<Equipment>] = EquipmentPreset.allCases.map { Set($0.equipment) } + [[]]

/// Tjedne frakcijske serije po mišiću (glavni mišić 1, pomoćni 0,5; Pelland i sur. 2026) i koliko puta
/// tjedno je mišić glavni u nekoj vježbi.
private func weeklyLoad(
    of program: Program, equipment: Set<Equipment>, catalog: ExerciseCatalog
) -> (sets: [Muscle: Double], frequency: [Muscle: Double]) {
    let available = TrainingProfile(equipment: equipment).availableEquipment
    let workouts = Dictionary(uniqueKeysWithValues: program.workouts.map { ($0.key, $0) })
    var sets: [Muscle: Double] = [:]
    var frequency: [Muscle: Double] = [:]
    let weeks = Double(program.weeks)
    for case .workout(let key) in program.sequence {
        guard let workout = workouts[key] else { continue }
        var trained = Set<Muscle>()
        for item in workout.exercises {
            guard let choice = item.option(for: available) ?? (item.role == .isolation ? nil : item.options.first),
                  let exercise = catalog.exercise(withID: choice.catalogId) else { continue }
            for muscle in exercise.primaryMuscles {
                sets[muscle, default: 0] += Double(item.sets) / weeks
                trained.insert(muscle)
            }
            for muscle in exercise.secondaryMuscles { sets[muscle, default: 0] += Double(item.sets) * 0.5 / weeks }
        }
        for muscle in trained { frequency[muscle, default: 0] += 1 / weeks }
    }
    return (sets, frequency)
}

@Suite("Gotovi programi")
struct ProgramTests {
    @Test("Svaka izvedba postoji u katalogu s istom vrstom unosa i opremom")
    func optionsMatchCatalog() throws {
        let catalog = try loadCatalog()
        for program in ProgramLibrary.all {
            for workout in program.workouts {
                for item in workout.exercises {
                    #expect(!item.options.isEmpty)
                    for option in item.options {
                        let found = catalog.exercise(withID: option.catalogId)
                        #expect(found != nil, "\(program.id): nema \(option.catalogId)")
                        guard let found else { continue }
                        #expect(found.inputType == option.inputType, "\(option.catalogId): druga vrsta unosa")
                        if found.equipment == .bodyweight {
                            #expect(option.equipment.isSubset(of: [.other]), "\(option.catalogId): oprema")
                        } else {
                            #expect(option.equipment == [found.equipment], "\(option.catalogId): oprema")
                        }
                    }
                }
            }
        }
    }

    @Test("Nizovi pozivaju postojeće treninge, svaki trening je u nizu i broj treninga odgovara danima")
    func sequences() {
        #expect(ProgramLibrary.all.map(\.id).count == Set(ProgramLibrary.all.map(\.id)).count)
        for program in ProgramLibrary.all {
            let keys = Set(program.workouts.map(\.key))
            #expect(keys.count == program.workouts.count, "\(program.id): ponovljen ključ")
            var used = Set<String>()
            var workoutDays = 0
            for case .workout(let key) in program.sequence {
                #expect(keys.contains(key), "\(program.id): nepoznat trening \(key)")
                used.insert(key)
                workoutDays += 1
            }
            #expect(used == keys, "\(program.id): trening nije u nizu")
            #expect(workoutDays == program.daysPerWeek * program.weeks, "\(program.id): broj treninga")
            #expect(program.sequence.count == 7 * program.weeks, "\(program.id): niz nije cijeli broj tjedana")
            #expect(program.suitableDays.contains(program.daysPerWeek))
            #expect(!program.goals.isEmpty && !program.levels.isEmpty)
        }
    }

    @Test("Svaki program može se izvesti sa svakom opremom, i bez opreme")
    func availableEverywhere() {
        for equipment in equipmentChoices {
            let available = TrainingProfile(equipment: equipment).availableEquipment
            for program in ProgramLibrary.all {
                #expect(program.isAvailable(with: available), "\(program.id) nije moguć s \(equipment)")
                for workout in program.workouts {
                    let count = workout.exercises.filter { $0.option(for: available) != nil }.count
                    #expect(count >= 3, "\(program.id)/\(workout.key): premalo vježbi s \(equipment)")
                }
            }
        }
    }

    @Test("Svaki mišić dobiva dovoljno serija, ali ne previše (teretana)")
    func weeklyVolume() throws {
        let catalog = try loadCatalog()
        let big: [Muscle] = [.chest, .quadriceps, .glutes]
        for program in ProgramLibrary.all {
            let load = weeklyLoad(of: program, equipment: [], catalog: catalog).sets
            // Leđa su dva mišića u katalogu (široki leđni i srednja leđa), pa se provjerava svaki.
            let back = [load[.lats] ?? 0, load[.middleBack] ?? 0]
            if program.levels.contains(.beginner) && !program.levels.contains(.advanced) || program.daysPerWeek <= 2 {
                // Početnici i minimalna doza: barem ~5 serija tjedno (Fyfe i sur. 2022).
                for muscle in big { #expect((load[muscle] ?? 0) >= 4.5, "\(program.id): \(muscle)") }
                #expect(back.allSatisfy { $0 >= 4.5 }, "\(program.id): leđa")
            } else {
                // ~10 serija tjedno i više (ACSM 2026), ispod granice iznad koje nema razlike (~30, Pelland i sur. 2026).
                for muscle in big {
                    #expect((9...30).contains(load[muscle] ?? 0), "\(program.id): \(muscle) \(load[muscle] ?? 0)")
                }
                #expect(back.allSatisfy { (6...30).contains($0) }, "\(program.id): leđa \(back)")
                #expect((load[.hamstrings] ?? 0) >= 7, "\(program.id): stražnja loža")
            }
        }
    }

    @Test("Uz tri i više dana tjedno prsa, leđa i noge rade se barem 1,5 puta tjedno")
    func frequency() throws {
        let catalog = try loadCatalog()
        for program in ProgramLibrary.all where program.daysPerWeek >= 3 {
            for equipment in equipmentChoices {
                let frequency = weeklyLoad(of: program, equipment: equipment, catalog: catalog).frequency
                let back = max(frequency[.lats] ?? 0, frequency[.middleBack] ?? 0)
                #expect((frequency[.chest] ?? 0) >= 1.5, "\(program.id): prsa")
                #expect(back >= 1.5, "\(program.id): leđa")
                #expect((frequency[.quadriceps] ?? 0) >= 1.5 || (frequency[.glutes] ?? 0) >= 2, "\(program.id): noge")
            }
        }
    }

    @Test("Bira se prva izvedba za dostupnu opremu")
    func optionForEquipment() throws {
        let bench = try #require(try program("upper-lower-4").workouts.first?.exercises.first)
        #expect(bench.option(for: Set(Equipment.allCases))?.catalogId == "barbell-bench-press")
        #expect(bench.option(for: [.dumbbell, .bodyweight])?.catalogId == "dumbbell-bench-press")
        #expect(bench.option(for: [.bodyweight])?.catalogId == "push-up")
    }

    @Test("Zadani dani podsjetnika imaju odmor između treninga")
    func weekdays() {
        #expect(ProgramLibrary.defaultWeekdays(daysPerWeek: 1) == [4])
        #expect(ProgramLibrary.defaultWeekdays(daysPerWeek: 3) == [2, 4, 6])
        for days in 1...7 { #expect(ProgramLibrary.defaultWeekdays(daysPerWeek: days).count == days) }
    }
}

@Suite("Doziranje prema cilju i iskustvu")
struct PrescriptionTests {
    @Test("Snaga: glavne vježbe 3–6 ponavljanja i duža pauza")
    func strength() {
        let main = ProgramPrescription.make(role: .main, sets: 3, goal: .strength, level: .intermediate)
        #expect(main == Prescription(sets: 3, repsMin: 3, repsMax: 6, restSeconds: 180))
    }

    @Test("Bez cilja vrijedi hipertrofija")
    func defaultGoal() {
        #expect(
            ProgramPrescription.make(role: .secondary, sets: 3, goal: nil, level: nil)
                == ProgramPrescription.make(role: .secondary, sets: 3, goal: .hypertrophy, level: nil)
        )
        #expect(ProgramPrescription.make(role: .isolation, sets: 3, goal: nil, level: nil).repsMax == 15)
    }

    @Test("Opća kondicija i početnik rade serije manje, ali barem dvije")
    func fewerSets() {
        #expect(ProgramPrescription.make(role: .main, sets: 3, goal: .generalFitness, level: nil).sets == 2)
        #expect(ProgramPrescription.make(role: .isolation, sets: 3, goal: .hypertrophy, level: .beginner).sets == 2)
        #expect(ProgramPrescription.make(role: .main, sets: 3, goal: .hypertrophy, level: .beginner).sets == 3)
        #expect(ProgramPrescription.make(role: .isolation, sets: 2, goal: .generalFitness, level: .beginner).sets == 2)
    }

    @Test("Svaki raspon ima donju granicu ispod gornje")
    func ranges() {
        for goal in TrainingGoal.allCases {
            for role in [ExerciseRole.main, .secondary, .isolation] {
                let dose = ProgramPrescription.make(role: role, sets: 3, goal: goal, level: nil)
                #expect(dose.repsMin < dose.repsMax && dose.restSeconds >= 60)
            }
        }
    }
}

@Suite("Instalacija programa")
struct ProgramInstallerTests {
    @Test("Stvara predloške i raspored u istom redoslijedu, s rasponima i pauzama")
    func install() throws {
        let context = try makeContext()
        let ppl = try program("ppl-6")
        let schedule = try ProgramInstaller(context: context).install(ppl) { "Vježba \($0)" }
        #expect(schedule.name == ppl.name && schedule.isActive)
        #expect(schedule.orderedItems.count == 7)
        #expect(schedule.orderedItems.last?.kind == .restDay)
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(templates.count == 6)
        #expect(Set(schedule.orderedItems.compactMap(\.workoutTemplateId)).count == 6)

        let push = try #require(templates.first { $0.name == "Push A" })
        let bench = try #require(push.orderedExercises.first)
        #expect(bench.exerciseName == "Vježba barbell-bench-press")
        #expect(bench.orderedSets.count == 4)
        #expect(bench.orderedSets.allSatisfy { $0.targetReps == 6 && $0.targetRepsMax == 10 })
        #expect(bench.restSeconds == 150)
        #expect(schedule.reminderMode == .fixedDays && schedule.weekdays == [2, 3, 4, 5, 6, 7])
        #expect(schedule.reminderMinutes == nil)
    }

    @Test("Cilj snaga mijenja ponavljanja glavnih vježbi")
    func strengthProfile() throws {
        let context = try makeContext()
        try ProgramInstaller(context: context).install(
            try program("upper-lower-4"), profile: TrainingProfile(goal: .strength)
        ) { $0 }
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let upper = try #require(templates.first { $0.name == "Gornji dio tijela A" })
        let bench = try #require(upper.orderedExercises.first)
        #expect(bench.orderedSets.allSatisfy { $0.targetReps == 3 && $0.targetRepsMax == 6 })
        #expect(bench.restSeconds == 180)
    }

    @Test("Bez opreme: vježbe s vlastitom težinom, izolacije bez opreme otpadaju")
    func bodyweightOnly() throws {
        let context = try makeContext()
        try ProgramInstaller(context: context).install(
            try program("upper-lower-4"), profile: TrainingProfile(equipment: Set(EquipmentPreset.bodyweightOnly.equipment))
        ) { $0 }
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let upper = try #require(templates.first { $0.name == "Gornji dio tijela A" })
        let names = upper.orderedExercises.map(\.exerciseName)
        #expect(names.first == "push-up")
        #expect(!names.contains("dumbbell-lateral-raise") && !names.contains("band-lateral-raise"))
        #expect(upper.orderedExercises.first?.inputType == .bodyweight)
    }

    @Test("Dani podsjetnika prate dane iz profila kad ih program podržava")
    func profileDays() throws {
        let context = try makeContext()
        let basic = try program("basic-full-body-2")
        let one = try ProgramInstaller(context: context).install(basic, profile: TrainingProfile(daysPerWeek: 1)) { $0 }
        #expect(one.weekdays == [4])
        let five = try ProgramInstaller(context: context).install(basic, profile: TrainingProfile(daysPerWeek: 5)) { $0 }
        #expect(five.weekdays == [3, 6])
    }

    @Test("Nazivi rasporeda i treninga na jeziku sučelja")
    func localizedNames() throws {
        let context = try makeContext()
        let schedule = try ProgramInstaller(context: context).install(
            try program("upper-lower-4"), name: "Upper/Lower (4 days)", workoutName: { "W \($0.key)" }, exerciseName: { $0 }
        )
        #expect(schedule.name == "Upper/Lower (4 days)")
        let names = Set(try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.name))
        #expect(names == ["W upperA", "W lowerA", "W upperB", "W lowerB"])
    }

    @Test("Plank ima serije bez ponavljanja")
    func durationExercise() throws {
        let context = try makeContext()
        try ProgramInstaller(context: context).install(try program("basic-full-body-2")) { $0 }
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let plank = try #require(templates.flatMap(\.orderedExercises).first { $0.exerciseName == "front-plank" })
        #expect(plank.inputType == .duration)
        #expect(plank.orderedSets.allSatisfy { $0.targetReps == nil && $0.targetRepsMax == nil })
    }

    @Test("Nova serija preuzima raspon, a ručni cilj iznad raspona ga poništava")
    func rangeEditing() throws {
        let context = try makeContext()
        try ProgramInstaller(context: context).install(try program("full-body-3")) { $0 }
        let template = try #require(try context.fetch(FetchDescriptor<WorkoutTemplate>()).first)
        let exercise = try #require(template.orderedExercises.first)
        let engine = TemplateEngine(context: context)
        let added = try engine.addSet(to: exercise)
        #expect(added.targetReps == 6 && added.targetRepsMax == 10)
        try engine.setTargets(added, weightKg: 60, reps: 8)
        #expect(added.targetRepsMax == 10)
        try engine.setTargets(added, weightKg: 60, reps: 12)
        #expect(added.targetRepsMax == nil)
    }
}

@Suite("Preporuka programa")
struct RecommenderTests {
    private func top(_ profile: TrainingProfile) -> String? {
        ProgramRecommender.recommend(for: profile).first?.program.id
    }

    @Test("Tipični profili dobivaju očekivani program")
    func golden() {
        #expect(top(TrainingProfile(goal: .strength, experience: .beginner, daysPerWeek: 3)) == "beginner-full-body-3")
        #expect(top(TrainingProfile(goal: .hypertrophy, experience: .intermediate, daysPerWeek: 3)) == "full-body-3")
        #expect(top(TrainingProfile(goal: .hypertrophy, experience: .beginner, daysPerWeek: 4)) == "upper-lower-4")
        #expect(top(TrainingProfile(goal: .hypertrophy, experience: .intermediate, daysPerWeek: 5)) == "upper-lower-ppl-5")
        #expect(top(TrainingProfile(goal: .hypertrophy, experience: .advanced, daysPerWeek: 6)) == "ppl-6")
        #expect(top(TrainingProfile(goal: .hypertrophy, experience: .advanced, daysPerWeek: 7)) == "ppl-6")
        #expect(top(TrainingProfile(goal: .generalFitness, daysPerWeek: 1)) == "basic-full-body-2")
        #expect(top(TrainingProfile(goal: .generalFitness, daysPerWeek: 2)) == "basic-full-body-2")
        // Bez odgovora: 3 dana, početnik.
        #expect(top(TrainingProfile()) == "beginner-full-body-3")
    }

    @Test("Razlozi navode samo ono što je korisnik odgovorio")
    func reasons() throws {
        let plain = try #require(ProgramRecommender.recommend(for: TrainingProfile()).first)
        #expect(plain.reasons == [.days(3)])
        let full = try #require(ProgramRecommender.recommend(for: TrainingProfile(
            goal: .strength, experience: .beginner, equipment: Set(EquipmentPreset.dumbbells.equipment), daysPerWeek: 3
        )).first)
        #expect(full.reasons == [.days(3), .level(.beginner), .goal(.strength), .equipment])
    }

    @Test("Svaka kombinacija odgovora dobiva prijedlog koji odgovara opremi, danima i cilju")
    func exhaustive() {
        let goals: [TrainingGoal?] = TrainingGoal.allCases + [nil]
        let levels: [ExperienceLevel?] = ExperienceLevel.allCases + [nil]
        let days: [Int?] = Array(1...7) + [nil]
        for goal in goals {
            for level in levels {
                for day in days {
                    for equipment in equipmentChoices {
                        let profile = TrainingProfile(goal: goal, experience: level, equipment: equipment, daysPerWeek: day)
                        let result = ProgramRecommender.recommend(for: profile)
                        #expect(result.count == 3)
                        #expect(Set(result.map(\.program.id)).count == result.count)
                        guard let best = result.first else { continue }
                        #expect(best.program.suitableDays.contains(day ?? ProgramRecommender.defaultDays), "\(profile)")
                        // Cilj se poštuje kad ga ima ijedan program za te dane (za 5 i 6 dana nema programa za opću kondiciju).
                        let days = day ?? ProgramRecommender.defaultDays
                        if let goal, ProgramLibrary.all.contains(where: { $0.suitableDays.contains(days) && $0.goals.contains(goal) }) {
                            #expect(best.program.goals.contains(goal), "\(profile)")
                        }
                        for item in result {
                            #expect(item.program.isAvailable(with: profile.availableEquipment))
                        }
                        #expect(zip(result, result.dropFirst()).allSatisfy { $0.score >= $1.score })
                    }
                }
            }
        }
    }

    @Test("Program koji se ne može izvesti s opremom ne predlaže se")
    func equipmentFilter() {
        let gymOnly = Program(
            id: "gym-only", name: "", summary: "", daysPerWeek: 3, suitableDays: 3...3,
            goals: Set(TrainingGoal.allCases), levels: Set(ExperienceLevel.allCases),
            workouts: [ProgramWorkout(key: "a", name: "A", exercises: [
                ProgramExercise(
                    options: [ExerciseOption(catalogId: "machine-leg-press", inputType: .weightReps, equipment: [.machine])],
                    role: .main, sets: 3
                ),
            ])],
            sequence: [.workout("a"), .restDay, .workout("a"), .restDay, .workout("a"), .restDay, .restDay],
            weeks: 1
        )
        let home = TrainingProfile(equipment: Set(EquipmentPreset.homeGym.equipment), daysPerWeek: 3)
        #expect(ProgramRecommender.recommend(for: home, programs: [gymOnly]).isEmpty)
        #expect(ProgramRecommender.recommend(for: TrainingProfile(daysPerWeek: 3), programs: [gymOnly]).count == 1)
    }
}

@Suite("Cilj dana tjedno i dani programa")
struct DaysGoalTests {
    @Test("Dani programa prema profilu: dani iz profila ako ih program podržava, inače dani programa")
    func trainingDays() throws {
        #expect(try program("upper-lower-4").trainingDays(for: TrainingProfile(daysPerWeek: 4)) == 4)
        #expect(try program("full-body-3").trainingDays(for: TrainingProfile(daysPerWeek: 4)) == 3)
        #expect(try program("full-body-3").trainingDays(for: TrainingProfile()) == 3)
        #expect(try program("basic-full-body-2").trainingDays(for: TrainingProfile(daysPerWeek: 1)) == 1)
        #expect(try program("ppl-6").trainingDays(for: TrainingProfile(daysPerWeek: 7)) == 6)
    }

    @Test("Smanjenje cilja nudi se samo kad program ima manje dana od cilja")
    func lowerGoal() throws {
        #expect(TrainingProfile(daysPerWeek: 4).lowerDaysGoal(for: try program("full-body-3")) == 3)
        #expect(TrainingProfile(daysPerWeek: 7).lowerDaysGoal(for: try program("ppl-6")) == 6)
        #expect(TrainingProfile(daysPerWeek: 4).lowerDaysGoal(for: try program("upper-lower-4")) == nil)
        #expect(TrainingProfile(daysPerWeek: 2).lowerDaysGoal(for: try program("full-body-3")) == nil)
        #expect(TrainingProfile().lowerDaysGoal(for: try program("full-body-3")) == nil)
    }
}

@Suite("Preseti opreme")
struct EquipmentPresetTests {
    @Test("Teretana je sva oprema, a preset se prepoznaje iz spremljenog popisa")
    func presets() {
        #expect(Set(EquipmentPreset.gym.equipment) == Set(Equipment.allCases))
        for preset in EquipmentPreset.allCases {
            #expect(EquipmentPreset.matching(Array(preset.equipment.reversed())) == preset)
            #expect(preset.equipment.contains(.bodyweight))
        }
        #expect(EquipmentPreset.matching([.kettlebell]) == nil)
        #expect(EquipmentPreset.matching([]) == nil)
    }

    @Test("Profil bez opreme znači teretanu, a vlastita težina je uvijek dostupna")
    func profileEquipment() {
        #expect(TrainingProfile().availableEquipment == Set(Equipment.allCases))
        #expect(TrainingProfile(equipment: [.dumbbell]).availableEquipment == [.dumbbell, .bodyweight])
        #expect(!TrainingProfile().hasAnswers)
        #expect(TrainingProfile(daysPerWeek: 3).hasAnswers)
    }
}
