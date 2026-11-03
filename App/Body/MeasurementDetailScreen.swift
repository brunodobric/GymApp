import Charts
import Models
import SwiftData
import SwiftUI
import Stats
import Units

/// Povijest i graf jedne mjere, s unosom nove vrijednosti.
struct MeasurementDetailScreen: View {
    let kind: BodyMeasurementKind
    let customName: String?
    let unit: WeightUnit

    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date) private var all: [BodyMeasurement]
    @State private var showsAdd = false
    @State private var errorText: String?

    private var list: [BodyMeasurement] {
        all.filter { $0.kind == kind && (kind != .custom || $0.customName == customName) }
    }

    private var title: String {
        kind == .custom ? (customName ?? "") : String(localized: kind.title)
    }

    var body: some View {
        List {
            if list.count >= 2 {
                Section {
                    Chart(list) { item in
                        LineMark(
                            x: .value("Datum", item.date),
                            y: .value(title, BodyFormat.displayValue(item.value, kind: kind, unit: unit))
                        )
                        PointMark(
                            x: .value("Datum", item.date),
                            y: .value(title, BodyFormat.displayValue(item.value, kind: kind, unit: unit))
                        )
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartHeight(200, regular: 320)
                    .accessibilityLabel(Text("Graf mjere \(title)"))
                }
            }
            Section("Povijest") {
                if list.isEmpty {
                    Text("Još nema unosa.").foregroundStyle(.secondary)
                }
                ForEach(list.reversed()) { item in
                    HStack {
                        Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(BodyFormat.text(item.value, kind: kind, unit: unit))
                        if item.source == .healthKit {
                            Image(systemName: "heart.fill").foregroundStyle(.red).accessibilityLabel(Text("Iz Apple Zdravlja"))
                        }
                    }
                }
                .onDelete { offsets in
                    let reversed = Array(list.reversed())
                    for index in offsets { try? BodyTracking(context: context).delete(reversed[index]) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Dodaj", systemImage: "plus") { showsAdd = true }
            }
        }
        .sheet(isPresented: $showsAdd) {
            AddMeasurementSheet(kind: kind, customName: customName, unit: unit)
        }
    }
}

private struct AddMeasurementSheet: View {
    let kind: BodyMeasurementKind
    let customName: String?
    let unit: WeightUnit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var valueText = ""
    @State private var date = Date()
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Vrijednost", text: $valueText)
                        .keyboardType(.decimalPad)
                    Text(BodyFormat.unitSymbol(kind: kind, unit: unit)).foregroundStyle(.secondary)
                }
                DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: .date)
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("Novi unos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Odustani") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Spremi") { save() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let input = NumberInput.parse(valueText) else {
            errorText = String(localized: "Upiši broj.")
            return
        }
        do {
            try BodyTracking(context: context).add(
                kind, value: BodyFormat.storedValue(input, kind: kind, unit: unit), date: date, customName: customName
            )
            dismiss()
        } catch {
            errorText = String(localized: "Vrijednost mora biti veća od nule.")
        }
    }
}
