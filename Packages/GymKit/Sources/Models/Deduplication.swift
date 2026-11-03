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
        total += try removeDuplicateSettings(in: context)
        total += try removeDuplicateDashboardCards(in: context)
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

    /// Svaki uređaj stvara svoj zapis postavki, pa ih nakon sinkronizacije može biti više.
    /// Ostaje jedan, po istom pravilu na svim uređajima (`UserSettings.preferred(in:)`).
    @discardableResult
    public static func removeDuplicateSettings(in context: ModelContext) throws -> Int {
        let all = try context.fetch(FetchDescriptor<UserSettings>())
        guard all.count > 1, let kept = UserSettings.preferred(in: all) else { return 0 }
        var removed = 0
        for settings in all where settings.persistentModelID != kept.persistentModelID {
            context.delete(settings)
            removed += 1
        }
        try context.save()
        return removed
    }

    /// Ista vrsta kartice dodana na dva uređaja. Ostaje kartica s manjim `orderIndex`, a redoslijed se ponovno numerira.
    /// Kartice nepoznate vrste (iz novije verzije aplikacije) se ne diraju.
    @discardableResult
    public static func removeDuplicateDashboardCards(in context: ModelContext) throws -> Int {
        let cards = try context.fetch(FetchDescriptor<DashboardCard>())
            .sorted { ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString) }
        var seen = Set<String>()
        var kept: [DashboardCard] = []
        var removed = 0
        for card in cards {
            if DashboardCardKind(rawValue: card.kindRaw) != nil, !seen.insert(card.kindRaw).inserted {
                context.delete(card)
                removed += 1
            } else {
                kept.append(card)
            }
        }
        guard removed > 0 else { return 0 }
        for (index, card) in kept.enumerated() where card.orderIndex != index {
            card.orderIndex = index
        }
        try context.save()
        return removed
    }
}

public extension UserSettings {
    /// Koji od više zapisa postavki vrijedi. Isti zapis promijenjen na dva uređaja razrješava CloudKit
    /// (vrijedi zadnja promjena), a više zapisa nastaje samo kad novi uređaj stvori svoje postavke prije
    /// nego što stignu one iz iClouda. Tada prednost ima zapis s obavljenim onboardingom, zatim onaj koji
    /// se više razlikuje od zadanih vrijednosti (korisnik ga je mijenjao), zatim najmanji `id`.
    /// Pravilo je isto na svim uređajima, pa svi zadrže isti zapis.
    static func preferred(in all: [UserSettings]) -> UserSettings? {
        let defaults = UserSettings()
        return all.min { lhs, rhs in
            if lhs.onboardingCompleted != rhs.onboardingCompleted { return lhs.onboardingCompleted }
            let lhsChanges = lhs.changeCount(from: defaults)
            let rhsChanges = rhs.changeCount(from: defaults)
            if lhsChanges != rhsChanges { return lhsChanges > rhsChanges }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Koliko se postavki razlikuje od zadanih.
    func changeCount(from defaults: UserSettings) -> Int {
        let pairs: [(AnyHashable, AnyHashable)] = [
            (weightUnitRaw, defaults.weightUnitRaw),
            (defaultRestSeconds, defaults.defaultRestSeconds),
            (themeRaw, defaults.themeRaw),
            (accentColorRaw, defaults.accentColorRaw),
            (effortScaleRaw, defaults.effortScaleRaw),
            (prEnabled, defaults.prEnabled),
            (trackedPRKindsRaw, defaults.trackedPRKindsRaw),
            (restEndSoundEnabled, defaults.restEndSoundEnabled),
            (availablePlatesRaw, defaults.availablePlatesRaw),
            (barbellWeightKg, defaults.barbellWeightKg),
            (goalRaw, defaults.goalRaw),
            (experienceRaw, defaults.experienceRaw),
            (equipmentRaw, defaults.equipmentRaw),
            (trainingDaysPerWeek, defaults.trainingDaysPerWeek),
            (wantsHealthKit, defaults.wantsHealthKit),
            (notificationsEnabled, defaults.notificationsEnabled),
            (bodyMapFemale, defaults.bodyMapFemale),
        ]
        return pairs.filter { $0.0 != $0.1 }.count
    }
}
