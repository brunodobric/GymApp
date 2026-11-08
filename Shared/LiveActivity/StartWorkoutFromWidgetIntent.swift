import AppIntents

/// Gumb ▶ na widgetu sljedećeg treninga i kontrola "Započni trening" (Kontrolni centar, zaključani zaslon,
/// tipka Action). Otvara aplikaciju i pokreće sljedeći trening iz rasporeda ili nastavlja trening u tijeku, isto kao ⌘N.
///
/// Nije u aplikaciji Prečaci (`isDiscoverable`): ondje su intenti s izborom treninga.
struct StartWorkoutFromWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Započni trening"
    static let description = IntentDescription("Otvara Apolon i pokreće sljedeći trening iz rasporeda.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await WidgetActions.startWorkout()
        return .result()
    }
}
