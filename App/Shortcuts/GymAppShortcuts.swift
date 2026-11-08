import AppIntents

/// Akcije koje se same pojave u Prečacima, Spotlightu i na Action buttonu, bez postavljanja.
/// Fraze su u `App/AppShortcuts.xcstrings` (hrvatski i engleski) i moraju sadržavati naziv aplikacije.
struct GymAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Započni trening u \(.applicationName)",
                "Započni \(\.$workout) u \(.applicationName)",
            ],
            shortTitle: "Započni trening",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StartScheduledWorkoutIntent(),
            phrases: [
                "Započni sljedeći trening u \(.applicationName)",
            ],
            shortTitle: "Sljedeći trening",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: FinishWorkoutIntent(),
            phrases: [
                "Završi trening u \(.applicationName)",
            ],
            shortTitle: "Završi trening",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: LogBodyWeightIntent(),
            phrases: [
                "Upiši težinu u \(.applicationName)",
            ],
            shortTitle: "Upiši težinu",
            systemImageName: "scalemass.fill"
        )
    }
}
