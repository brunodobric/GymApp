import AppIntents
import SwiftUI
import WidgetKit

/// Kontrola "Započni trening" (prijedlog 10) za Kontrolni centar, zaključani zaslon i tipku Action:
/// otvara aplikaciju i pokreće sljedeći trening iz rasporeda ili nastavlja trening u tijeku.
struct StartWorkoutControl: ControlWidget {
    static let kind = "com.brunodobric.gymapp.start-workout"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartWorkoutFromWidgetIntent()) {
                Label("Započni trening", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Započni trening")
        .description("Pokreće sljedeći trening iz rasporeda.")
    }
}
