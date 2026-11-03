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
        total += try removeDuplicateHealthImports(in: context)
        return total
    }

    /// Isti trening ili mjerenje iz Zdravlja uvezeno više puta (npr. na iPhoneu i iPadu prije sinkronizacije)
    /// ima različit `id`, ali isti UUID uzorka u HealthKitu. Ostaje najranije uvezeni zapis.
    @discardableResult
    public static func removeDuplicateHealthImports(in context: ModelContext) throws -> Int {
        var removed = 0
        let imported = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.isImportedFromWorkoutsApp == true }))
        var seenWorkouts = Set<UUID>()
        for session in imported.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let workoutId = session.healthKitWorkoutId else { continue }
            if seenWorkouts.insert(workoutId).inserted { continue }
            context.delete(session)
            removed += 1
        }
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        var seenSamples = Set<UUID>()
        for measurement in measurements.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let sampleId = measurement.healthKitSampleId else { continue }
            if seenSamples.insert(sampleId).inserted { continue }
            context.delete(measurement)
            removed += 1
        }
        if removed > 0 { try context.save() }
        return removed
    }
}
