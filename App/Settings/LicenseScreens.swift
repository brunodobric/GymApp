import Catalog
import SwiftUI

/// Izvor i licenca crteža tijela za heatmap.
struct MuscleMapLicenseScreen: View {
    private var licenseText: String {
        let url = Bundle.main.resourceURL?.appendingPathComponent("BodyMap/LICENSE-MuscleMap.txt")
        let raw = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "MIT License"
        return LicenseText.reflowed(raw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Crteži tijela u heatmapu preuzeti su iz projekta MuscleMap (MIT licenca).")
                Link("github.com/Jsplice/MuscleMap", destination: URL(string: "https://github.com/Jsplice/MuscleMap")!)
                Divider()
                Text(licenseText).font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("MuscleMap")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Atribucija kataloga vježbi: izvor i licenca (Unlicense, javno vlasništvo).
struct ExerciseCatalogLicenseScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Vježbe, upute i fotografije preuzete su iz projekta free-exercise-db (Unlicense).")
                Link("github.com/yuhonas/free-exercise-db", destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!)
                Divider()
                Text("Unlicense stavlja djelo u javno vlasništvo: slobodno se smije koristiti, mijenjati i dijeliti, bez uvjeta.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("free-exercise-db")
        .navigationBarTitleDisplayMode(.inline)
    }
}
