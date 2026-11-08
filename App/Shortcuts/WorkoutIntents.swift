import AppIntents
import Foundation

/// Pokreće spremljeni trening ili prazan trening i otvara ga u aplikaciji. Za Siri, Action button,
/// Spotlight i automatizacije u Prečacima.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Započni trening"
    static let description = IntentDescription("Pokreće spremljeni trening ili prazan trening i otvara ga u aplikaciji.")
    /// Trening se vodi na ekranu, a Live Activity se može pokrenuti samo dok je aplikacija otvorena.
    static let openAppWhenRun = true

    @Parameter(title: "Trening", description: "Spremljeni trening. Bez njega se pokreće prazan trening.")
    var workout: WorkoutTemplateEntity?

    init() {}

    init(workout: WorkoutTemplateEntity?) {
        self.workout = workout
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ShortcutActions.startWorkout(templateId: workout?.id)
        return .result(dialog: IntentDialog(message))
    }
}

/// Pokreće sljedeći trening aktivnog rasporeda, kao prvi gumb na Početnoj.
struct StartScheduledWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Započni sljedeći trening"
    static let description = IntentDescription("Pokreće sljedeći trening iz aktivnog rasporeda i otvara ga u aplikaciji.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ShortcutActions.startNextScheduled()
        return .result(dialog: IntentDialog(message))
    }
}

/// Završava i sprema trening u tijeku, kao gumb "Završi" na ekranu treninga. Radi u pozadini, bez otvaranja aplikacije.
struct FinishWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Završi trening"
    static let description = IntentDescription(
        "Završava i sprema trening u tijeku. Nezavršene serije se brišu, kao kad trening završiš na ekranu."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ShortcutActions.finishWorkout()
        return .result(dialog: IntentDialog(message))
    }
}
