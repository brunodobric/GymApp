import AppIntents
import Foundation

/// Sprema tjelesnu težinu za danas, u jedinici iz postavki aplikacije (kg ili lbs). Radi u pozadini.
struct LogBodyWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Upiši tjelesnu težinu"
    static let description = IntentDescription(
        "Sprema današnju tjelesnu težinu u jedinici iz postavki aplikacije (kg ili lbs)."
    )

    @Parameter(
        title: "Težina",
        description: "Tjelesna težina u jedinici iz postavki aplikacije.",
        requestValueDialog: IntentDialog("Kolika je tvoja težina?")
    )
    var weight: Double

    init() {}

    init(weight: Double) {
        self.weight = weight
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ShortcutActions.logBodyWeight(weight)
        return .result(dialog: IntentDialog(message))
    }
}
