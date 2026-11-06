// Demo podaci za snimke zaslona za App Store (faza 14). Samo u Debug buildu: u Releaseu je modul prazan.
#if DEBUG
import Catalog
import Foundation
import Models
import Planning
import SwiftData
import Training

/// Puni praznu bazu uvjerljivom poviješću: gotov program Upper/Lower, nekoliko tjedana treninga s postupnim
/// napretkom (pa ima i rekorda), mjere tijela i postavke s obavljenim onboardingom. Treninzi idu kroz
/// `TemplateStarter` i `WorkoutEngine`, kao u aplikaciji, pa su podaci isti kao da ih je korisnik upisao.
public struct DemoDataGenerator {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Program iz kojeg nastaju treninzi.
    public static let programId = "upper-lower-4"

    /// Dani u tjednu s treningom (1 = nedjelja): ponedjeljak, utorak, četvrtak i petak.
    static let trainingWeekdays: Set<Int> = [2, 3, 5, 6]

    /// Početne težine (kg) za vježbe programa. Ostale počinju s 20 kg.
    static let startingWeights: [String: Double] = [
        "barbell-bench-press": 70,
        "barbell-bent-over-row": 60,
        "dumbbell-seated-overhead-press": 20,
        "wide-grip-lat-pulldown": 55,
        "dumbbell-curl": 12,
        "cable-bar-pushdown": 25,
        "barbell-squat": 90,
        "barbell-romanian-deadlift": 80,
        "dumbbell-alternating-forward-lunge": 16,
        "lying-leg-curl": 35,
        "standing-calf-raise-machine": 60,
        "kneeling-cable-crunch": 30,
    ]

    /// - Parameters:
    ///   - weeks: koliko tjedana unatrag ima treninga
    ///   - names: nazivi na jeziku sučelja (program, treninzi i vježbe iz kataloga)
    ///   - now: kraj povijesti; danas se ne trenira, da "Započni" nudi sljedeći trening
    @discardableResult
    public func populate(
        weeks: Int = 10,
        scheduleName: String? = nil,
        workoutName: (ProgramWorkout) -> String = { $0.name },
        exerciseName: (String) -> String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Int {
        let settings = try GymQueries(context: context).settings()
        settings.onboardingCompleted = true
        settings.notificationsEnabled = false
        settings.wantsHealthKit = false

        guard let program = ProgramLibrary.all.first(where: { $0.id == Self.programId }) else { return 0 }
        let schedule = try ProgramInstaller(context: context).install(
            program, name: scheduleName, workoutName: workoutName, exerciseName: exerciseName
        )

        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -weeks * 7, to: today) else { return 0 }
        let schedules = ScheduleEngine(context: context)
        let engine = WorkoutEngine(context: context)
        var day = first
        var count = 0
        while day < today {
            if Self.trainingWeekdays.contains(calendar.component(.weekday, from: day)),
               let planned = try schedules.nextWorkout(of: schedule) {
                let progress = day.timeIntervalSince(first) / max(1, today.timeIntervalSince(first))
                let start = day.addingTimeInterval(18 * 3600 + Double(count % 3) * 900)
                try logWorkout(planned, start: start, progress: progress, engine: engine)
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        try addMeasurements(from: first, until: today, calendar: calendar)
        try context.save()
        return count
    }

    private func logWorkout(_ planned: PlannedWorkout, start: Date, progress: Double, engine: WorkoutEngine) throws {
        let session = try TemplateStarter(context: context).start(planned, now: start)
        var time = start
        for exercise in engine.visibleExercises(in: session) {
            let base = Self.startingWeights[exercise.exerciseCatalogId ?? ""] ?? 20
            // Oko 12 % napretka kroz cijelo razdoblje, zaokruženo na 2,5 kg.
            let weight = (base * (1 + 0.12 * progress) / 2.5).rounded() * 2.5
            let sets = exercise.orderedSets
            for (index, set) in sets.enumerated() {
                let target = set.reps ?? 8
                // Zadnja serija je teža, pa ponekad ide ponavljanje manje.
                set.reps = index == sets.count - 1 && Int(progress * 10) % 2 == 1 ? max(1, target - 1) : target
                if exercise.inputType == .weightReps { set.weightKg = weight }
                time = time.addingTimeInterval(150)
                _ = try engine.completeSet(set, defaultRestSeconds: 90, now: time)
            }
        }
        try engine.finishSession(session, now: time.addingTimeInterval(120))
        try ScheduleEngine(context: context).sessionFinished(session)
    }

    private func addMeasurements(from first: Date, until today: Date, calendar: Calendar) throws {
        context.insert(BodyMeasurement(kind: .height, value: 182, date: first))
        var date = first
        var week = 0.0
        while date < today {
            context.insert(BodyMeasurement(kind: .weight, value: ((84 - 0.2 * week) * 10).rounded() / 10, date: date))
            if Int(week) % 2 == 0 {
                context.insert(BodyMeasurement(kind: .waist, value: ((88 - 0.3 * week) * 10).rounded() / 10, date: date))
            }
            guard let next = calendar.date(byAdding: .day, value: 7, to: date) else { break }
            date = next
            week += 1
        }
    }
}
#endif
