import SwiftUI

/// Ekran prototipa veze iPhone ↔ Watch. Isti ekran koriste obje aplikacije.
struct ConnectivityPrototypeView: View {
    private var session: ConnectivityPrototypeSession { .shared }

    var body: some View {
        List {
            Section("Stanje") {
                LabeledContent("Sesija", value: session.activationDescription)
                LabeledContent("Dostupan", value: session.isReachable ? "da" : "ne")
                LabeledContent("Instalirano", value: session.isCounterpartInstalled ? "da" : "ne")
            }

            Section("Pošalji") {
                Button("sendMessage") { session.sendViaMessage() }
                Button("transferUserInfo") { session.sendViaUserInfo() }
                Button("applicationContext") { session.sendViaApplicationContext() }
                Button("Isti događaj dvaput") { session.sendDuplicate() }
            }

            Section("Zapis") {
                if session.log.isEmpty {
                    Text("Još ništa").foregroundStyle(.secondary)
                }
                ForEach(session.log) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.text).font(.caption)
                        Text(entry.date.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !session.log.isEmpty {
                    Button("Očisti zapis", role: .destructive) { session.clearLog() }
                }
            }
        }
        .navigationTitle("Veza")
    }
}
