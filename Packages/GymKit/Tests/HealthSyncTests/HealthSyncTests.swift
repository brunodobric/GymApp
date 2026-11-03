import Foundation
import Models
import SwiftData
import Testing
@testable import HealthSync

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let watchSource = "com.apple.health.7A3B1C2D-0000-4000-8000-000000000001"

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private func run(
    _ uuid: UUID = UUID(), activity: HealthActivity = .running, source: String = watchSource,
    start: Date = base, minutes: Double = 30, external: UUID? = nil, energy: Double? = 320
) -> HealthWorkoutRecord {
    HealthWorkoutRecord(
        uuid: uuid, activity: activity, start: start, end: start.addingTimeInterval(minutes * 60),
        sourceBundleIdentifier: source, externalUUID: external,
        activeEnergyKilocalories: energy, distanceMeters: 5_200, averageHeartRate: 148
    )
}

private func name(_ activity: HealthActivity) -> String {
    activity == .running ? "Trčanje" : activity.rawValue
}

private func finishedSession(in context: ModelContext, kind: WorkoutKind = .strength) -> Session {
    let session = Session(name: "Push", kind: kind, startedAt: base)
    session.state = .finished
    session.endedAt = base.addingTimeInterval(3_600)
    context.insert(session)
    return session
}

@Suite("Uvoz treninga iz Zdravlja")
struct WorkoutImportTests {

    @Test("Trčanje sa sata postaje kardio trening u povijesti sa svim podacima")
    func importsRun() throws {
        let context = try makeContext()
        let record = run()
        #expect(try HealthImporter(context: context).importWorkouts([record], name: name) == 1)

        // Uvezeni trening je samo u lokalnoj bazi, a povijest ga vidi kao trening.
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 0)
        let session = try #require(try GymQueries(context: context).allFinishedSessions().first)
        #expect(session.name == "Trčanje" && session.kind == .cardio && session.state == .finished)
        #expect(session.startedAt == record.start && session.endedAt == record.end)
        #expect(session.isImportedFromWorkoutsApp && session.healthKitWorkoutId == record.uuid)
        #expect(session.activeEnergyKilocalories == 320 && session.distanceMeters == 5_200 && session.averageHeartRate == 148)
    }

    @Test("Plan sa sata (WorkoutKit) sprema se uz uvezeni trening")
    func keepsWorkoutPlan() throws {
        let context = try makeContext()
        var record = run()
        let planId = UUID()
        record.workoutPlanId = planId
        try HealthImporter(context: context).importWorkouts([record, run(start: base.addingTimeInterval(86_400))], name: name)
        let workouts = try HealthLocalStore(context: context).workouts()
        #expect(workouts.map(\.workoutPlanId) == [planId, nil])
    }

    @Test("Isti trening uvezen dvaput pojavi se točno jednom")
    func importIsIdempotent() throws {
        let context = try makeContext()
        let record = run()
        let importer = HealthImporter(context: context)
        #expect(try importer.importWorkouts([record, record], name: name) == 1)
        #expect(try importer.importWorkouts([record], name: name) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HealthWorkout>()) == 1)
    }

    @Test("Treninzi koje je spremila ova aplikacija se ne uvoze natrag")
    func skipsOwnWorkouts() throws {
        let context = try makeContext()
        let own = finishedSession(in: context)
        try context.save()
        let fromOwnApp = run(activity: .traditionalStrengthTraining, source: "com.brunodobric.gymapp", external: own.id)
        let ownCardio = run(activity: .mixedCardio, source: "com.brunodobric.gymapp", external: own.id)
        // Ni Appleov izvor s našim vanjskim UUID-om (npr. sat u fazi 8) ne stvara drugi zapis.
        let appleWithOwnId = run(activity: .mixedCardio, source: watchSource, external: own.id)
        let imported = try HealthImporter(context: context).importWorkouts([fromOwnApp, ownCardio, appleWithOwnId], name: name)
        #expect(imported == 0)
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<HealthWorkout>()) == 0)
    }

    @Test("Uvoze se samo kardio treninzi iz Appleovih aplikacija")
    func filtersSourceAndActivity() throws {
        let context = try makeContext()
        let records = [
            run(activity: .cycling),
            run(activity: .walking, source: "com.apple.Fitness"),
            run(activity: .traditionalStrengthTraining),
            run(activity: .running, source: "com.strava.stravaride"),
            run(activity: .other)
        ]
        #expect(try HealthImporter(context: context).importWorkouts(records, name: name) == 2)
    }

    @Test("Bez kalorija u Zdravlju polje ostaje prazno, nikad nula")
    func missingEnergyStaysNil() throws {
        let context = try makeContext()
        try HealthImporter(context: context).importWorkouts([run(energy: nil), run(energy: 0)], name: name)
        let workouts = try HealthLocalStore(context: context).workouts()
        #expect(workouts.count == 2 && workouts.allSatisfy { $0.activeEnergyKilocalories == nil })
    }

    @Test("Uvezeni treninzi iz korisničke baze (starije verzije, dva uređaja) prelaze u lokalnu bazu jednom")
    func movesLegacyImports() throws {
        let context = try makeContext()
        let workoutId = UUID()
        for _ in 0..<2 {
            let session = Session(name: "Trčanje", kind: .cardio, startedAt: base)
            session.state = .finished
            session.isImportedFromWorkoutsApp = true
            session.healthKitWorkoutId = workoutId
            context.insert(session)
        }
        try context.save()
        #expect(try HealthLocalStore(context: context).moveHealthDataOutOfUserStore() == 2)
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HealthWorkout>()) == 1)
        #expect(try HealthLocalStore(context: context).moveHealthDataOutOfUserStore() == 0)
    }
}

@Suite("Uvoz težine i visine iz Zdravlja")
struct BodyImportTests {

    @Test("Težina i visina se uvoze jednom, s izvorom Zdravlje")
    func importsOnce() throws {
        let context = try makeContext()
        let samples = [
            HealthBodySample(uuid: UUID(), kind: .weight, value: 81.3, date: base),
            HealthBodySample(uuid: UUID(), kind: .height, value: 182, date: base)
        ]
        let importer = HealthImporter(context: context)
        #expect(try importer.importBodySamples(samples) == 2)
        #expect(try importer.importBodySamples(samples) == 0)

        #expect(try context.fetchCount(FetchDescriptor<BodyMeasurement>()) == 0)
        let measurements = try HealthLocalStore(context: context).measurements().map { $0.makeMeasurement() }
        #expect(measurements.count == 2 && measurements.allSatisfy { $0.source == .healthKit && $0.healthKitSampleId != nil })
        #expect(measurements.contains { $0.kind == .weight && $0.value == 81.3 })
    }

    @Test("Ručna mjerenja ostaju netaknuta, a druge vrste i nule se preskaču")
    func keepsManualAndSkipsInvalid() throws {
        let context = try makeContext()
        context.insert(BodyMeasurement(kind: .weight, value: 80, date: base))
        try context.save()
        let samples = [
            HealthBodySample(uuid: UUID(), kind: .weight, value: 0, date: base),
            HealthBodySample(uuid: UUID(), kind: .waist, value: 85, date: base)
        ]
        #expect(try HealthImporter(context: context).importBodySamples(samples) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BodyMeasurement>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<HealthMeasurement>()) == 0)
    }

    @Test("Mjerenja iz Zdravlja u korisničkoj bazi prelaze u lokalnu, a ručna ostaju")
    func movesLegacyMeasurements() throws {
        let context = try makeContext()
        context.insert(BodyMeasurement(kind: .weight, value: 80, date: base))
        let fromHealth = BodyMeasurement(kind: .weight, value: 81, date: base, source: .healthKit)
        fromHealth.healthKitSampleId = UUID()
        context.insert(fromHealth)
        try context.save()
        #expect(try HealthLocalStore(context: context).moveHealthDataOutOfUserStore() == 1)
        let manual = try context.fetch(FetchDescriptor<BodyMeasurement>())
        #expect(manual.count == 1 && manual.first?.source == .manual)
        #expect(try HealthLocalStore(context: context).measurements().map(\.value) == [81])
    }
}

@Suite("Spremanje treninga u Zdravlje")
struct WorkoutExportTests {

    @Test("Završeni trening s iPhonea se sprema kao trening snage")
    func exportsPhoneSession() throws {
        let context = try makeContext()
        let session = finishedSession(in: context)
        let export = try #require(HealthWorkoutExport.make(for: session))
        #expect(export.activity == .traditionalStrengthTraining && export.sessionId == session.id)
        #expect(export.start == base && export.end == base.addingTimeInterval(3_600))
        #expect(HealthWorkoutExport.make(for: finishedSession(in: context, kind: .cardio))?.activity == .mixedCardio)
    }

    @Test("Ne sprema se trening u tijeku, sa sata, već spremljen ni uvezen")
    func skipsIneligible() throws {
        let context = try makeContext()
        let active = Session(name: "U tijeku", startedAt: base)
        context.insert(active)
        let watch = finishedSession(in: context)
        watch.controllingDevice = .watch
        let saved = finishedSession(in: context)
        saved.healthKitWorkoutId = UUID()
        let imported = finishedSession(in: context, kind: .cardio)
        imported.isImportedFromWorkoutsApp = true
        for session in [active, watch, saved, imported] {
            #expect(HealthWorkoutExport.make(for: session) == nil)
        }
    }

    @Test("Spremanje bilježi UUID iz Zdravlja, a kalorije samo kad postoje")
    func markExported() throws {
        let context = try makeContext()
        let session = finishedSession(in: context)
        try context.save()
        let workoutId = UUID()
        try HealthImporter(context: context).markExported(sessionId: session.id, workoutId: workoutId, activeEnergyKilocalories: 0)
        #expect(session.healthKitWorkoutId == workoutId && session.activeEnergyKilocalories == nil)
        #expect(HealthLocalStore(context: context).activeEnergy(of: session) == nil)
        #expect(HealthWorkoutExport.make(for: session) == nil)

        try HealthImporter(context: context).markExported(sessionId: session.id, workoutId: workoutId, activeEnergyKilocalories: 410)
        // Kalorije su samo u lokalnoj bazi, nikad u treningu koji se sinkronizira.
        #expect(session.activeEnergyKilocalories == nil)
        #expect(HealthLocalStore(context: context).activeEnergy(of: session) == 410)
    }

    @Test("Prvi uvoz ide od početka dana prije zadanog broja dana")
    func importWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = HealthImportWindow.start(days: 30, now: base, calendar: calendar)
        #expect(start == calendar.startOfDay(for: base).addingTimeInterval(-30 * 86_400))
    }
}
