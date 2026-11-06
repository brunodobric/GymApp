import HealthKit
import SwiftUI
import WatchKit

@main
struct GymAppWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @State private var store = WatchWorkoutStore.shared

    init() {
        // WatchConnectivity se aktivira odmah, da poruke s iPhonea stignu i kad se aplikacija pokrene u pozadini.
        WatchWorkoutStore.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Sustav ponovno pokreće aplikaciju ako se ugasila usred treninga: sesija u Zdravlju se nastavlja.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            WatchWorkoutStore.shared.health.recover()
        }
    }

    /// iPhone je pokrenuo trening i zatražio sesiju na satu (`HKHealthStore.startWatchApp`): sat mjeri puls
    /// i kalorije, ostaje otvoren i na kraju sprema trening u Zdravlje.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WatchWorkoutStore.shared.phoneRequestedHealthSession()
        }
    }
}

/// Početni ekran, aktivni trening ili sažetak (specifikacija, odjeljak 6, "Watch ekrani").
struct WatchRootView: View {
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        if let summary = store.summary {
            WatchSummaryView(summary: summary) { store.closeSummary() }
        } else if store.active != nil {
            WatchWorkoutView()
        } else {
            WatchHomeView()
        }
    }
}
