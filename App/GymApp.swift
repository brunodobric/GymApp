import SwiftUI

@main
struct GymApp: App {
    init() {
        // WatchConnectivity sesija mora se aktivirati što ranije, da poruke sa sata
        // stignu i kad se aplikacija pokrene u pozadini.
        ConnectivityPrototypeSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
