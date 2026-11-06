import Models
import OSLog
import SwiftUI

/// Prikazuje se umjesto aplikacije kad se baza na uređaju ne može otvoriti (npr. nakon neuspjele migracije
/// nakon ažuriranja). Aplikacija se tako ne ruši pri svakom pokretanju, a podaci se ne brišu: korisnik može
/// pričekati popravak ili stare datoteke premjestiti u stranu i krenuti s praznom bazom (s iCloudom se
/// podaci zatim ponovno preuzmu).
struct StoreFailureScreen: View {
    @State private var confirmsReset = false
    @State private var movedTo: URL?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Podaci se nisu otvorili", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.title2.bold())
                    Text("Apolon nije mogao otvoriti spremljene treninge na ovom uređaju. Ništa nije obrisano.")
                    Text("Najprije zatvori aplikaciju i otvori je ponovno. Ako se ovo ponavlja, provjeri ima li novije verzije u App Storeu.")
                        .foregroundStyle(.secondary)
                    if let movedTo {
                        Text("Stari podaci su premješteni u mapu „\(movedTo.lastPathComponent)”. Zatvori aplikaciju i otvori je ponovno.")
                            .foregroundStyle(.green)
                    } else {
                        Button("Počni s praznom bazom", role: .destructive) { confirmsReset = true }
                            .buttonStyle(.bordered)
                    }
                    if let error = AppServices.storeOpenError {
                        DisclosureGroup("Detalji greške") {
                            Text(error)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding()
            }
        }
        .confirmationDialog("Početi s praznom bazom?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Premjesti stare podatke i počni", role: .destructive, action: moveAside)
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Stari podaci ostaju na uređaju u zasebnoj mapi. Treninzi iz iClouda ponovno se preuzimaju.")
        }
        .errorAlert($errorText)
    }

    private func moveAside() {
        do {
            movedTo = try GymPersistence.moveStoresAside(GymPersistence.storeURLs)
        } catch {
            Logger(subsystem: "com.brunodobric.gymapp", category: "Store")
                .error("Premještanje baze: \(String(describing: error))")
            errorText = String(localized: "Podaci se nisu mogli premjestiti.")
        }
    }
}
