import Catalog
import Models
import Stats
import SwiftData
import SwiftUI

/// Odjeljak s mapom mišića jednog treninga: tijelo sprijeda i straga obojeno prema broju tvrdih serija po regiji
/// (fiksna skala, `LoadScale.sessionLevel`) te popis mišića, podijeljen na glavne i one koji samo pomažu.
/// Odabir radi u oba smjera: dodir mišića na mapi označi redak, a dodir retka označi mišić na mapi.
/// Koriste ga sažetak nakon treninga i detalji treninga iz povijesti. Trening bez tvrde serije
/// (npr. uvezen iz Zdravlja) nema odjeljak.
struct SessionMusclesSection: View {
    @Environment(\.appAccent) private var accent
    let session: Session
    /// Tvrde serije po regiji u tjednu treninga (sažetak nakon treninga); prazno kad se ne prikazuju.
    var weekSets: [String: Double] = [:]

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
            let split = SessionRegions.split(sets)
            Section {
                HStack(alignment: .top, spacing: 8) {
                    BodyFigureView(female: female, back: false, heatmap: heatmap, selected: $selection)
                    BodyFigureView(female: female, back: true, heatmap: heatmap, selected: $selection)
                }
                .frame(maxHeight: 300)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Prikaz tijela. Rađeno: \(names(split.primary))"))
            } header: {
                Text("Mišići u ovom treningu")
            } footer: {
                if split.assisting.isEmpty { footer }
            }
            if !split.primary.isEmpty {
                Section("Glavni mišići") {
                    ForEach(split.primary, id: \.region) { row($0) }
                }
            }
            if !split.assisting.isEmpty {
                Section {
                    ForEach(split.assisting, id: \.region) { row($0) }
                } header: {
                    Text("Pomažu")
                } footer: {
                    footer
                }
            }
        }
    }

    private var footer: some View {
        Text("Broj je broj tvrdih serija. Serija u kojoj mišić pomaže broji se kao pola, a serija s RPE ispod 6 se ne broji. Razina i boja: 1–2, 3–5, 6–9 i 10 ili više serija.")
    }

    /// Redak mišića: boja skupine, glavne i pomoćne serije, razina na skali mape i broj serija.
    /// Dodir označi mišić na mapi, a ponovni dodir makne oznaku.
    private func row(_ load: RegionSets) -> some View {
        let selected = load.region == selection
        return Button {
            selection = selected ? nil : load.region
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(BodyRegion.color(load.region))
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BodyRegion.title(load.region))
                        .fontWeight(selected ? .semibold : nil)
                    Text(detail(load))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                LevelSegments(level: load.level)
                Text(load.weightedSets.formatted(.number.precision(.fractionLength(0...1))))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Crta između redaka ide do lijevog ruba, preko točke.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .listRowBackground(selected ? accent.opacity(0.12) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(BodyRegion.title(load.region)))
        .accessibilityValue(Text("\(load.weightedSets.formatted(.number.precision(.fractionLength(0...1)))) serija, \(detail(load))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(Text("Označi mišić na prikazu tijela."))
    }

    private func detail(_ load: RegionSets) -> String {
        var parts: [String] = []
        if load.primarySets > 0 { parts.append(String(localized: "\(load.primarySets) glavne")) }
        if load.secondarySets > 0 { parts.append(String(localized: "\(load.secondarySets) pomoćne")) }
        if let week = weekSets[load.region], week > 0 {
            let total = week.formatted(.number.precision(.fractionLength(0...1)))
            parts.append(String(localized: "ovaj tjedan \(total)"))
        }
        return parts.joined(separator: " · ")
    }

    private func names(_ loads: [RegionSets]) -> String {
        loads.map { BodyRegion.title($0.region) }.formatted(.list(type: .and))
    }
}

/// Razina opterećenja u četiri stupnja, u istim bojama kao mišići na mapi.
private struct LevelSegments: View {
    @Environment(\.appAccent) private var accent
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...LoadScale.maximumLevel, id: \.self) { step in
                RoundedRectangle(cornerRadius: 3)
                    .fill(step <= level
                        ? BodyFigureView.fill(intensity: LoadScale.intensity(level: step), accent: accent)
                        : Color.secondary.opacity(0.15))
                    .frame(width: 10, height: 14)
            }
        }
        .accessibilityHidden(true)
    }
}
