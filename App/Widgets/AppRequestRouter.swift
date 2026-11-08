import Observation

/// Zahtjev Početnoj koji stiže izvan prozora: gumb ▶ na widgetu ili kontrola "Započni trening".
/// Intent se izvršava u aplikaciji (`openAppWhenRun`), a `RootView` zahtjev preuzme kad se prikaže.
@MainActor
@Observable
final class AppRequestRouter {
    static let shared = AppRequestRouter()

    var pending: HomeRequest?

    /// Preuzima zahtjev i briše ga. Na iPadu s više prozora svaki `RootView` vidi isti zahtjev,
    /// a samo prvi ga dobije, pa se trening ne pokrene dvaput.
    func take() -> HomeRequest? {
        defer { pending = nil }
        return pending
    }
}

/// Prava izvedba radnji iz widgeta (u extensionu je prazna, `Widgets/WidgetActions.swift`).
enum WidgetActions {
    static func startWorkout() async {
        await MainActor.run { AppRequestRouter.shared.pending = .startWorkout }
    }
}
