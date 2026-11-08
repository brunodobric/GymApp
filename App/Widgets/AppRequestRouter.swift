import Observation

/// Zahtjev Početnoj koji stiže izvan prozora: gumb ▶ na widgetu ili kontrola "Započni trening".
/// Intent se izvršava u aplikaciji (`openAppWhenRun`), a `RootView` zahtjev preuzme kad se prikaže.
@MainActor
@Observable
final class AppRequestRouter {
    static let shared = AppRequestRouter()

    var pending: HomeRequest?
}

/// Prava izvedba radnji iz widgeta (u extensionu je prazna, `Widgets/WidgetActions.swift`).
enum WidgetActions {
    static func startWorkout() async {
        await MainActor.run { AppRequestRouter.shared.pending = .startWorkout }
    }
}
