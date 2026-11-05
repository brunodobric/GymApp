import Foundation

/// U widget extensionu `CompleteSetIntent` i `AdjustSetValueIntent` se ne izvršavaju: `LiveActivityIntent` sustav pokreće u procesu
/// aplikacije, gdje je prava izvedba (`App/LiveActivity/LiveActivityActions.swift`). Ovo je samo da se intenti prevedu.
enum LiveActivityActions {
    static func completeSet(id: String) async {}
    static func adjustSet(id: String, field: String, steps: Int) async {}
}
