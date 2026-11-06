import Catalog
import Models
import Stats
import SwiftData
import SwiftUI

/// Odjeljak s mapom mišića jednog treninga: tijelo sprijeda i straga obojeno prema broju tvrdih serija po regiji
/// (fiksna skala, `LoadScale.sessionLevel`) te popis mišića s brojem serija. Koriste ga sažetak nakon treninga i
/// detalji treninga iz povijesti. Trening bez tvrde serije (npr. uvezen iz Zdravlja) nema odjeljak.
struct SessionMusclesSection: View {
    let session: Session

    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]
    @State private var selection: String?

    private var female: Bool { UserSettings.preferred(in: settingsList)?.bodyMapFemale ?? false }

    var body: some View {
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        let sets = SessionRegions.sets(in: session, info: info)
        if !sets.isEmpty {
            let heatmap = SessionRegions.heatmap(sets)
            let primary = sets.filter { $0.primarySets > 0 }
            Section {
                HStack(alignment: .top, spacing: 8) {
                    BodyFigureView(female: female, back: false, heatmap: heatmap, selected: $selection)
                    BodyFigureView(female: female, back: true, heatmap: heatmap, selected: $selection)
                }
                .frame(maxHeight: 300)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Prikaz tijela. Rađeno: \(names(primary))"))
                // Traka je na istoj skali kao boja tijela: puna traka je 10 i više serija.
                ForEach(sets, id: \.region) { load in
                    LabeledContent {
                        Text(load.weightedSets.formatted(.number.precision(.fractionLength(0...1))))
                            .monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(BodyRegion.title(load.region))
                                .fontWeight(load.region == selection ? .semibold : nil)
                            if load.primarySets == 0 {
                                Text("Pomaže").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(load.weightedSets, 10), total: 10)
                                .tint(BodyRegion.color(load.region))
                                .accessibilityHidden(true)
                        }
                    }
                }
            } header: {
                Text("Mišići u ovom treningu")
            } footer: {
                Text("Broj je broj tvrdih serija. Serija u kojoj mišić pomaže broji se kao pola, a serija s RPE ispod 6 se ne broji. Boja: 1–2, 3–5, 6–9 i 10 ili više serija.")
            }
        }
    }

    private func names(_ loads: [RegionSets]) -> String {
        loads.map { BodyRegion.title($0.region) }.formatted(.list(type: .and))
    }
}
