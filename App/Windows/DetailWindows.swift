import Catalog
import Models
import SwiftData
import SwiftUI

// Dodatni prozori na iPadu (Stage Manager, Split View): trening iz povijesti ili vježba iz kataloga
// mogu se otvoriti u zasebnom prozoru, npr. uz uređivač treninga ili statistiku.

enum DetailWindow {
    static let session = "session"
    static let exercise = "exercise"
}

extension View {
    /// Kontekstni izbornik "Otvori u novom prozoru". Dodaje se samo gdje sustav podržava više prozora
    /// (iPad), pa na iPhoneu dugi pritisak ne otvara prazan izbornik.
    func openInWindowMenu<Value: Codable & Hashable>(_ windowId: String, value: Value) -> some View {
        modifier(OpenInWindowMenu(windowId: windowId, value: value))
    }
}

private struct OpenInWindowMenu<Value: Codable & Hashable>: ViewModifier {
    let windowId: String
    let value: Value

    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow

    @ViewBuilder
    func body(content: Content) -> some View {
        if supportsMultipleWindows {
            content.contextMenu {
                Button("Otvori u novom prozoru", systemImage: "macwindow.badge.plus") {
                    openWindow(id: windowId, value: value)
                }
            }
        } else {
            content
        }
    }
}

/// Prozor s detaljima odrađenog treninga.
struct SessionWindow: View {
    let sessionId: UUID?

    @Query private var sessions: [Session]
    @Query private var healthWorkouts: [HealthWorkout]
    @Query private var settingsList: [UserSettings]

    init(sessionId: UUID?) {
        self.sessionId = sessionId
        let id = sessionId ?? UUID()
        _sessions = Query(filter: #Predicate<Session> { $0.id == id })
        _healthWorkouts = Query(filter: #Predicate<HealthWorkout> { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            if let session = sessions.first ?? healthWorkouts.first?.makeSession() {
                SessionDetailScreen(session: session, unit: UserSettings.weightUnit(in: settingsList))
            } else {
                ContentUnavailableView("Trening nije pronađen", systemImage: "clock")
            }
        }
        .windowAppearance(UserSettings.preferred(in: settingsList))
    }
}

/// Prozor s detaljima vježbe iz kataloga ili vlastite vježbe.
struct ExerciseWindow: View {
    let summaryId: String?

    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]

    private var summary: ExerciseSummary? {
        guard let summaryId else { return nil }
        return (catalogStore.summaries + customExercises.map(\.summary)).first { $0.id == summaryId }
    }

    var body: some View {
        NavigationStack {
            if let summary {
                ExerciseDetailScreen(summary: summary)
            } else {
                ContentUnavailableView("Vježba nije pronađena", systemImage: "questionmark.circle")
            }
        }
        .windowAppearance(UserSettings.preferred(in: settingsList))
    }
}

extension View {
    /// Tema i boja iz postavki, kao u glavnom prozoru.
    func windowAppearance(_ settings: UserSettings?) -> some View {
        tint(settings?.accent.color ?? AccentChoice.blue.color)
            .preferredColorScheme(settings?.theme.colorScheme)
    }
}
