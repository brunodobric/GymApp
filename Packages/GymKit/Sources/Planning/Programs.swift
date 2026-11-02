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
        weighted("Barbell_Bench_Press_-_Medium_Grip", 4, 6),
        weighted("Dumbbell_Shoulder_Press", 3, 8),
        weighted("Incline_Dumbbell_Press", 3, 10),
        weighted("Side_Lateral_Raise", 3, 15),
        weighted("Triceps_Pushdown", 3, 12),
    ])

    private static let pull = ProgramWorkout(key: "pull", name: "Pull", exercises: [
        bodyweight("Pullups", 3, 8),
        weighted("Bent_Over_Barbell_Row", 4, 8),
        weighted("Seated_Cable_Rows", 3, 10),
        weighted("Face_Pull", 3, 15),
        weighted("Dumbbell_Bicep_Curl", 3, 10),
    ])

    private static let legs = ProgramWorkout(key: "legs", name: "Noge", exercises: [
        weighted("Barbell_Squat", 4, 6),
        weighted("Romanian_Deadlift", 3, 8),
        weighted("Leg_Press", 3, 10),
        weighted("Lying_Leg_Curls", 3, 12),
        weighted("Standing_Calf_Raises", 4, 12),
    ])

    private static let upper = ProgramWorkout(key: "upper", name: "Gornji dio tijela", exercises: [
        weighted("Barbell_Bench_Press_-_Medium_Grip", 3, 8),
        weighted("Bent_Over_Barbell_Row", 3, 8),
        weighted("Dumbbell_Shoulder_Press", 3, 10),
        weighted("Wide-Grip_Lat_Pulldown", 3, 10),
        weighted("Dumbbell_Bicep_Curl", 2, 12),
        weighted("Triceps_Pushdown", 2, 12),
    ])

    private static let lower = ProgramWorkout(key: "lower", name: "Donji dio tijela", exercises: [
        weighted("Barbell_Squat", 4, 6),
        weighted("Romanian_Deadlift", 3, 8),
        weighted("Dumbbell_Lunges", 3, 10),
        weighted("Lying_Leg_Curls", 3, 12),
        weighted("Standing_Calf_Raises", 3, 12),
        weighted("Cable_Crunch", 3, 12),
    ])

    private static let fullBodyA = ProgramWorkout(key: "fullA", name: "Cijelo tijelo A", exercises: [
        weighted("Barbell_Squat", 3, 5),
        weighted("Barbell_Bench_Press_-_Medium_Grip", 3, 5),
        weighted("Bent_Over_Barbell_Row", 3, 8),
        weighted("Standing_Military_Press", 2, 8),
        ProgramExercise(catalogId: "Plank", inputType: .duration, sets: 3, reps: nil),
    ])

    private static let fullBodyB = ProgramWorkout(key: "fullB", name: "Cijelo tijelo B", exercises: [
        weighted("Barbell_Deadlift", 3, 5),
        weighted("Incline_Dumbbell_Press", 3, 8),
        weighted("Wide-Grip_Lat_Pulldown", 3, 10),
        weighted("Leg_Press", 3, 10),
        weighted("Dumbbell_Bicep_Curl", 2, 12),
    ])

    private static let fullBodyC = ProgramWorkout(key: "fullC", name: "Cijelo tijelo C", exercises: [
        weighted("Goblet_Squat", 3, 10),
        weighted("Dumbbell_Bench_Press", 3, 10),
        weighted("Seated_Cable_Rows", 3, 10),
        weighted("Side_Lateral_Raise", 3, 12),
        weighted("Triceps_Pushdown", 2, 12),
        bodyweight("Crunches", 3, 15),
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

    @discardableResult
    public func install(_ program: Program, exerciseName: (String) -> String) throws -> Schedule {
        let templates = TemplateEngine(context: context)
        let schedules = ScheduleEngine(context: context)
        var created: [String: WorkoutTemplate] = [:]

        for workout in program.workouts {
            let template = try templates.createTemplate(name: workout.name)
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

        let schedule = try schedules.createSchedule(name: program.name)
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
