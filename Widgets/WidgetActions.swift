import Foundation

/// U widget extensionu `StartWorkoutFromWidgetIntent` se ne izvršava: intent ima `openAppWhenRun`, pa ga sustav
/// pokreće u procesu aplikacije, gdje je prava izvedba (`App/Widgets/AppRequestRouter.swift`). Ovo je samo da se intent prevede.
enum WidgetActions {
    static func startWorkout() async {}
}
