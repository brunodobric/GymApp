import Foundation

/// Zahtjev akcije iz Prečaca, Sirija ili Action buttona prikazanim ekranima: nakon pokretanja treninga
/// `RootView` otvara puni ekran aktivnog treninga, kao dodir na Live Activity.
@MainActor
@Observable
final class IntentRouter {
    static let shared = IntentRouter()

    /// Treba otvoriti trening u tijeku. `RootView` ga poništava kad zahtjev preuzme, pa ga otvara samo jedan prozor.
    var opensActiveWorkout = false

    func openActiveWorkout() {
        opensActiveWorkout = true
    }
}
