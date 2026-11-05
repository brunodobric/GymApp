import AppIntents
import Foundation

/// Gumb "Potvrdi seriju" u Live Activityju. `LiveActivityIntent` sustav izvršava u procesu aplikacije
/// (i kad je aplikacija u pozadini), pa se serija upisuje u bazu kao da je označena na ekranu treninga.
///
/// Datoteka je i u widget extensionu jer ga gumb treba. Tamo `LiveActivityActions` ne radi ništa
/// (vidi `Widgets/LiveActivityActions.swift`), a u aplikaciji upisuje seriju (`App/LiveActivity/LiveActivityActions.swift`).
struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Potvrdi seriju"
    static let description = IntentDescription("Označava sljedeću seriju aktivnog treninga završenom.")
    static let isDiscoverable = false

    @Parameter(title: "Serija")
    var setID: String

    init() {}

    init(setID: String) {
        self.setID = setID
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityActions.completeSet(id: setID)
        return .result()
    }
}
