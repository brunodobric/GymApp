import SwiftUI

@main
struct GymAppWatchApp: App {
    init() {
        ConnectivityPrototypeSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// Privremeni početni ekran sata. Pravi ekrani (specifikacija, odjeljak 6) dolaze u fazi 8.
struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            List {
                Label("Trening stiže u fazi 8", systemImage: "figure.strengthtraining.traditional")
                    .foregroundStyle(.secondary)
                #if DEBUG
                NavigationLink {
                    ConnectivityPrototypeView()
                } label: {
                    Label("Veza s iPhoneom", systemImage: "iphone")
                }
                #endif
            }
            .navigationTitle("Početna")
        }
    }
}
