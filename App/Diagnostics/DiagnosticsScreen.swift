import Diagnostics
import SwiftUI

/// Postavke > O aplikaciji > Dijagnostika: MetricKit izvještaji spremljeni na uređaju.
/// Korisnik ih može izvesti i poslati uz prijavu greške; aplikacija ih sama nikamo ne šalje.
struct DiagnosticsScreen: View {
    @State private var log = DiagnosticsLog()
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section {
                // swiftlint:disable:next line_length
                Text("Sustav jednom dnevno pripremi izvještaj o radu aplikacije (pokretanje, memorija, baterija), a nakon rušenja ili zastoja i izvještaj o grešci. Izvještaji ostaju na ovom uređaju i ne sadrže tvoje treninge. Možeš ih izvesti i poslati uz prijavu greške.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !log.totals.isEmpty {
                Section("Zadnjih 90 dana") {
                    ForEach(log.totals.sorted { $0.key < $1.key }, id: \.key) { kind, count in
                        LabeledContent(DiagnosticsText.title(kind), value: count.formatted())
                    }
                }
            }
            Section("Izvještaji") {
                if log.entries.isEmpty {
                    Text("Još nema izvještaja. Prvi stiže dan nakon korištenja aplikacije.")
                        .foregroundStyle(.secondary)
                }
                ForEach(log.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.kind == .diagnostics ? "Greška u radu" : "Dnevne metrike")
                        Text(entry.receivedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !entry.counts.isEmpty {
                            Text(DiagnosticsText.summary(entry.counts))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !log.entries.isEmpty {
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Izvezi izvještaje", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Obriši izvještaje", role: .destructive) {
                        DiagnosticsStore.shared.removeAll()
                        reload()
                    }
                }
            }
        }
        .navigationTitle("Dijagnostika")
        .onAppear(perform: reload)
    }

    private func reload() {
        log = DiagnosticsStore.shared.load()
        exportURL = log.entries.isEmpty ? nil : DiagnosticsStore.shared.exportFile()
    }
}

enum DiagnosticsText {
    /// Naziv vrste dijagnostike iz MetricKita ("crash", "hang"…).
    static func title(_ kind: String) -> String {
        switch kind {
        case "crash": String(localized: "Rušenja")
        case "hang": String(localized: "Zastoji")
        case "cpuException": String(localized: "Prekomjerno korištenje procesora")
        case "diskWriteException": String(localized: "Prekomjerno pisanje na disk")
        case "appLaunch": String(localized: "Sporo pokretanje")
        default: kind
        }
    }

    /// Npr. "Rušenja: 1, Zastoji: 2".
    static func summary(_ counts: [String: Int]) -> String {
        counts.sorted { $0.key < $1.key }
            .map { "\(title($0.key)): \($0.value)" }
            .joined(separator: ", ")
    }
}
