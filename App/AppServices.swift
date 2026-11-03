import Models
import SwiftData

/// Baza i veze koje trebaju i ekrani i radnje izvan njih (gumb u Live Activityju, poruke sa sata).
///
/// `LiveActivityIntent` sustav može pokrenuti u pozadini prije nego što se išta prikaže, pa se baza otvara
/// ovdje, jednom, a ne u `GymApp`.
@MainActor
enum AppServices {
    /// Korisnička baza. Faza 12 prebacuje je na CloudKit (`.cloudKit`), dotad je samo lokalna.
    static let container: ModelContainer = {
        do {
            return try GymPersistence.makeUserContainer(storage: .local)
        } catch {
            // Bez baze aplikacija ne može raditi, a tihi nastavak bi sakrio problem.
            fatalError("Korisnička baza se nije mogla otvoriti: \(error)")
        }
    }()

    private static var isStarted = false

    /// Pokreće vezu sa satom. Poziva se što ranije (i iz pozadinskih radnji), a više poziva ne smeta.
    static func start() {
        guard !isStarted else { return }
        isStarted = true
        // WatchConnectivity sesija mora se aktivirati što ranije, da poruke sa sata
        // stignu i kad se aplikacija pokrene u pozadini.
        PhoneWatchSync.shared.start(container: container)
    }
}
