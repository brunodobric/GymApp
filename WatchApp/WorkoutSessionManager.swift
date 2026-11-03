import Foundation
import HealthKit
import Observation
import OSLog

/// `HKWorkoutSession` i `HKLiveWorkoutBuilder` za trening koji vodi sat (specifikacija, odjeljak 6):
/// puls i kalorije uživo, aplikacija ostaje aktivna dok je zapešće spušteno, a na kraju se trening
/// sprema u Zdravlje (ako je korisnik to uključio). Bez dozvole trening radi i dalje, samo bez pulsa.
@MainActor
@Observable
final class WorkoutSessionManager: NSObject {

    struct Result: Sendable {
        var workoutId: UUID?
        var activeEnergyKilocalories: Double?
        var averageHeartRate: Double?
    }

    private(set) var heartRate: Double?
    private(set) var activeEnergyKilocalories: Double?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private let logger = Logger(subsystem: "com.brunodobric.gymapp.watchkitapp", category: "Workout")

    private static let heartRateType = HKQuantityType(.heartRate)
    private static let energyType = HKQuantityType(.activeEnergyBurned)
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    var isRunning: Bool { session != nil }

    private func requestAuthorization() async {
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType(), Self.energyType],
                read: [Self.heartRateType, Self.energyType]
            )
        } catch {
            logger.error("Dozvole za Zdravlje: \(error.localizedDescription)")
        }
    }

    /// Pokreće sesiju treninga snage. `sessionID` ide u metapodatke, pa iPhone prepoznaje trening u Zdravlju.
    func start(sessionID: UUID, at date: Date) async {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        await requestAuthorization()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            attach(session, builder: builder)
            session.startActivity(with: date)
            try await builder.beginCollection(at: date)
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: sessionID.uuidString,
                HKMetadataKeyIndoorWorkout: true
            ])
        } catch {
            logger.error("Pokretanje treninga: \(error.localizedDescription)")
            reset()
        }
    }

    /// Nakon rušenja ili gašenja aplikacije usred treninga sustav je ponovno pokreće i vraća sesiju.
    func recover() {
        guard session == nil else { return }
        store.recoverActiveWorkoutSession { session, error in
            guard let session else { return }
            Task { @MainActor in
                WatchWorkoutStore.shared.health.attach(session, builder: session.associatedWorkoutBuilder())
            }
            if let error {
                Logger(subsystem: "com.brunodobric.gymapp.watchkitapp", category: "Workout")
                    .error("Oporavak treninga: \(error.localizedDescription)")
            }
        }
    }

    /// Završava sesiju. S `save` se trening sprema u Zdravlje, inače se odbacuje (puls i kalorije ostaju u aplikaciji).
    func end(at date: Date, save: Bool) async -> Result {
        guard let session, let builder else { return Result() }
        session.end()
        var result = Result()
        do {
            try await builder.endCollection(at: date)
            result.activeEnergyKilocalories = builder.statistics(for: Self.energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            result.averageHeartRate = builder.statistics(for: Self.heartRateType)?.averageQuantity()?.doubleValue(for: Self.beatsPerMinute)
            if save {
                result.workoutId = try await builder.finishWorkout()?.uuid
            } else {
                builder.discardWorkout()
            }
        } catch {
            logger.error("Završetak treninga: \(error.localizedDescription)")
        }
        reset()
        return result
    }

    /// Kao `end`, ali čeka najviše `timeout`. Ako Zdravlje ne odgovori, trening se ipak završava
    /// (bez pulsa i kalorija), da sat ne ostane zapeo u treningu.
    func end(at date: Date, save: Bool, timeout: Duration) async -> Result {
        let gate = ResumeGate()
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let result = await self.end(at: date, save: save)
                if gate.open() { continuation.resume(returning: result) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if gate.open() { continuation.resume(returning: Result()) }
            }
        }
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        reset()
    }

    fileprivate func attach(_ session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
    }

    private func reset() {
        session = nil
        builder = nil
        heartRate = nil
        activeEnergyKilocalories = nil
    }

    fileprivate func update(heartRate: Double?, energy: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let energy { activeEnergyKilocalories = energy }
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState, date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Logger(subsystem: "com.brunodobric.gymapp.watchkitapp", category: "Workout")
            .error("Sesija treninga: \(error.localizedDescription)")
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Statička svojstva klase pripadaju glavnom actoru, pa se tipovi ovdje stvaraju iznova.
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        var heartRate: Double?
        var energy: Double?
        if collectedTypes.contains(heartRateType) {
            heartRate = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if collectedTypes.contains(energyType) {
            energy = workoutBuilder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        Task { @MainActor [heartRate, energy] in
            WatchWorkoutStore.shared.health.update(heartRate: heartRate, energy: energy)
        }
    }
}

/// Propušta samo prvi od dva rezultata (Zdravlje ili istek vremena).
@MainActor
private final class ResumeGate {
    private var isOpen = true

    func open() -> Bool {
        defer { isOpen = false }
        return isOpen
    }
}
