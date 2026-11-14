import Foundation
import SwiftData
import Units

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
        // Čita se samo UUID: provjera nakon svakog uvoza ne smije učitati cijelu bazu u memoriju.
        var descriptor = FetchDescriptor<Model>()
        descriptor.propertiesToFetch = [id]
        let all = try context.fetch(descriptor)
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
        // Podaci iz Zdravlja koji su stigli u korisničku bazu (starija verzija aplikacije na drugom uređaju,
        // sigurnosna kopija) prelaze u lokalnu bazu, gdje ih nema više od jednog po UUID-u iz HealthKita.
        total += try HealthLocalStore(context: context).moveHealthDataOutOfUserStore()
        total += try removeDuplicateSettings(in: context)
        total += try removeDuplicateDashboardCards(in: context)
        return total
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
    /// Jedinica težine iz važećeg zapisa postavki, a bez postavki kilogrami.
    static func weightUnit(in all: [UserSettings]) -> WeightUnit {
        preferred(in: all)?.weightUnit ?? .kilograms
    }

    /// Koji od više zapisa postavki vrijedi. Isti zapis promijenjen na dva uređaja razrješava CloudKit
    /// (vrijedi zadnja promjena), a više zapisa nastaje samo kad novi uređaj stvori svoje postavke prije
    /// nego što stignu one iz iClouda. Tada prednost ima zapis s obavljenim onboardingom, zatim onaj koji
    /// se više razlikuje od zadanih vrijednosti (korisnik ga je mijenjao), zatim najmanji `id`.
    /// Pravilo je isto na svim uređajima, pa svi zadrže isti zapis.
    static func preferred(in all: [UserSettings]) -> UserSettings? {
        // Uobičajeno je jedan zapis: bez usporedbe (i bez stvaranja zapisa sa zadanim vrijednostima),
        // jer se ovo zove pri svakom iscrtavanju ekrana koji čita postavke.
        guard all.count > 1 else { return all.first }
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
            (compoundRestSeconds, defaults.compoundRestSeconds),
            (themeRaw, defaults.themeRaw),
            (accentColorRaw, defaults.accentColorRaw),
            (effortScaleRaw, defaults.effortScaleRaw),
            (prEnabled, defaults.prEnabled),
            (trackedPRKindsRaw, defaults.trackedPRKindsRaw),
            (prExcludedExercisesRaw, defaults.prExcludedExercisesRaw),
            (statsDetailRaw, defaults.statsDetailRaw),
            (sexRaw, defaults.sexRaw),
            (restEndSoundEnabled, defaults.restEndSoundEnabled),
            (availablePlatesRaw, defaults.availablePlatesRaw),
            (barbellWeightKg, defaults.barbellWeightKg),
            (equipmentWeightStepsRaw, defaults.equipmentWeightStepsRaw),
            (exerciseWeightStepsRaw, defaults.exerciseWeightStepsRaw),
            (exerciseNotesRaw, defaults.exerciseNotesRaw),
            (goalRaw, defaults.goalRaw),
            (experienceRaw, defaults.experienceRaw),
            (equipmentRaw, defaults.equipmentRaw),
            (trainingDaysPerWeek, defaults.trainingDaysPerWeek),
            (wantsHealthKit, defaults.wantsHealthKit),
            (notificationsEnabled, defaults.notificationsEnabled),
            (restNotificationEnabled, defaults.restNotificationEnabled),
            (startsWatchWorkout, defaults.startsWatchWorkout),
            (suggestsHeavierWeight, defaults.suggestsHeavierWeight),
            (bodyMapFemale, defaults.bodyMapFemale),
            (liveActivityFollowsApp, defaults.liveActivityFollowsApp),
            (liveActivityThemeRaw, defaults.liveActivityThemeRaw),
            (liveActivityAccentRaw, defaults.liveActivityAccentRaw),
        ]
        return pairs.filter { $0.0 != $0.1 }.count
    }
}
