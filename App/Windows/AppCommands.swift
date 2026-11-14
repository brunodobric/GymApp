import Foundation
import SwiftUI
import WidgetData

/// Zahtjev Početnoj iz tipkovničkog prečaca (pokretanje treninga ili Postavke iz bilo kojeg taba).
enum HomeRequest: Equatable {
    case startWorkout
    case settings
    /// Dodir na Live Activity: puni ekran aktivnog treninga.
    case activeWorkout
    /// Widgeti: Početna bez ičega preko nje.
    case home
    /// Widget Ovaj tjedan: pregled tekućeg tjedna.
    case week
    /// Widget težine: praćenje tijela.
    case bodyWeight
    /// Widget zadnjeg treninga: detalji zadnjeg treninga.
    case lastWorkout
    /// Widget rekorda: detalji treninga u kojem je rekord postavljen.
    case session(UUID)
}

extension HomeRequest {
    /// Zahtjev iz poveznice widgeta ili Live Activityja.
    init(_ link: WidgetLink) {
        switch link {
        case .home: self = .home
        case .startWorkout: self = .startWorkout
        case .activeWorkout: self = .activeWorkout
        case .week: self = .week
        case .bodyWeight: self = .bodyWeight
        case .lastWorkout: self = .lastWorkout
        case .session(let id): self = .session(id)
        }
    }
}

/// Radnje glavnog prozora koje izbornik prečaca može pozvati. Objavljuje ih `RootView` aktivnog prozora.
struct RootActions {
    var select: (RootView.Section) -> Void
    var request: (HomeRequest) -> Void
}

extension FocusedValues {
    @Entry var rootActions: RootActions?
}

/// Tipkovnički prečaci za osnovne radnje (iPad s tipkovnicom). Drže li se ⌘, sustav ih prikazuje sve.
///
/// Prečaci unutar ekrana (npr. ⌘K za ploču kataloga u uređivaču treninga) su uz same gumbe.
struct AppCommands: Commands {
    @FocusedValue(\.rootActions) private var actions

    var body: some Commands {
        CommandMenu("Trening") {
            Button("Započni trening") { actions?.request(.startWorkout) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("Postavke") { actions?.request(.settings) }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandMenu("Idi") {
            sectionButton("Početna", .home, key: "1")
            sectionButton("Povijest", .history, key: "2")
            sectionButton("Plan", .schedules, key: "3")
            sectionButton("Vježbe", .exercises, key: "4")
            sectionButton("Statistika", .statistics, key: "5")
        }
    }

    private func sectionButton(_ title: LocalizedStringKey, _ section: RootView.Section, key: KeyEquivalent) -> some View {
        Button(title) { actions?.select(section) }
            .keyboardShortcut(key, modifiers: .command)
            .disabled(actions == nil)
    }
}
