import Catalog
import Foundation
import Models
import SwiftData

public struct ProgramExercise: Equatable, Sendable {
    public let catalogId: String
    public let inputType: ExerciseInputType
    public let sets: Int
    /// Ciljana ponavljanja; nil za vježbe s trajanjem.
    public let reps: Int?
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

/// Gotov program: skup treninga i njihov redoslijed.
public struct Program: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let daysPerWeek: Int
    public let workouts: [ProgramWorkout]
    public let sequence: [ProgramStep]
}

public enum ProgramLibrary {

    private static func weighted(_ id: String, _ sets: Int, _ reps: Int) -> ProgramExercise {
        ProgramExercise(catalogId: id, inputType: .weightReps, sets: sets, reps: reps)
    }

    private static func bodyweight(_ id: String, _ sets: Int, _ reps: Int) -> ProgramExercise {
        ProgramExercise(catalogId: id, inputType: .bodyweight, sets: sets, reps: reps)
    }

    private static let push = ProgramWorkout(key: "push", name: "Push", exercises: [
        weighted("barbell-bench-press", 4, 6),
        weighted("dumbbell-seated-overhead-press", 3, 8),
        weighted("dumbbell-incline-bench-press", 3, 10),
        weighted("dumbbell-lateral-raise", 3, 15),
        weighted("cable-bar-pushdown", 3, 12),
    ])

    private static let pull = ProgramWorkout(key: "pull", name: "Pull", exercises: [
        bodyweight("pull-ups", 3, 8),
        weighted("barbell-bent-over-row", 4, 8),
        weighted("machine-seated-cable-row", 3, 10),
        weighted("machine-face-pulls", 3, 15),
        weighted("dumbbell-curl", 3, 10),
    ])

    private static let legs = ProgramWorkout(key: "legs", name: "Noge", exercises: [
        weighted("barbell-squat", 4, 6),
        weighted("barbell-romanian-deadlift", 3, 8),
        weighted("machine-leg-press", 3, 10),
        weighted("lying-leg-curl", 3, 12),
        weighted("standing-calf-raise-machine", 4, 12),
    ])

    private static let upper = ProgramWorkout(key: "upper", name: "Gornji dio tijela", exercises: [
        weighted("barbell-bench-press", 3, 8),
        weighted("barbell-bent-over-row", 3, 8),
        weighted("dumbbell-seated-overhead-press", 3, 10),
        weighted("wide-grip-lat-pulldown", 3, 10),
        weighted("dumbbell-curl", 2, 12),
        weighted("cable-bar-pushdown", 2, 12),
    ])

    private static let lower = ProgramWorkout(key: "lower", name: "Donji dio tijela", exercises: [
        weighted("barbell-squat", 4, 6),
        weighted("barbell-romanian-deadlift", 3, 8),
        weighted("dumbbell-alternating-forward-lunge", 3, 10),
        weighted("lying-leg-curl", 3, 12),
        weighted("standing-calf-raise-machine", 3, 12),
        weighted("kneeling-cable-crunch", 3, 12),
    ])

    private static let fullBodyA = ProgramWorkout(key: "fullA", name: "Cijelo tijelo A", exercises: [
        weighted("barbell-squat", 3, 5),
        weighted("barbell-bench-press", 3, 5),
        weighted("barbell-bent-over-row", 3, 8),
        weighted("barbell-overhead-press", 2, 8),
        ProgramExercise(catalogId: "front-plank", inputType: .duration, sets: 3, reps: nil),
    ])

    private static let fullBodyB = ProgramWorkout(key: "fullB", name: "Cijelo tijelo B", exercises: [
        weighted("barbell-deadlift", 3, 5),
        weighted("dumbbell-incline-bench-press", 3, 8),
        weighted("wide-grip-lat-pulldown", 3, 10),
        weighted("machine-leg-press", 3, 10),
        weighted("dumbbell-curl", 2, 12),
    ])

    private static let fullBodyC = ProgramWorkout(key: "fullC", name: "Cijelo tijelo C", exercises: [
        weighted("kettlebell-goblet-squat", 3, 10),
        weighted("dumbbell-bench-press", 3, 10),
        weighted("machine-seated-cable-row", 3, 10),
        weighted("dumbbell-lateral-raise", 3, 12),
        weighted("cable-bar-pushdown", 2, 12),
        bodyweight("crunches", 3, 15),
    ])

    private static func pushPullLegs(days: Int) -> Program {
        let cycle = ["push", "pull", "legs", "push", "pull", "legs"]
        let steps = cycle.prefix(days).map { ProgramStep.workout($0) } + [.restDay]
        return Program(
            id: "ppl-\(days)", name: "Push/Pull/Legs (\(days) dana)",
            summary: "Guranje, povlačenje i noge u zasebnim danima, \(days) treninga u nizu pa jedan dan odmora.",
            daysPerWeek: days, workouts: [push, pull, legs], sequence: steps
        )
    }

    public static let all: [Program] = [
        Program(
            id: "full-body-3", name: "Full Body (3 dana)",
            summary: "Tri treninga cijelog tijela tjedno s danom odmora između.",
            daysPerWeek: 3, workouts: [fullBodyA, fullBodyB, fullBodyC],
            sequence: [.workout("fullA"), .restDay, .workout("fullB"), .restDay, .workout("fullC"), .restDay, .restDay]
        ),
        Program(
            id: "upper-lower-4", name: "Upper/Lower (4 dana)",
            summary: "Dva dana gornjeg i dva dana donjeg dijela tijela tjedno.",
            daysPerWeek: 4, workouts: [upper, lower],
            sequence: [.workout("upper"), .workout("lower"), .restDay, .workout("upper"), .workout("lower"), .restDay, .restDay]
        ),
        pushPullLegs(days: 3),
        pushPullLegs(days: 4),
        pushPullLegs(days: 5),
        pushPullLegs(days: 6),
    ]
}

/// Stvara predloške i raspored iz gotovog programa. Nazive vježbi daje pozivatelj (katalog je na jeziku korisnika).
public struct ProgramInstaller {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// - Parameters:
    ///   - name: naziv rasporeda na jeziku sučelja (zadano: hrvatski naziv programa)
    ///   - workoutName: naziv treninga na jeziku sučelja (zadano: hrvatski naziv)
    @discardableResult
    public func install(
        _ program: Program,
        name: String? = nil,
        workoutName: (ProgramWorkout) -> String = { $0.name },
        exerciseName: (String) -> String
    ) throws -> Schedule {
        let templates = TemplateEngine(context: context)
        let schedules = ScheduleEngine(context: context)
        var created: [String: WorkoutTemplate] = [:]

        for workout in program.workouts {
            let template = try templates.createTemplate(name: workoutName(workout))
            for item in workout.exercises {
                let ref = ExerciseRef(catalogId: item.catalogId, name: exerciseName(item.catalogId))
                let exercise = try templates.addExercise(ref, inputType: item.inputType, to: template, setCount: item.sets)
                if let reps = item.reps {
                    for set in exercise.orderedSets { set.targetReps = reps }
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
        return schedule
    }
}
