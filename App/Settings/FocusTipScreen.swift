import SwiftUI

/// Uputa za sustavski Focus način tijekom treninga (specifikacija, odjeljak 6, "Notifikacije").
/// Aplikacija ne može utišati obavijesti drugih aplikacija, pa samo objašnjava kako to napraviti u iOS-u.
struct FocusTipScreen: View {
    var body: some View {
        List {
            Section {
                Text("Apollo ne može utišati obavijesti drugih aplikacija. To radi Focus način u iOS-u, a može se uključivati sam kad počneš trening.")
            }

            Section {
                step(1, "Otvori Postavke > Fokus i dodaj Fokus Fitness (ili vlastiti).")
                step(2, "U Dopuštenim obavijestima dodaj Apollo, da obavijest o kraju odmora i dalje stiže.")
                step(3, "Pod Automatski uključi odaberi Kad počne trening. Fokus se tada uključuje kad trening pokreneš na Apple Watchu.")
            } header: {
                Text("Postavljanje")
            }

            Section {
                step(1, "Otvori Prečace > Automatizacija i dodaj novu.")
                step(2, "Odaberi Aplikacija, zatim Apollo i Otvorena.")
                step(3, "Kao radnju dodaj Postavi Fokus i odaberi Fitness.")
            } header: {
                Text("Trening samo na iPhoneu")
            } footer: {
                Text("Fokus se uključuje kad otvoriš Apollo. Isključuje se ručno ili drugom automatizacijom kad aplikaciju zatvoriš.")
            }
        }
        .navigationTitle("Fokus")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
        }
    }
}

#Preview {
    NavigationStack { FocusTipScreen() }
}
