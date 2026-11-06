import Catalog
import Foundation
import SwiftData

/// Prevodi spremljene id-jeve vježbi iz starog kataloga (free-exercise-db) u id-jeve MoveKit kataloga.
///
/// Treninzi, predlošci i izmjene ciklusa pamte vježbu po id-ju kataloga. Kad se id promijeni,
/// zapis dobiva novi id i ključ. Vježba koja u novom katalogu nema para postaje vlastita vježba
/// istog naziva, pa povijest, rekordi i predlošci ostaju. Id koji katalog ne poznaje (ni kao stari)
/// ne dira se.
///
/// Migracija je idempotentna: pokreće se pri svakom pokretanju aplikacije, nakon uvoza i nakon
/// sinkronizacije, jer zapisi sa starog uređaja mogu stići kasnije.
public enum CatalogIdMigration {

    public struct Result: Equatable, Sendable {
        /// Zapisi kojima je id kataloga promijenjen.
        public var renamed = 0
        /// Zapisi prebačeni na vlastitu vježbu.
        public var convertedToCustom = 0
        /// Novostvorene vlastite vježbe.
        public var createdCustomExercises = 0

        public init() {}

        public var changed: Bool { renamed + convertedToCustom > 0 }
    }

    @discardableResult
    public static func migrate(in context: ModelContext, catalog: ExerciseCatalog) throws -> Result {
        var result = Result()
        var customs = CustomLookup(context: context)

        /// Nova referenca za stari id ili nil kad zapis treba ostati kakav je.
        func replacement(for ref: ExerciseRef, inputType: ExerciseInputType?) throws -> ExerciseRef? {
            guard let id = ref.catalogId else { return nil }
            switch catalog.resolve(id) {
            case .current, .unknown:
                return nil
            case .renamed(let newID):
                result.renamed += 1
                return ExerciseRef(catalogId: newID, name: ref.name)
            case .removed:
                result.convertedToCustom += 1
                let custom = try customs.exercise(
                    named: ref.name.isEmpty ? id : ref.name,
                    inputType: inputType ?? .weightReps,
                    created: &result.createdCustomExercises
                )
                return custom.ref
            }
        }

        for exercise in try context.fetch(FetchDescriptor<SessionExercise>()) where exercise.exerciseCatalogId != nil {
            if let ref = try replacement(for: exercise.exercise, inputType: exercise.inputType) {
                exercise.exercise = ref
            }
        }
        for exercise in try context.fetch(FetchDescriptor<TemplateExercise>()) where exercise.exerciseCatalogId != nil {
            if let ref = try replacement(for: exercise.exercise, inputType: exercise.inputType) {
                exercise.exercise = ref
            }
        }
        for override in try context.fetch(FetchDescriptor<CycleOverride>()) {
            if let current = override.replacement,
               let ref = try replacement(for: current, inputType: override.replacementInputType) {
                override.replacement = ref
            }
            if let key = override.targetExerciseKey,
               let target = ExerciseRef(key: key, name: ""),
               let ref = try replacement(for: target, inputType: nil) {
                override.targetExerciseKey = ref.key
            }
        }

        if result.changed || result.createdCustomExercises > 0 {
            try context.save()
        }
        return result
    }

    /// Vlastite vježbe po nazivu (bez razlike u velikim slovima), da se za isti naziv ne stvaraju duplikati.
    private struct CustomLookup {
        let context: ModelContext
        private var byName: [String: CustomExercise]?

        init(context: ModelContext) {
            self.context = context
        }

        private static func key(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        mutating func exercise(named name: String, inputType: ExerciseInputType, created: inout Int) throws -> CustomExercise {
            if byName == nil {
                let all = try context.fetch(FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.createdAt)]))
                byName = Dictionary(all.map { (Self.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
            }
            if let existing = byName?[Self.key(name)] { return existing }
            let custom = CustomExercise(name: name, inputType: inputType)
            context.insert(custom)
            byName?[Self.key(name)] = custom
            created += 1
            return custom
        }
    }
}
