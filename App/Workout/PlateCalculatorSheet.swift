import Models
import SwiftData
import SwiftUI
import Training
import Units

/// Kalkulator ploča (dugi pritisak na polje težine): koje ploče staviti na svaku stranu šipke.
/// Postavke ploča i šipke čuvaju se u kg; za funte se koriste uobičajene ploče u funtama.
struct PlateCalculatorSheet: View {
    let targetText: String
    let unit: WeightUnit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    // Postavke iz upita, a ne zapamćeni objekt: nakon sinkronizacije duplikat postavki može biti obrisan.
    @Query private var settingsList: [UserSettings]
    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }

    init(targetText: String, unit: WeightUnit) {
        self.targetText = targetText
        self.unit = unit
        _text = State(initialValue: targetText)
    }

    private var barbell: Double {
        guard unit == .kilograms else { return PlateCalculator.defaultPoundBarbell }
        return settings?.barbellWeightKg ?? 20
    }

    private var plates: [Double] {
        guard unit == .kilograms else { return PlateCalculator.defaultPoundPlates }
        return settings?.availablePlatesKg ?? []
    }

    private var result: PlateCalculator.Result? {
        guard let target = NumberInput.parse(text) else { return nil }
        return PlateCalculator.calculate(target: target, barbell: barbell, plates: plates)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ciljna težina") {
                    HStack {
                        TextField("Težina", text: $text)
                            .keyboardType(.decimalPad)
                        Text(unit.symbol).foregroundStyle(.secondary)
                    }
                    LabeledContent("Šipka", value: "\(NumberInput.format(barbell)) \(unit.symbol)")
                }
                if let result {
                    Section("Na svaku stranu") {
                        if result.isBelowBar {
                            Text("Cilj je manji od same šipke.")
                                .foregroundStyle(.secondary)
                        } else if result.perSide.isEmpty {
                            Text("Samo šipka.")
                        } else {
                            ForEach(PlateCalculator.grouped(result.perSide), id: \.plate) { item in
                                LabeledContent("\(item.count) ×", value: "\(NumberInput.format(item.plate)) \(unit.symbol)")
                            }
                        }
                        if !result.isExact && !result.isBelowBar {
                            LabeledContent("Postižemo", value: "\(NumberInput.format(result.achievedTotal)) \(unit.symbol)")
                            Text("Točna težina nije moguća s dostupnim pločama.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Ploče")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { _ = try? GymQueries(context: context).settings() }
    }
}
