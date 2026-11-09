import Catalog
import Models
import SwiftData
import SwiftUI
import Units

/// Korak težine po opremi (Postavke > Trening > Korak težine) i popis vježbi s vlastitim korakom.
/// Korak vrijedi za kotačić na iPhoneu, gumbe + i − u Live Activityju i na Početnoj te krunu na satu.
struct WeightStepsScreen: View {
    @Bindable var settings: UserSettings

    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]

    private var unit: WeightUnit { settings.weightUnit }

    var body: some View {
        List {
            Section {
                ForEach(Equipment.allCases, id: \.self) { equipment in
                    Picker(selection: binding(for: equipment)) {
                        ForEach(WeightStepSettings.choices(for: unit), id: \.self) { step in
                            Text(verbatim: WeightStepText.text(step, unit: unit)).tag(step)
                        }
                    } label: {
                        Text(equipment.title)
                    }
                }
            } header: {
                Text("Oprema")
            } footer: {
                Text("""
                    Razmak između dviju težina na kotačiću, na gumbima + i − u Live Activityju i za jedan klik \
                    Digital Crowna na satu. Koraci vrijede za jedinicu koja je sada odabrana (\(unit.symbol)).
                    """)
            }
            if !overrides.isEmpty {
                Section {
                    ForEach(overrides, id: \.key) { item in
                        LabeledContent(item.name, value: WeightStepText.text(item.step, unit: unit))
                            .swipeActions {
                                Button("Prema opremi") { removeOverride(item.key) }
                            }
                    }
                } header: {
                    Text("Vježbe s vlastitim korakom")
                } footer: {
                    Text("Korak postavljen na vježbi ima prednost pred korakom opreme. Mijenja se na stranici vježbe, a povlačenjem ulijevo vježba se vraća na korak opreme.")
                }
            }
            Section {
                Button("Vrati zadane korake") { resetEquipment() }
                    .disabled(!settings.weightSteps.equipment.keys.contains { $0.unit == unit })
            }
        }
        .navigationTitle("Korak težine")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for equipment: Equipment) -> Binding<Double> {
        Binding(
            get: { settings.weightSteps.step(for: equipment, unit: unit) },
            set: { step in
                var steps = settings.weightSteps
                steps.setStep(step, for: equipment, unit: unit)
                settings.weightSteps = steps
            }
        )
    }

    private struct Override {
        var key: String
        var name: String
        var step: Double
    }

    /// Vježbe s vlastitim korakom u trenutnoj jedinici, po nazivu.
    private var overrides: [Override] {
        settings.weightSteps.exercises
            .filter { $0.key.unit == unit }
            .map { key, step in Override(key: key.id, name: name(ofExercise: key.id), step: step) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func name(ofExercise key: String) -> String {
        if key.hasPrefix("c:"), let exercise = catalogStore.catalog?.exercise(withID: String(key.dropFirst(2))) {
            return exercise.displayName(language: catalogStore.language)
        }
        if key.hasPrefix("u:"), let id = UUID(uuidString: String(key.dropFirst(2))),
           let custom = customExercises.first(where: { $0.id == id }) {
            return custom.name
        }
        return String(localized: "Nepoznata vježba")
    }

    private func removeOverride(_ key: String) {
        var steps = settings.weightSteps
        steps.setOverride(nil, forExercise: key, unit: unit)
        settings.weightSteps = steps
    }

    private func resetEquipment() {
        var steps = settings.weightSteps
        for equipment in Equipment.allCases {
            steps.setStep(nil, for: equipment, unit: unit)
        }
        settings.weightSteps = steps
    }
}

/// Korak s jedinicom za prikaz, npr. "2,5 kg" ili "5 lbs".
enum WeightStepText {
    static func text(_ step: Double, unit: WeightUnit) -> String {
        "\(NumberInput.format(step)) \(unit.symbol)"
    }
}
