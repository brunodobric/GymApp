import Catalog
import Foundation
import SwiftData

extension CustomExercise {
    /// Sažetak za popis i pretragu, zajednički sa službenim vježbama.
    public var summary: ExerciseSummary {
        ExerciseSummary(
            source: .custom(id: id),
            name: name,
            category: category,
            muscles: muscles,
            equipment: equipment,
            isArchived: isArchived
        )
    }
}

extension ExerciseSummary {
    /// Referenca koju spremaju predlošci i treninzi.
    public var ref: ExerciseRef {
        switch source {
        case .catalog(let id): ExerciseRef(catalogId: id, name: name)
        case .custom(let id): ExerciseRef(customExerciseId: id, name: name)
        }
    }
}

public enum CustomExerciseStore {

    public enum RemovalResult: Equatable, Sendable {
        case deleted
        /// Vježba ima povijest ili je u predlošku, pa je samo skrivena.
        case archived
    }

    /// Je li vježba korištena u nekom treningu ili predlošku.
    public static func isReferenced(_ exercise: CustomExercise, in context: ModelContext) throws -> Bool {
        let id: UUID? = exercise.id
        var sessions = FetchDescriptor<SessionExercise>(predicate: #Predicate { $0.exerciseCustomId == id })
        sessions.fetchLimit = 1
        if try !context.fetch(sessions).isEmpty { return true }
        var templates = FetchDescriptor<TemplateExercise>(predicate: #Predicate { $0.exerciseCustomId == id })
        templates.fetchLimit = 1
        return try !context.fetch(templates).isEmpty
    }

    /// Briše vlastitu vježbu, a ako ima povijest samo je arhivira kako statistika ne bi izgubila podatke.
    @discardableResult
    public static func remove(_ exercise: CustomExercise, in context: ModelContext) throws -> RemovalResult {
        if try isReferenced(exercise, in: context) {
            exercise.isArchived = true
            try context.save()
            return .archived
        }
        context.delete(exercise)
        try context.save()
        return .deleted
    }
}
