import Catalog
import Foundation
import Models
import Testing
@testable import Connectivity

private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let row = ExerciseRef(catalogId: "row", name: "Veslanje")

func sampleSnapshot(device: DeviceRole = .watch) -> SessionSnapshot {
    SessionSnapshot(
        name: "Push", startedAt: base, controllingDevice: device, updatedAt: base,
        exercises: [
            ExerciseSnapshot(
                orderIndex: 0, exercise: bench, inputType: .weightReps, restSeconds: 120,
                sets: [
                    SetSnapshot(orderIndex: 0, kind: .warmUp, weightKg: 40, reps: 10),
                    SetSnapshot(orderIndex: 1, weightKg: 80, reps: 8),
                    SetSnapshot(orderIndex: 2, weightKg: 80, reps: 8),
                ]
            ),
            ExerciseSnapshot(
                orderIndex: 1, exercise: row, inputType: .weightReps,
                sets: [SetSnapshot(orderIndex: 0, weightKg: 60, reps: 10)]
            ),
        ]
    )
}

@Suite("WorkoutEvent")
struct WorkoutEventTests {

    @Test("Snimka i naredbe prežive pakiranje i raspakiravanje")
    func roundTrip() throws {
        let snapshot = sampleSnapshot()
        let kinds: [WorkoutEvent.Kind] = [
            .snapshot(snapshot),
            .commands([
                .upsertSet(exerciseID: snapshot.exercises[0].id, set: snapshot.exercises[0].sets[1]),
                .deleteSet(setID: UUID()),
                .upsertExercise(snapshot.exercises[1]),
                .deleteExercise(exerciseID: UUID()),
                .setRestTimer(startedAt: base, endsAt: base.addingTimeInterval(90)),
                .setRestTimer(startedAt: nil, endsAt: nil),
                .setNotes("Bilješka"),
                .finish(at: base.addingTimeInterval(3600)),
                .discard,
                .healthRecordingStarted,
                .healthRecorded(workoutId: UUID(), activeEnergyKilocalories: 310, averageHeartRate: 128),
                .healthRecorded(workoutId: nil, activeEnergyKilocalories: nil, averageHeartRate: nil),
            ]),
        ]
        for kind in kinds {
            let event = WorkoutEvent(sessionID: snapshot.id, createdAt: base.addingTimeInterval(0.5), origin: .watch, kind: kind)
            let decoded = try WorkoutEvent(payload: event.payload())
            #expect(decoded == event)
        }
    }

    @Test("Rječnik bez događaja javlja grešku")
    func missingPayload() {
        #expect(throws: WorkoutEventCodingError.missingPayload) {
            try WorkoutEvent(payload: ["nešto": 1])
        }
    }

    @Test("Isti događaj obrađuje se samo jednom")
    func deduplication() {
        var deduplicator = WorkoutEventDeduplicator()
        let event = WorkoutEvent(origin: .phone, kind: .commands([.discard]))
        let first = deduplicator.accept(event)
        let repeated = deduplicator.accept(event)
        let other = deduplicator.accept(WorkoutEvent(origin: .phone, kind: .commands([.discard])))
        #expect(first)
        #expect(!repeated)
        #expect(other)
    }

    @Test("Kontekst za sat i snimka prežive sažimanje, a nedostajući dio ostaje prazan")
    func applicationContext() throws {
        let context = WatchContextPayload(
            upcoming: [PlannedWorkoutPayload(
                templateId: UUID(), scheduleId: UUID(), name: "Push", scheduleName: "PPL", kind: .strength,
                exercises: [PlannedExercisePayload(exercise: bench, inputType: .weightReps, restSeconds: 90, supersetGroup: 0,
                                                   sets: [PlannedSetPayload(weightKg: 80, reps: 8)])]
            )],
            templates: [], weightUnit: .pounds, defaultRestSeconds: 120, savesToHealth: true, generatedAt: base
        )
        let full = ApplicationContextPayload(watchContext: context, session: sampleSnapshot())
        #expect(ApplicationContextPayload(dictionary: try full.dictionary()) == full)

        let onlyContext = ApplicationContextPayload(watchContext: context)
        let decoded = ApplicationContextPayload(dictionary: try onlyContext.dictionary())
        #expect(decoded.watchContext == context)
        #expect(decoded.session == nil)

        #expect(ApplicationContextPayload(dictionary: ["session": Data([1, 2, 3])]) == ApplicationContextPayload())
    }
}
