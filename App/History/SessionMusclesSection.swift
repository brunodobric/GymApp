import Catalog
import Models
import Stats
import SwiftData
import SwiftUI

/// Odjeljak s mapom mišića jednog treninga: tijelo sprijeda i straga obojeno prema broju serija po regiji
/// te popis glavnih mišića s brojem serija. Koriste ga sažetak nakon treninga i detalji treninga iz povijesti.
/// Trening bez završene radne serije (npr. uvezen iz Zdravlja) nema odjeljak.
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
            let assisting = sets.filter { $0.primarySets == 0 }.map { BodyRegion.title($0.region) }
            Section {
                HStack(alignment: .top, spacing: 8) {
                    BodyFigureView(female: female, back: false, heatmap: heatmap, selected: $selection)
                    BodyFigureView(female: female, back: true, heatmap: heatmap, selected: $selection)
                }
                .frame(maxHeight: 300)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Prikaz tijela. Rađeno: \(names(primary))"))
                let most = primary.map(\.primarySets).max() ?? 1
                ForEach(primary, id: \.region) { load in
                    LabeledContent {
                        Text("\(load.primarySets) serije")
                    } label: {
                        // Traka u boji mišićne skupine, dulja što je više serija.
                        VStack(alignment: .leading, spacing: 6) {
                            Text(BodyRegion.title(load.region))
                                .fontWeight(load.region == selection ? .semibold : nil)
                            ProgressView(value: Double(load.primarySets), total: Double(max(most, 1)))
                                .tint(BodyRegion.color(load.region))
                                .accessibilityHidden(true)
                        }
                    }
                }
                if !assisting.isEmpty {
                    Text("Pomažu: \(assisting.formatted(.list(type: .and)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Mišići u ovom treningu")
            } footer: {
                Text("Tamnija boja znači više serija. Pomoćna serija broji se kao pola.")
            }
        }
    }

    private func names(_ loads: [RegionSets]) -> String {
        loads.map { BodyRegion.title($0.region) }.formatted(.list(type: .and))
    }
}
