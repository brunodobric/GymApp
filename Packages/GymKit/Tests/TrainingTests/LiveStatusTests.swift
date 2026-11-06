import Catalog
import Foundation
import Models
import SwiftData
import Testing
@testable import Training

private let squat = ExerciseRef(catalogId: "squat", name: "Čučanj")
private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let row = ExerciseRef(catalogId: "row", name: "Veslanje")
private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func makeEngine() throws -> WorkoutEngine {
    WorkoutEngine(context: ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory)))
}

/// Popunjava sve serije vježbe da se mogu potvrditi.
private func fill(_ exercise: SessionExercise, weight: Double = 60, reps: Int = 8) {
    for set in exercise.orderedSets {
        set.weightKg = weight
        set.reps = reps
    }
}

@Suite("Live Activity i obavijest o kraju odmora")
struct LiveStatusTests {

    @Test("Prva serija prve vježbe, pa sljedeća vježba i broj serija")
    func initialStatus() throws {
        let engine = try makeEngine()
        let session = try engine.startSession(name: "A", now: start)
        let first = try engine.addExercise(squat, inputType: .weightReps, to: session, now: start)
        _ = try engine.addExercise(bench, inputType: .weightReps, to: session, now: start)

        let status = engine.liveStatus(of: session)
        #expect(status.currentExerciseName == "Čučanj")
        #expect(status.nextExerciseName == "Potisak s klupe")
        #expect(status.setNumber == 1)
        #expect(status.setCount == 3)
        #expect(status.nextSetID == first.orderedSets[0].id)
        #expect(status.completedSets == 0)
        #expect(status.totalSets == 6)
        #expect(status.rest == nil)
        // Prazna serija ne može se potvrditi iz Live Activityja.
        #expect(!status.canConfirmNextSet)
    }

    @Test("Nakon potvrde serije: sljedeća serija iste vježbe i rest timer")
    func afterCompletion() throws {
        let engine = try makeEngine()
        let session = try engine.startSession(name: "A", now: start)
        let first = try engine.addExercise(squat, inputType: .weightReps, to: session, now: start)
        fill(first)
        let set = try #require(engine.nextSet(in: session))
        try engine.completeSet(set, defaultRestSeconds: 90, now: start.addingTimeInterval(30))

        let status = engine.liveStatus(of: session)
        #expect(status.setNumber == 2)
        #expect(status.nextSetID == first.orderedSets[1].id)
        #expect(status.canConfirmNextSet)
        #expect(status.completedSets == 1)
        #expect(status.rest?.endsAt == start.addingTimeInterval(120))
        #expect(status.nextExerciseName == nil)
    }

    @Test("Ostaje na vježbi koju korisnik radi, i kad nije prva po redu")
    func followsCurrentExercise() throws {
        let engine = try makeEngine()
        let session = try engine.startSession(name: "A", now: start)
        _ = try engine.addExercise(squat, inputType: .weightReps, to: session, now: start)
        let second = try engine.addExercise(bench, inputType: .weightReps, to: session, now: start)
        fill(second)
        try engine.completeSet(second.orderedSets[0], defaultRestSeconds: 90, now: start)

        let status = engine.liveStatus(of: session)
        #expect(status.currentExerciseName == "Potisak s klupe")
        #expect(status.setNumber == 2)
        #expect(status.nextExerciseName == "Čučanj")
    }

    @Test("Kad je vježba gotova, prelazi se na prvu nezavršenu po redu")
    func movesToFirstIncomplete() throws {
        let engine = try makeEngine()
        let session = try engine.startSession(name: "A", now: start)
        _ = try engine.addExercise(squat, inputType: .weightReps, to: session, now: start)
        let second = try engine.addExercise(bench, inputType: .weightReps, to: session, now: start)
        _ = try engine.addExercise(row, inputType: .weightReps, to: session, now: start)
        fill(second)
        for set in second.orderedSets { try engine.completeSet(set, defaultRestSeconds: 90, now: start) }

        let status = engine.liveStatus(of: session)
        #expect(status.currentExerciseName == "Čučanj")
        #expect(status.nextExerciseName == "Veslanje")
    }

    @Test("Superset: serije idu naizmjence, a sljedeća vježba je partner")
    func superset() throws {
        let engine = try makeEngine()
        let session = try engine.startSession(name: "A", now: start)
        let first = try engine.addExercise(bench, inputType: .weightReps, to: session, now: start)
        let second = try engine.addExercise(row, inputType: .weightReps, to: session, now: start)
        try engine.makeSuperset([first, second], in: session, now: start)
        fill(first)
        fill(second)

        #expect(engine.liveStatus(of: session).nextExerciseName == "Veslanje")
        try engine.completeSet(first.orderedSets[0], defaultRestSeconds: 90, now: start)
        let status = engine.liveStatus(of: session)
        #expect(status.currentExerciseName == "Veslanje")
        #expect(status.nextSetID == second.orderedSets[0].id)
        #expect(status.nextExerciseName == "Potisak s klupe")
    }

    @Test("Sve serije završene: nema serije za potvrdu")
    func allDone() throws {
        let engine = try makeEngine()
        let session = try engine.startSession(name: "A", now: start)
        let first = try engine.addExercise(squat, inputType: .weightReps, to: session, now: start)
        fill(first)
        for set in first.orderedSets { try engine.completeSet(set, defaultRestSeconds: 90, now: start) }

        let status = engine.liveStatus(of: session)
        #expect(status.isAllCompleted)
        #expect(status.nextSetID == nil)
        #expect(status.currentExerciseName == nil)
        #expect(!status.canConfirmNextSet)
    }

    @Test("Uklonjena vježba ne broji se u serije")
    func removedExerciseIgnored() throws {
        let engine = try makeEngine()
        let session = try engine.startSession(name: "A", now: start)
        let first = try engine.addExercise(squat, inputType: .weightReps, to: session, now: start)
        _ = try engine.addExercise(bench, inputType: .weightReps, to: session, now: start)
        try engine.removeExercise(first, now: start)

        let status = engine.liveStatus(of: session)
        #expect(status.currentExerciseName == "Potisak s klupe")
        #expect(status.totalSets == 3)
    }

    @Test("Obavijest o kraju odmora samo za trening koji vodi iPhone")
    func notificationPolicy() {
        let end = start.addingTimeInterval(90)
        #expect(RestNotificationPolicy.fireDate(
            restEndsAt: end, controllingDevice: .phone, notificationsEnabled: true, isSessionActive: true, now: start
        ) == end)
        // Trening vodi sat, ili sat drži sesiju za trening s iPhonea: kraj odmora javlja sat.
        #expect(RestNotificationPolicy.fireDate(
            restEndsAt: end, controllingDevice: .phone, notificationsEnabled: true, isSessionActive: true,
            watchAlertsRest: true, now: start
        ) == nil)
        #expect(RestNotificationPolicy.fireDate(
            restEndsAt: end, controllingDevice: .watch, notificationsEnabled: true, isSessionActive: true, now: start
        ) == nil)
        #expect(RestNotificationPolicy.fireDate(
            restEndsAt: end, controllingDevice: .phone, notificationsEnabled: false, isSessionActive: true, now: start
        ) == nil)
        #expect(RestNotificationPolicy.fireDate(
            restEndsAt: end, controllingDevice: .phone, notificationsEnabled: true, isSessionActive: false, now: start
        ) == nil)
        #expect(RestNotificationPolicy.fireDate(
            restEndsAt: nil, controllingDevice: .phone, notificationsEnabled: true, isSessionActive: true, now: start
        ) == nil)
        // Odmor je već (gotovo) istekao.
        #expect(RestNotificationPolicy.fireDate(
            restEndsAt: start.addingTimeInterval(0.5), controllingDevice: .phone, notificationsEnabled: true,
            isSessionActive: true, now: start
        ) == nil)
    }

    @Test("+10 / −10 pomiče trenutak obavijesti")
    func adjustMovesNotification() throws {
        let engine = try makeEngine()
        let session = try engine.startSession(name: "A", now: start)
        let first = try engine.addExercise(squat, inputType: .weightReps, to: session, now: start)
        fill(first)
        try engine.completeSet(first.orderedSets[0], defaultRestSeconds: 90, now: start)
        try engine.adjustRest(of: session, bySeconds: 10, now: start.addingTimeInterval(5))

        let fire = RestNotificationPolicy.fireDate(
            restEndsAt: engine.liveStatus(of: session).rest?.endsAt, controllingDevice: session.controllingDevice,
            notificationsEnabled: true, isSessionActive: true, now: start.addingTimeInterval(5)
        )
        #expect(fire == start.addingTimeInterval(100))
    }
}
