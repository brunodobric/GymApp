import Foundation

/// U widget extensionu `CompleteSetIntent` se ne izvršava: `LiveActivityIntent` sustav pokreće u procesu
/// aplikacije, gdje je prava izvedba (`App/Workout/LiveActivityActions.swift`). Ovo je samo da se intent prevede.
enum LiveActivityActions {
    static func completeSet(id: String) async {}
}
