import Foundation
import SwiftData

// Podaci iz Apple Zdravlja žive u zasebnoj, lokalnoj bazi koja se nikad ne sinkronizira (faza 12).
// Pravilo App Storea 5.1.3 (ii) ne dopušta zdravstvene podatke iz HealthKita u iCloudu. Svaki uređaj
// ih sam čita iz Zdravlja, koje se i samo sinkronizira između korisnikovih uređaja.
//
// Modeli nemaju relacije prema modelima korisničke baze (CloudKit to ne dopušta između konfiguracija),
// nego ih vežu UUID-ovi.

/// Modeli lokalne baze podataka iz Zdravlja.
public enum GymHealthSchema {
    public static var models: [any PersistentModel.Type] {
        [HealthWorkout.self, HealthMeasurement.self, SessionHealthData.self]
    }
}

/// Kardio trening uvezen iz Appleovih aplikacija (Trening na satu, Fitness).
@Model
public final class HealthWorkout {
    public var id: UUID = UUID()
    /// UUID uzorka u HealthKitu (isti na svim uređajima korisnika).
    public var healthKitWorkoutId: UUID = UUID()
    public var name: String = ""
    public var startedAt: Date = Date()
    public var endedAt: Date = Date()
    public var activeEnergyKilocalories: Double?
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    /// Plan iz WorkoutKita po kojem je trening odrađen na satu.
    public var workoutPlanId: UUID?
    /// Raspored i predložak s kojima je trening povezan (`CardioPlanLinker`).
    public var scheduleId: UUID?
    public var templateId: UUID?

    public init(healthKitWorkoutId: UUID, name: String, startedAt: Date, endedAt: Date) {
        self.healthKitWorkoutId = healthKitWorkoutId
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    /// Trening za prikaz uz treninge iz korisničke baze (povijest, statistika). Ne umeće se ni u jednu bazu,
    /// a ima isti `id`, pa ga ekrani prepoznaju po `Session.isImportedFromWorkoutsApp`.
    public func makeSession() -> Session {
        let session = Session(name: name, kind: .cardio, startedAt: startedAt)
        session.id = id
        session.endedAt = endedAt
        session.lastActivityAt = endedAt
        session.state = .finished
        session.isImportedFromWorkoutsApp = true
        session.healthKitWorkoutId = healthKitWorkoutId
        session.activeEnergyKilocalories = activeEnergyKilocalories
        session.distanceMeters = distanceMeters
        session.averageHeartRate = averageHeartRate
        session.workoutPlanId = workoutPlanId
        session.scheduleId = scheduleId
        session.templateId = templateId
        return session
    }
}

/// Težina ili visina iz Zdravlja.
@Model
public final class HealthMeasurement {
    public var id: UUID = UUID()
    public var healthKitSampleId: UUID = UUID()
    public var kindRaw: String = BodyMeasurementKind.weight.rawValue
    /// kg za težinu, cm za visinu.
    public var value: Double = 0
    public var date: Date = Date()

    public init(healthKitSampleId: UUID, kind: BodyMeasurementKind, value: Double, date: Date) {
        self.healthKitSampleId = healthKitSampleId
        self.kindRaw = kind.rawValue
        self.value = value
        self.date = date
    }

    /// Mjerenje za prikaz uz ručna mjerenja. Ne umeće se ni u jednu bazu.
    public func makeMeasurement() -> BodyMeasurement {
        let measurement = BodyMeasurement(
            kind: BodyMeasurementKind(rawValue: kindRaw) ?? .weight, value: value, date: date, source: .healthKit
        )
        measurement.id = id
        measurement.healthKitSampleId = healthKitSampleId
        return measurement
    }
}

public extension Session {
    /// Vlastiti treninzi i treninzi iz Zdravlja (lokalna baza) zajedno, od najnovijeg.
    static func merged(_ own: [Session], health: [HealthWorkout]) -> [Session] {
        (own + health.map { $0.makeSession() }).sorted { $0.startedAt > $1.startedAt }
    }
}

public extension BodyMeasurement {
    /// Ručna mjerenja i mjerenja iz Zdravlja (lokalna baza) zajedno, od najstarijeg.
    static func merged(_ manual: [BodyMeasurement], health: [HealthMeasurement]) -> [BodyMeasurement] {
        (manual + health.map { $0.makeMeasurement() }).sorted { $0.date < $1.date }
    }
}

/// Kalorije i puls vlastitog treninga, izmjereni satom ili pročitani iz Zdravlja.
@Model
public final class SessionHealthData {
    public var sessionId: UUID = UUID()
    public var activeEnergyKilocalories: Double?
    public var averageHeartRate: Double?

    public init(sessionId: UUID) {
        self.sessionId = sessionId
    }
}

/// Čitanje i pisanje lokalnih podataka iz Zdravlja.
public struct HealthLocalStore {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Uvezeni treninzi

    public func workouts() throws -> [HealthWorkout] {
        try context.fetch(FetchDescriptor<HealthWorkout>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    /// Uvezeni treninzi čiji je početak u rasponu [from, to), kao treninzi za prikaz.
    public func sessions(from: Date, to: Date) throws -> [Session] {
        try context.fetch(FetchDescriptor<HealthWorkout>(
            predicate: #Predicate { $0.startedAt >= from && $0.startedAt < to }
        )).map { $0.makeSession() }
    }

    public func workout(id: UUID) throws -> HealthWorkout? {
        try context.fetch(FetchDescriptor<HealthWorkout>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: Mjerenja

    public func measurements() throws -> [HealthMeasurement] {
        try context.fetch(FetchDescriptor<HealthMeasurement>(sortBy: [SortDescriptor(\.date)]))
    }

    public func measurement(id: UUID) throws -> HealthMeasurement? {
        try context.fetch(FetchDescriptor<HealthMeasurement>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: Kalorije i puls vlastitih treninga

    public func values(forSession sessionId: UUID) throws -> SessionHealthData? {
        try context.fetch(FetchDescriptor<SessionHealthData>(predicate: #Predicate { $0.sessionId == sessionId })).first
    }

    /// Upisuje kalorije i puls treninga. Prazna vrijednost ne briše postojeću. Ne sprema kontekst.
    public func setValues(forSession sessionId: UUID, activeEnergyKilocalories: Double?, averageHeartRate: Double?) throws {
        let energy = activeEnergyKilocalories.flatMap { $0 > 0 ? $0 : nil }
        let heartRate = averageHeartRate.flatMap { $0 > 0 ? $0 : nil }
        guard energy != nil || heartRate != nil else { return }
        let data: SessionHealthData
        if let existing = try values(forSession: sessionId) {
            data = existing
        } else {
            data = SessionHealthData(sessionId: sessionId)
            context.insert(data)
        }
        if let energy { data.activeEnergyKilocalories = energy }
        if let heartRate { data.averageHeartRate = heartRate }
    }

    /// Kalorije treninga: iz Zdravlja za uvezeni trening, inače iz lokalnih podataka.
    public func activeEnergy(of session: Session) -> Double? {
        if session.isImportedFromWorkoutsApp { return session.activeEnergyKilocalories }
        return (try? values(forSession: session.id))?.activeEnergyKilocalories
    }

    /// Prosječni puls: izmjeren (lokalno) ima prednost pred ručno upisanim u sažetku treninga.
    public func averageHeartRate(of session: Session) -> Double? {
        if session.isImportedFromWorkoutsApp { return session.averageHeartRate }
        return (try? values(forSession: session.id))?.averageHeartRate ?? session.averageHeartRate
    }

    // MARK: Brisanje

    /// Briše uvezeni trening (prikazan kao `Session` s `isImportedFromWorkoutsApp`).
    public func deleteImported(sessionId: UUID) throws {
        if let workout = try workout(id: sessionId) {
            context.delete(workout)
            try context.save()
        }
    }

    /// Briše kalorije i puls obrisanog vlastitog treninga. Ne sprema kontekst.
    public func deleteValues(forSession sessionId: UUID) throws {
        if let data = try values(forSession: sessionId) { context.delete(data) }
    }

    /// Briše mjerenje iz Zdravlja (prikazano kao `BodyMeasurement` s izvorom Zdravlje). U Zdravlju ostaje.
    public func deleteMeasurement(id: UUID) throws {
        if let measurement = try measurement(id: id) {
            context.delete(measurement)
            try context.save()
        }
    }

    /// Briše sve podatke iz Zdravlja na uređaju ("Obriši sve podatke").
    public func deleteAll() throws {
        try context.deleteEvery(HealthWorkout.self)
        try context.deleteEvery(HealthMeasurement.self)
        try context.deleteEvery(SessionHealthData.self)
        try context.save()
    }

    // MARK: Premještanje iz korisničke baze

    /// Premješta podatke iz Zdravlja koji su završili u korisničkoj bazi u lokalnu: uvezene treninge,
    /// mjerenja iz Zdravlja te kalorije i izmjereni puls vlastitih treninga. Takvi zapisi postoje iz verzija
    /// prije faze 12, a mogu stići i iz sigurnosne kopije ili s uređaja sa starijom verzijom aplikacije.
    /// Vraća broj premještenih zapisa.
    @discardableResult
    public func moveHealthDataOutOfUserStore() throws -> Int {
        var moved = 0
        let knownWorkouts = Set(try workouts().map(\.healthKitWorkoutId))
        let imported = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.isImportedFromWorkoutsApp == true }))
        var addedWorkouts = Set<UUID>()
        for session in imported {
            // Bez UUID-a iz Zdravlja (npr. ručno složena kopija) trening se ipak čuva, pod svojim id-om.
            let workoutId = session.healthKitWorkoutId ?? session.id
            if !knownWorkouts.contains(workoutId), addedWorkouts.insert(workoutId).inserted {
                let workout = HealthWorkout(
                    healthKitWorkoutId: workoutId, name: session.name,
                    startedAt: session.startedAt, endedAt: session.endedAt ?? session.startedAt
                )
                workout.id = session.id
                workout.activeEnergyKilocalories = session.activeEnergyKilocalories
                workout.distanceMeters = session.distanceMeters
                workout.averageHeartRate = session.averageHeartRate
                workout.workoutPlanId = session.workoutPlanId
                workout.scheduleId = session.scheduleId
                workout.templateId = session.templateId
                context.insert(workout)
            }
            context.delete(session)
            moved += 1
        }

        let knownSamples = Set(try measurements().map(\.healthKitSampleId))
        var addedSamples = Set<UUID>()
        let source = MeasurementSource.healthKit.rawValue
        let fromHealth = try context.fetch(FetchDescriptor<BodyMeasurement>(predicate: #Predicate { $0.sourceRaw == source }))
        // Iz Zdravlja se uvoze samo težina i visina. Druge mjere s tim izvorom ostaju gdje jesu.
        for measurement in fromHealth where measurement.kind == .weight || measurement.kind == .height {
            if let sampleId = measurement.healthKitSampleId, !knownSamples.contains(sampleId),
               addedSamples.insert(sampleId).inserted {
                let local = HealthMeasurement(
                    healthKitSampleId: sampleId, kind: measurement.kind, value: measurement.value, date: measurement.date
                )
                local.id = measurement.id
                context.insert(local)
            }
            context.delete(measurement)
            moved += 1
        }

        // Kalorije su uvijek iz Zdravlja. Puls je izmjeren kad je trening vodio sat; inače ga je korisnik upisao.
        let withEnergy = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.activeEnergyKilocalories != nil }))
        let watchLed = try context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.averageHeartRate != nil && $0.controllingDeviceRaw == "watch" }
        ))
        var touched = Set<UUID>()
        for session in withEnergy + watchLed where !session.isImportedFromWorkoutsApp && touched.insert(session.id).inserted {
            let heartRate = session.controllingDevice == .watch ? session.averageHeartRate : nil
            try setValues(
                forSession: session.id, activeEnergyKilocalories: session.activeEnergyKilocalories, averageHeartRate: heartRate
            )
            session.activeEnergyKilocalories = nil
            if heartRate != nil { session.averageHeartRate = nil }
            moved += 1
        }

        if moved > 0 { try context.save() }
        return moved
    }
}
