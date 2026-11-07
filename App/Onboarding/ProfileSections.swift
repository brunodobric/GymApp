import Catalog
import Models
import SwiftUI

extension EquipmentPreset {
    var title: LocalizedStringKey {
        switch self {
        case .gym: "Teretana (sva oprema)"
        case .homeGym: "Kućna teretana"
        case .dumbbells: "Bučice i trake"
        case .bodyweightOnly: "Bez opreme"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .gym: "Šipke, bučice, sprave i kablovi"
        case .homeGym: "Šipka sa stalkom i klupom, bučice, trake i šipka za zgibove"
        case .dumbbells: "Bučice, trake i vlastita težina"
        case .bodyweightOnly: "Samo vlastita težina"
        }
    }
}

/// Profil treninga: cilj, dani, iskustvo i oprema. Isti obrazac je u onboardingu i u Postavkama > Profil,
/// a preporuka gotovih programa koristi te odgovore.
struct TrainingProfileSections: View {
    @Binding var goal: TrainingGoal?
    @Binding var daysPerWeek: Int?
    @Binding var experience: ExperienceLevel?
    @Binding var equipment: [Equipment]

    var body: some View {
        Section {
            Picker("Cilj", selection: $goal) {
                Text("Bez odgovora").tag(TrainingGoal?.none)
                ForEach(TrainingGoal.allCases, id: \.self) { Text($0.title).tag(TrainingGoal?.some($0)) }
            }
            Picker("Dana tjedno", selection: $daysPerWeek) {
                Text("Bez odgovora").tag(Int?.none)
                ForEach(OnboardingAnswers.daysPerWeekRange, id: \.self) { Text($0, format: .number).tag(Int?.some($0)) }
            }
            Picker("Iskustvo", selection: $experience) {
                Text("Bez odgovora").tag(ExperienceLevel?.none)
                ForEach(ExperienceLevel.allCases, id: \.self) { Text($0.title).tag(ExperienceLevel?.some($0)) }
            }
        } header: {
            Text("Trening")
        } footer: {
            Text("Početnik trenira redovno manje od 6 mjeseci, srednji od 6 mjeseci do 2 godine, a napredni više od 2 godine.")
        }
        EquipmentSection(equipment: $equipment)
    }
}

/// Gdje korisnik trenira: preset jednim dodirom ("Teretana" odabire svu opremu) ili vlastiti popis.
private struct EquipmentSection: View {
    @Binding var equipment: [Equipment]

    private var selected: EquipmentPreset? { EquipmentPreset.matching(equipment) }

    private var customSummary: String {
        guard selected == nil, !equipment.isEmpty else { return "" }
        return String(localized: "Odabrano: \(equipment.count)")
    }

    var body: some View {
        Section {
            ForEach(EquipmentPreset.allCases, id: \.self) { preset in
                Button {
                    equipment = preset.equipment
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title).foregroundStyle(.primary)
                            Text(preset.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected == preset {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityAddTraits(selected == preset ? .isSelected : [])
            }
            NavigationLink {
                EquipmentListScreen(equipment: $equipment)
            } label: {
                LabeledContent("Prilagodi", value: customSummary)
            }
        } header: {
            Text("Gdje treniraš")
        } footer: {
            Text("Gotovi programi koriste samo vježbe za koje imaš opremu.")
        }
    }
}

/// Vlastiti odabir opreme, kad nijedan preset ne odgovara.
private struct EquipmentListScreen: View {
    @Binding var equipment: [Equipment]

    var body: some View {
        Form {
            Section {
                ForEach(Equipment.allCases, id: \.self) { item in
                    let isOn = equipment.contains(item)
                    Button {
                        if isOn { equipment.removeAll { $0 == item } } else { equipment.append(item) }
                    } label: {
                        HStack {
                            Text(item.title).foregroundStyle(.primary)
                            Spacer()
                            if isOn { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            } footer: {
                Text("Šipka za zgibove je pod Ostalo. Vježbe s vlastitom težinom su uvijek moguće.")
            }
        }
        .navigationTitle("Oprema")
        .navigationBarTitleDisplayMode(.inline)
    }
}
