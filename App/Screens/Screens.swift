import SwiftUI

// Privremeni ekrani za fazu 0. Svaki se zamjenjuje u fazi koja ga gradi.
// Naslovi su kratki (ispod 15 znakova) i nisu naziv aplikacije, prema HIG-u.

struct HomeScreen: View {
    @State private var showsSettings = false
    #if DEBUG
    @State private var showsPrototypes = false
    #endif

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Spremni za trening", systemImage: "figure.strengthtraining.traditional")
            } description: {
                Text("Pokretanje treninga stiže u fazi 3.")
            }
            .navigationTitle("Početna")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Postavke", systemImage: "gearshape") {
                        showsSettings = true
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button("Prototipi", systemImage: "hammer") {
                        showsPrototypes = true
                    }
                }
                #endif
            }
            .sheet(isPresented: $showsSettings) {
                SettingsScreen()
            }
            #if DEBUG
            .sheet(isPresented: $showsPrototypes) {
                PrototypesView()
            }
            #endif
        }
    }
}

struct HistoryScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Još nema treninga",
                systemImage: "clock",
                description: Text("Ovdje će biti svi odrađeni treninzi.")
            )
            .navigationTitle("Povijest")
        }
    }
}

struct SchedulesScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nema rasporeda",
                systemImage: "calendar",
                description: Text("Ovdje ćeš slagati svoje rasporede treninga.")
            )
            .navigationTitle("Rasporedi")
        }
    }
}

struct ExercisesScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Katalog vježbi",
                systemImage: "dumbbell",
                description: Text("Katalog stiže u fazi 2.")
            )
            .navigationTitle("Vježbe")
        }
    }
}

struct StatisticsScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Još nema podataka",
                systemImage: "chart.bar",
                description: Text("Statistika se prikazuje nakon prvih treninga.")
            )
            .navigationTitle("Statistika")
        }
    }
}

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("O aplikaciji") {
                    LabeledContent("Verzija", value: version)
                    // Atribucija kataloga (specifikacija, odjeljak 10), iako je javno vlasništvo.
                    Link(destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!) {
                        LabeledContent("Katalog vježbi", value: "free-exercise-db")
                    }
                    // TODO(faza 13): javni URL pravila privatnosti.
                    LabeledContent("Pravila privatnosti", value: "Uskoro")
                }
            }
            .navigationTitle("Postavke")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
        }
    }
}
