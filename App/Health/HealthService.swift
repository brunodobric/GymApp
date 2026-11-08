import Catalog
import Foundation
import HealthKit
import HealthSync
import Models
import OSLog
import Stats
import SwiftData
import WorkoutKit

/// Veza s Apple Zdravljem (specifikacija, odjeljak 6).
///
/// * Dozvole se traže samo za tipove koji se stvarno koriste: zapis treninga te čitanje treninga,
///   kalorija, udaljenosti, pulsa, težine i visine.
/// * Aplikacija radi i bez dozvole: svaka greška ili odbijena dozvola tiho preskače korak.
/// * Logika uvoza i izvoza je u `HealthSync` (GymKit); ovdje je samo pretvorba HealthKit objekata.
@MainActor
final class HealthService {
    static let shared = HealthService()

    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "Health")
    private var isImporting = false

    private static let workoutType = HKObjectType.workoutType()
    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let height = HKQuantityType(.height)
    private static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private static let heartRate = HKQuantityType(.heartRate)
    private static let distanceTypes = [
        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)
    ]

    private static let shareTypes: Set<HKSampleType> = [workoutType]
    private static var readTypes: Set<HKObjectType> {
        Set([workoutType, bodyMass, height, activeEnergy, heartRate] + distanceTypes)
    }

    /// Zdravlje ne postoji na svim uređajima (npr. stariji iPad).
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Prikazuje sistemski list s dozvolama. Sustav ga pokaže samo prvi put; kasnije se dozvole
    /// mijenjaju u aplikaciji Zdravlje, pa poziv odmah završi.
    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        } catch {
            logger.error("Dozvole za Zdravlje: \(error.localizedDescription)")
        }
    }

    // MARK: Spremanje treninga

    /// Sprema završeni trening s iPhonea u Zdravlje, ako je korisnik to dopustio.
    /// Trening snage s kardio vježbama ide kao više treninga jedan za drugim (`HealthWorkoutExport.segments`),
    /// jer jedan HealthKit trening ne može imati i snagu i kardio. Svi nose id treninga iz aplikacije,
    /// a u povijest se veže glavni (najdulji trening snage).
    func saveWorkout(of session: Session, context: ModelContext) async {
        // Trening koji je vodio sat sat je i spremio u Zdravlje (HKWorkoutSession).
        guard isAvailable, Self.isConnected(context: context), session.controllingDevice == .phone,
              session.healthKitWorkoutId == nil,
              store.authorizationStatus(for: Self.workoutType) == .sharingAuthorized
        else { return }
        let custom = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        let info = ExerciseInfoBuilder.provider(catalog: AppServices.bundledCatalog, custom: custom)
        guard let export = HealthWorkoutExport.make(for: session, isCardio: ExerciseInfoBuilder.isCardio(info)) else { return }

        // Glavni trening prvi: ako ostali ne uspiju, trening je ipak povezan sa Zdravljem.
        let order = [export.primaryIndex] + export.segments.indices.filter { $0 != export.primaryIndex }
        for index in order {
            let segment = export.segments[index]
            do {
                let workout = try await save(segment, sessionId: export.sessionId)
                guard index == export.primaryIndex, let workout else { continue }
                let energy = workout.statistics(for: Self.activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
                try HealthImporter(context: context).markExported(
                    sessionId: export.sessionId, workoutId: workout.uuid, activeEnergyKilocalories: energy
                )
            } catch {
                logger.error("Spremanje treninga u Zdravlje: \(error.localizedDescription)")
                // Bez glavnog treninga ostali se ne spremaju, da ponovni pokušaj ne napravi duplikate.
                if index == export.primaryIndex { return }
            }
        }
    }

    private func save(_ segment: HealthWorkoutSegment, sessionId: UUID) async throws -> HKWorkout? {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = segment.activity.hkActivityType
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: segment.start)
        try await builder.addMetadata([
            HKMetadataKeyExternalUUID: sessionId.uuidString,
            HKMetadataKeyIndoorWorkout: true
        ])
        try await builder.endCollection(at: segment.end)
        return try await builder.finishWorkout()
    }

    // MARK: Trening na satu

    /// Budi aplikaciju na satu i traži od nje sesiju treninga snage (`WatchAppDelegate.handle`).
    /// Ako sat nije u blizini ili nema aplikaciju, ništa se ne događa i trening ide samo na iPhoneu.
    func startWatchWorkout() {
        guard isAvailable else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        Task {
            do {
                try await store.startWatchApp(toHandle: configuration)
            } catch {
                logger.info("Trening na satu nije pokrenut: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Uvoz

    /// Uvozi nove kardio treninge, težinu i visinu. Prvi put ide unatrag `HealthImportWindow`,
    /// a nakon toga samo ono što je dodano od zadnjeg uvoza (anchor po tipu podatka).
    func importNewData(context: ModelContext) async {
        guard isAvailable, Self.isConnected(context: context), !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let importer = HealthImporter(context: context)
        do {
            let records = try await newWorkouts()
            let imported = try importer.importWorkouts(records.items) { $0.title }
            records.commit()
            // Kardio odrađen po planu iz rasporeda povezuje se s rasporedom (faza 10) i raspored napreduje.
            if imported > 0 { ReminderScheduler.refresh(context: context) }

            for (type, kind) in [(Self.bodyMass, BodyMeasurementKind.weight), (Self.height, .height)] {
                let samples = try await newBodySamples(of: type, kind: kind)
                try importer.importBodySamples(samples.items)
                samples.commit()
            }
        } catch {
            logger.error("Uvoz iz Zdravlja: \(error.localizedDescription)")
        }
    }

    /// Rezultat upita s novim anchorom koji se sprema tek nakon uspješnog upisa u bazu.
    private struct Batch<Item> {
        let items: [Item]
        let commit: () -> Void
    }

    private func newWorkouts() async throws -> Batch<HealthWorkoutRecord> {
        let since = HealthImportWindow.start(days: HealthImportWindow.workoutDays)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let key = "health.anchor.workouts"
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.workout(predicate)], anchor: Self.anchor(forKey: key))
        let result = try await descriptor.result(for: store)
        var records: [HealthWorkoutRecord] = []
        for workout in result.addedSamples {
            var item = record(from: workout)
            // Plan iz WorkoutKita po kojem je trening odrađen na satu. Samo za Appleove kardio treninge.
            if item.isFromApple, item.activity.isCardio, let plan = try? await workout.workoutPlan {
                item.workoutPlanId = plan.id
            }
            records.append(item)
        }
        return Batch(items: records) { Self.store(result.newAnchor, forKey: key) }
    }

    private func newBodySamples(of type: HKQuantityType, kind: BodyMeasurementKind) async throws -> Batch<HealthBodySample> {
        let since = HealthImportWindow.start(days: HealthImportWindow.bodyDays)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let key = "health.anchor.\(type.identifier)"
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)], anchor: Self.anchor(forKey: key)
        )
        let result = try await descriptor.result(for: store)
        let unit: HKUnit = kind == .weight ? .gramUnit(with: .kilo) : .meterUnit(with: .centi)
        let samples = result.addedSamples.map {
            HealthBodySample(uuid: $0.uuid, kind: kind, value: $0.quantity.doubleValue(for: unit), date: $0.startDate)
        }
        return Batch(items: samples) { Self.store(result.newAnchor, forKey: key) }
    }

    private func record(from workout: HKWorkout) -> HealthWorkoutRecord {
        let energy = workout.statistics(for: Self.activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let distance = Self.distanceTypes.lazy
            .compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
            .first { $0 > 0 }
        let heartRate = workout.statistics(for: Self.heartRate)?.averageQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
        let external = (workout.metadata?[HKMetadataKeyExternalUUID] as? String).flatMap(UUID.init(uuidString:))
        return HealthWorkoutRecord(
            uuid: workout.uuid,
            activity: HealthActivity(workout.workoutActivityType),
            start: workout.startDate,
            end: workout.endDate,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            externalUUID: external,
            activeEnergyKilocalories: energy,
            distanceMeters: distance,
            averageHeartRate: heartRate
        )
    }

    // MARK: Pomoćno

    private static func isConnected(context: ModelContext) -> Bool {
        (try? GymQueries(context: context).settings().wantsHealthKit) ?? false
    }

    /// Anchori su vezani uz Zdravlje na ovom uređaju, pa se čuvaju lokalno, a ne u sinkroniziranoj bazi.
    private static func anchor(forKey key: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func store(_ anchor: HKQueryAnchor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension HealthActivity {
    // swiftlint:disable:next cyclomatic_complexity
    init(_ type: HKWorkoutActivityType) {
        switch type {
        case .running: self = .running
        case .walking: self = .walking
        case .hiking: self = .hiking
        case .cycling, .handCycling: self = .cycling
        case .swimming: self = .swimming
        case .rowing: self = .rowing
        case .elliptical: self = .elliptical
        case .stairClimbing, .stairs, .stepTraining: self = .stairs
        case .highIntensityIntervalTraining: self = .highIntensityIntervalTraining
        case .mixedCardio, .cardioDance: self = .mixedCardio
        case .jumpRope: self = .jumpRope
        case .crossCountrySkiing: self = .crossCountrySkiing
        case .socialDance: self = .dance
        case .traditionalStrengthTraining: self = .traditionalStrengthTraining
        case .functionalStrengthTraining: self = .functionalStrengthTraining
        case .coreTraining: self = .coreTraining
        default: self = .other
        }
    }

    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling: .cycling
        case .swimming: .swimming
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .stairs: .stairClimbing
        case .highIntensityIntervalTraining: .highIntensityIntervalTraining
        case .mixedCardio: .mixedCardio
        case .jumpRope: .jumpRope
        case .crossCountrySkiing: .crossCountrySkiing
        case .dance: .socialDance
        case .traditionalStrengthTraining: .traditionalStrengthTraining
        case .functionalStrengthTraining: .functionalStrengthTraining
        case .coreTraining: .coreTraining
        case .other: .other
        }
    }

    /// Naziv uvezenog treninga u povijesti.
    var title: String {
        switch self {
        case .running: String(localized: "Trčanje")
        case .walking: String(localized: "Hodanje")
        case .hiking: String(localized: "Planinarenje")
        case .cycling: String(localized: "Vožnja bicikla")
        case .swimming: String(localized: "Plivanje")
        case .rowing: String(localized: "Veslanje")
        case .elliptical: String(localized: "Eliptični trenažer")
        case .stairs: String(localized: "Stepenice")
        case .highIntensityIntervalTraining: String(localized: "HIIT")
        case .mixedCardio: String(localized: "Kardio")
        case .jumpRope: String(localized: "Preskakanje užeta")
        case .crossCountrySkiing: String(localized: "Skijaško trčanje")
        case .dance: String(localized: "Ples")
        case .traditionalStrengthTraining, .functionalStrengthTraining: String(localized: "Trening snage")
        case .coreTraining: String(localized: "Core trening")
        case .other: String(localized: "Trening")
        }
    }
}
