import Charts
import Models
import SwiftData
import SwiftUI
import Stats
import Units

/// Praćenje tijela: popis mjera s zadnjom vrijednošću i promjenom, a svaka mjera ima povijest i graf.
struct BodyScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query private var settingsList: [UserSettings]
    @State private var showsNewCustom = false
    @State private var customName = ""

    private var unit: WeightUnit { settingsList.first?.weightUnit ?? .kilograms }

    private var customNames: [String] {
        Array(Set(measurements.filter { $0.kind == .custom }.compactMap(\.customName).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        List {
            Section {
                ForEach(BodyMeasurementKind.allCases.filter { $0 != .custom }, id: \.self) { kind in
                    NavigationLink {
                        MeasurementDetailScreen(kind: kind, customName: nil, unit: unit)
                    } label: {
                        row(title: String(localized: kind.title), list: entries(of: kind, customName: nil), kind: kind)
                    }
                }
            }
            Section("Vlastite mjere") {
                ForEach(customNames, id: \.self) { name in
                    NavigationLink {
                        MeasurementDetailScreen(kind: .custom, customName: name, unit: unit)
                    } label: {
                        row(title: name, list: entries(of: .custom, customName: name), kind: .custom)
                    }
                }
                Button("Nova mjera", systemImage: "plus") {
                    customName = ""
                    showsNewCustom = true
                }
            }
        }
        .navigationTitle("Tijelo")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Nova mjera", isPresented: $showsNewCustom) {
            TextField("Naziv (npr. podlaktica)", text: $customName)
            Button("Dodaj") { addPlaceholder() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Nakon dodavanja prve vrijednosti mjera se pojavljuje na popisu.")
        }
        .navigationDestination(item: $newCustom) { name in
            MeasurementDetailScreen(kind: .custom, customName: name, unit: unit)
        }
    }

    @State private var newCustom: String?

    private func addPlaceholder() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { newCustom = name }
    }

    private func entries(of kind: BodyMeasurementKind, customName: String?) -> [BodyMeasurement] {
        measurements.filter { $0.kind == kind && (kind != .custom || $0.customName == customName) }
    }

    private func row(title: String, list: [BodyMeasurement], kind: BodyMeasurementKind) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let last = list.last {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(BodyFormat.text(last.value, kind: kind, unit: unit))
                    if list.count >= 2, let first = list.first {
                        Text(BodyFormat.change(last.value - first.value, kind: kind, unit: unit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Nema unosa").foregroundStyle(.secondary)
            }
        }
    }
}

extension BodyMeasurementKind {
    var title: LocalizedStringResource {
        switch self {
        case .weight: "Težina"
        case .height: "Visina"
        case .waist: "Struk"
        case .chest: "Prsa"
        case .arm: "Ruka"
        case .leg: "Noga"
        case .custom: "Vlastita mjera"
        }
    }
}

/// Težina se sprema u kg, a prikazuje u odabranoj jedinici; ostale mjere su u centimetrima.
enum BodyFormat {
    static func displayValue(_ value: Double, kind: BodyMeasurementKind, unit: WeightUnit) -> Double {
        kind == .weight ? WeightConversion.displayValue(fromKilograms: value, in: unit) : value
    }

    static func unitSymbol(kind: BodyMeasurementKind, unit: WeightUnit) -> String {
        kind == .weight ? unit.symbol : "cm"
    }

    static func text(_ value: Double, kind: BodyMeasurementKind, unit: WeightUnit) -> String {
        "\(NumberInput.format(displayValue(value, kind: kind, unit: unit))) \(unitSymbol(kind: kind, unit: unit))"
    }

    static func change(_ delta: Double, kind: BodyMeasurementKind, unit: WeightUnit) -> String {
        let shown = displayValue(delta, kind: kind, unit: unit)
        let sign = shown > 0 ? "+" : ""
        return "\(sign)\(NumberInput.format(shown)) \(unitSymbol(kind: kind, unit: unit))"
    }

    /// Unos u prikazanoj jedinici natrag u kg ili cm.
    static func storedValue(_ input: Double, kind: BodyMeasurementKind, unit: WeightUnit) -> Double {
        kind == .weight ? WeightConversion.kilograms(from: input, in: unit) : input
    }
}
