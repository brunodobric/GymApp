import SwiftUI

/// Tekst vrijednosti i opisi gumba − i + za VoiceOver. Dijele ih Live Activity (Dynamic Island i zaključani
/// zaslon) i kartica treninga na Početnoj, koja izgleda kao Live Activity.
extension RestTimerActivityAttributes.SetValue {
    @ViewBuilder
    var valueText: some View {
        if field == "reps" {
            if let reps = Int(text) {
                Text("\(reps) pon.")
            } else {
                Text("– pon.")
            }
        } else if unitSymbol.isEmpty {
            Text(verbatim: text)
        } else {
            Text(verbatim: "\(text) \(unitSymbol)")
        }
    }

    var decreaseLabel: Text {
        switch field {
        case "reps": Text("Smanji ponavljanja")
        case "duration": Text("Skrati trajanje")
        case "distance": Text("Smanji udaljenost")
        default: Text("Smanji težinu")
        }
    }

    var increaseLabel: Text {
        switch field {
        case "reps": Text("Povećaj ponavljanja")
        case "duration": Text("Produlji trajanje")
        case "distance": Text("Povećaj udaljenost")
        default: Text("Povećaj težinu")
        }
    }
}
