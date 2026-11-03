import Models
import SwiftData
import SwiftUI

@main
struct GymApp: App {
    /// Korisnička baza. Faza 12 prebacuje je na CloudKit (`.cloudKit`), dotad je samo lokalna.
    private let container: ModelContainer
    @State private var catalogStore = CatalogStore()

    init() {
        do {
            container = try GymPersistence.makeUserContainer(storage: .local)
        } catch {
            // Bez baze aplikacija ne može raditi, a tihi nastavak bi sakrio problem.
            fatalError("Korisnička baza se nije mogla otvoriti: \(error)")
        }
        // WatchConnectivity sesija mora se aktivirati što ranije, da poruke sa sata
        // stignu i kad se aplikacija pokrene u pozadini.
        PhoneWatchSync.shared.start(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(catalogStore)
        }
        .modelContainer(container)
    }
}
