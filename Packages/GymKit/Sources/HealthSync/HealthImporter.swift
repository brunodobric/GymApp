import Foundation
import Models
import SwiftData

/// Upisuje podatke iz Zdravlja u bazu, bez duplikata.
///
/// Duplikat se prepoznaje po UUID-u uzorka u HealthKitu (`Session.healthKitWorkoutId`,
/// `BodyMeasurement.healthKitSampleId`). Taj UUID je isti na iPhoneu i iPadu, pa se nakon CloudKit
/// sinkronizacije dvostruki uvoz s dva uređaja svodi na jedan zapis (`Deduplication.removeDuplicateHealthImports`).
public struct HealthImporter {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Uvozi kardio treninge iz Appleovih aplikacija. Treninzi koje je spremila ova aplikacija se preskaču.
    /// Vraća broj novih treninga u povijesti.
    @discardableResult
    public func importWorkouts(_ records: [HealthWorkoutRecord], name: (HealthActivity) -> String) throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<Session>())
        var knownWorkouts = Set(sessions.compactMap(\.healthKitWorkoutId))
        let sessionIds = Set(sessions.map(\.id))
        var imported = 0
        for record in records.sorted(by: { $0.start < $1.start }) {
            guard record.isFromApple, record.activity.isCardio, record.end > record.start,
                  !knownWorkouts.contains(record.uuid)
            else { continue }
            if let external = record.externalUUID, sessionIds.contains(external) { continue }

            let session = Session(name: name(record.activity), kind: .cardio, startedAt: record.start)
            session.endedAt = record.end
            session.lastActivityAt = record.end
            session.state = .finished
            session.isImportedFromWorkoutsApp = true
            session.healthKitWorkoutId = record.uuid
            session.activeEnergyKilocalories = record.activeEnergyKilocalories.flatMap { $0 > 0 ? $0 : nil }
            session.distanceMeters = record.distanceMeters.flatMap { $0 > 0 ? $0 : nil }
            session.averageHeartRate = record.averageHeartRate.flatMap { $0 > 0 ? $0 : nil }
            context.insert(session)
            knownWorkouts.insert(record.uuid)
            imported += 1
        }
        if imported > 0 { try context.save() }
        try Deduplication.removeDuplicateHealthImports(in: context)
        return imported
    }

    /// Uvozi težinu i visinu. Vraća broj novih mjerenja.
    @discardableResult
    public func importBodySamples(_ samples: [HealthBodySample]) throws -> Int {
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        var known = Set(measurements.compactMap(\.healthKitSampleId))
        var imported = 0
        for sample in samples where sample.value > 0 && !known.contains(sample.uuid) {
            guard sample.kind == .weight || sample.kind == .height else { continue }
            let measurement = BodyMeasurement(kind: sample.kind, value: sample.value, date: sample.date, source: .healthKit)
            measurement.healthKitSampleId = sample.uuid
            context.insert(measurement)
            known.insert(sample.uuid)
            imported += 1
        }
        if imported > 0 { try context.save() }
        try Deduplication.removeDuplicateHealthImports(in: context)
        return imported
    }

    /// Bilježi da je trening spremljen u Zdravlje, da se ne bi spremio ponovno.
    public func markExported(sessionId: UUID, workoutId: UUID, activeEnergyKilocalories: Double?) throws {
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionId })
        guard let session = try context.fetch(descriptor).first else { return }
        session.healthKitWorkoutId = workoutId
        // Kalorije samo ako ih HealthKit stvarno ima (npr. sat je mjerio); inače polje ostaje prazno.
        if let energy = activeEnergyKilocalories, energy > 0 {
            session.activeEnergyKilocalories = energy
        }
        try context.save()
    }
}
