import AppIntents
import Foundation

/// Gumbi − i + uz težinu, ponavljanja, trajanje ili udaljenost sljedeće serije u Live Activityju.
/// Kao `CompleteSetIntent`: sustav ga izvršava u procesu aplikacije, gdje se vrijednost upisuje u bazu.
struct AdjustSetValueIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Promijeni vrijednost serije"
    static let description = IntentDescription("Povećava ili smanjuje vrijednost sljedeće serije aktivnog treninga.")
    static let isDiscoverable = false

    @Parameter(title: "Serija")
    var setID: String

    /// `WatchSetField.rawValue`: weight, extraWeight, reps, duration ili distance.
    @Parameter(title: "Polje")
    var field: String

    /// +1 ili −1 korak (1,25 kg, 1 ponavljanje, 5 sekundi, 50 metara).
    @Parameter(title: "Korak")
    var steps: Int

    init() {}

    init(setID: String, field: String, steps: Int) {
        self.setID = setID
        self.field = field
        self.steps = steps
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityActions.adjustSet(id: setID, field: field, steps: steps)
        return .result()
    }
}
