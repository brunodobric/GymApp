import Catalog
import Foundation
import Models
import SwiftData

/// Vježba iz odrađenih treninga, za odabir grafa napretka i usporedbe.
public struct DoneExercise: Identifiable, Hashable, Sendable {
    public let key: String
    public let name: String
    public var id: String { key }

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }

    public var ref: ExerciseRef? { ExerciseRef(key: key, name: name) }
}

public enum DoneExercises {
    /// Različite vježbe iz završenih treninga, abecedno. Izbačene vježbe se ne broje.
    public static func list(from exercises: [SessionExercise]) -> [DoneExercise] {
        var seen = Set<String>()
        var result: [DoneExercise] = []
        for exercise in exercises
        where !exercise.isRemoved && exercise.session?.state == .finished && !exercise.exerciseKey.isEmpty {
            if seen.insert(exercise.exerciseKey).inserted {
                result.append(DoneExercise(key: exercise.exerciseKey, name: exercise.exerciseName))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Dohvaća vježbe jednom (npr. pri otvaranju ekrana), umjesto da ekran prati sve vježbe iz povijesti.
    public static func fetch(in context: ModelContext) throws -> [DoneExercise] {
        let descriptor = FetchDescriptor<SessionExercise>(predicate: #Predicate { $0.isRemoved == false })
        return list(from: try context.fetch(descriptor))
    }
}
