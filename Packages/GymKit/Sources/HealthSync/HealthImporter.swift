import Foundation
import Models
import SwiftData

/// Upisuje podatke iz Zdravlja u lokalnu bazu (`HealthLocal.swift`), bez duplikata.
///
/// Lokalna baza se ne sinkronizira: svaki uređaj sam čita Zdravlje. Duplikat se prepoznaje po UUID-u
/// uzorka u HealthKitu (`HealthWorkout.healthKitWorkoutId`, `HealthMeasurement.healthKitSampleId`).
public struct HealthImporter {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Uvozi kardio treninge iz Appleovih aplikacija. Treninzi koje je spremila ova aplikacija se preskaču.
    /// Vraća broj novih treninga u povijesti.
    @discardableResult
    public func importWorkouts(_ records: [HealthWorkoutRecord], name: (HealthActivity) -> String) throws -> Int {
        let store = HealthLocalStore(context: context)
        var knownWorkouts = Set(try store.workouts().map(\.healthKitWorkoutId))
        // Trening koji je ova aplikacija spremila u Zdravlje (i s drugog uređaja, preko iClouda) već je u povijesti.
        let sessions = try context.fetch(FetchDescriptor<Session>())
        knownWorkouts.formUnion(sessions.compactMap(\.healthKitWorkoutId))
        let sessionIds = Set(sessions.map(\.id))
        var imported = 0
        for record in records.sorted(by: { $0.start < $1.start }) {
            guard record.isFromApple, record.activity.isCardio, record.end > record.start,
                  !knownWorkouts.contains(record.uuid)
            else { continue }
            if let external = record.externalUUID, sessionIds.contains(external) { continue }

            let workout = HealthWorkout(
                healthKitWorkoutId: record.uuid, name: name(record.activity), startedAt: record.start, endedAt: record.end
            )
            workout.activeEnergyKilocalories = record.activeEnergyKilocalories.flatMap { $0 > 0 ? $0 : nil }
            workout.distanceMeters = record.distanceMeters.flatMap { $0 > 0 ? $0 : nil }
            workout.averageHeartRate = record.averageHeartRate.flatMap { $0 > 0 ? $0 : nil }
            workout.workoutPlanId = record.workoutPlanId
            context.insert(workout)
            knownWorkouts.insert(record.uuid)
            imported += 1
        }
        if imported > 0 { try context.save() }
        return imported
    }

    /// Uvozi težinu i visinu. Vraća broj novih mjerenja.
    @discardableResult
    public func importBodySamples(_ samples: [HealthBodySample]) throws -> Int {
        var known = Set(try HealthLocalStore(context: context).measurements().map(\.healthKitSampleId))
        var imported = 0
        for sample in samples where sample.value > 0 && !known.contains(sample.uuid) {
            guard sample.kind == .weight || sample.kind == .height else { continue }
            context.insert(HealthMeasurement(healthKitSampleId: sample.uuid, kind: sample.kind, value: sample.value, date: sample.date))
            known.insert(sample.uuid)
            imported += 1
        }
        if imported > 0 { try context.save() }
        return imported
    }

    /// Bilježi da je trening spremljen u Zdravlje, da se ne bi spremio ponovno. UUID treninga u Zdravlju
    /// ide u korisničku bazu (samo poveznica), a kalorije u lokalnu.
    public func markExported(sessionId: UUID, workoutId: UUID, activeEnergyKilocalories: Double?) throws {
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionId })
        guard let session = try context.fetch(descriptor).first else { return }
        session.healthKitWorkoutId = workoutId
        // Kalorije samo ako ih HealthKit stvarno ima (npr. sat je mjerio); inače ostaju prazne.
        try HealthLocalStore(context: context).setValues(
            forSession: sessionId, activeEnergyKilocalories: activeEnergyKilocalories, averageHeartRate: nil
        )
        try context.save()
    }
}
