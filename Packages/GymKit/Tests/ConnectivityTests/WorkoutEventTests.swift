import Foundation
import Testing
@testable import Connectivity

@Suite("WorkoutEvent")
struct WorkoutEventTests {

    @Test("Događaj preživi pakiranje i raspakiravanje", arguments: [
        WorkoutEvent.Kind.ping(note: "test"),
        .setCompleted(setID: UUID()),
        .restTimerStarted(endsAt: Date(timeIntervalSince1970: 1_800_000_000)),
        .restTimerCancelled,
    ])
    func roundTrip(kind: WorkoutEvent.Kind) throws {
        let event = WorkoutEvent(
            sessionID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000.5),
            origin: .watch,
            kind: kind
        )
        let decoded = try WorkoutEvent(payload: event.payload())
        #expect(decoded == event)
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
        let event = WorkoutEvent(origin: .phone, kind: .restTimerCancelled)
        let first = deduplicator.accept(event)
        let repeated = deduplicator.accept(event)
        let other = deduplicator.accept(WorkoutEvent(origin: .phone, kind: .restTimerCancelled))
        #expect(first)
        #expect(!repeated)
        #expect(other)
    }
}
