import Foundation
import SwiftData

/// Uklanjanje duplikata po UUID-u. CloudKit može isporučiti isti zapis dvaput (npr. nakon
/// istovremenog stvaranja na dva uređaja), a bez `unique` ograničenja baza to ne sprječava.
public enum Deduplication {

    /// Ostavlja po jedan zapis za svaki UUID i briše ostale. Vraća broj obrisanih zapisa.
    @discardableResult
    public static func removeDuplicates<Model: PersistentModel>(
        of type: Model.Type,
        id: KeyPath<Model, UUID>,
        in context: ModelContext
    ) throws -> Int {
        let all = try context.fetch(FetchDescriptor<Model>())
        var seen = Set<UUID>()
        var removed = 0
        for item in all {
            if seen.insert(item[keyPath: id]).inserted { continue }
            context.delete(item)
            removed += 1
        }
        if removed > 0 { try context.save() }
        return removed
    }

    /// Pokreće uklanjanje duplikata za modele koji se stvaraju iz više uređaja.
    @discardableResult
    public static func removeAllDuplicates(in context: ModelContext) throws -> Int {
        var total = 0
        total += try removeDuplicates(of: Session.self, id: \.id, in: context)
        total += try removeDuplicates(of: SessionExercise.self, id: \.id, in: context)
        total += try removeDuplicates(of: SetLog.self, id: \.id, in: context)
        total += try removeDuplicates(of: WorkoutTemplate.self, id: \.id, in: context)
        total += try removeDuplicates(of: Schedule.self, id: \.id, in: context)
        total += try removeDuplicates(of: BodyMeasurement.self, id: \.id, in: context)
        total += try removeDuplicates(of: CustomExercise.self, id: \.id, in: context)
        return total
    }
}
