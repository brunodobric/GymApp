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

    init(targetText: String, unit: WeightUnit) {
        self.targetText = targetText
        self.unit = unit
        _text = State(initialValue: targetText)
    }

    var body: some View {
        NavigationStack {
            Form {
                PlateCalculatorSections(text: $text, unit: unit, settings: UserSettings.preferred(in: settingsList))
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

/// Kalkulator ploča preko cijelog ekrana (kartica na Početnoj): izračun i, ispod njega,
/// šipka i ploče koje korisnik ima, da ih može uključiti ili isključiti na licu mjesta.
struct PlateCalculatorScreen: View {
    let unit: WeightUnit

    @Environment(\.modelContext) private var context
    @State private var text = ""
    @Query private var settingsList: [UserSettings]

    var body: some View {
        let settings = UserSettings.preferred(in: settingsList)
        Form {
            PlateCalculatorSections(text: $text, unit: unit, settings: settings)
            if let settings {
                PlatesSettingsSection(settings: settings)
            }
        }
        .navigationTitle("Kalkulator ploča")
        .task { _ = try? GymQueries(context: context).settings() }
    }
}

/// Unos ciljne težine i ploče za svaku stranu. Dijele ga prozor iz serije i ekran s Početne.
private struct PlateCalculatorSections: View {
    @Binding var text: String
    let unit: WeightUnit
    let settings: UserSettings?

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
}
