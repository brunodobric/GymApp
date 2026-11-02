import Catalog
import SwiftUI

struct ExerciseFilterSheet: View {
    @Binding var filter: ExerciseFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Izvor", selection: $filter.origin) {
                        Text("Sve").tag(ExerciseFilter.Origin.all)
                        Text("Službene").tag(ExerciseFilter.Origin.official)
                        Text("Vlastite").tag(ExerciseFilter.Origin.custom)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Prikaži arhivirane", isOn: $filter.includeArchived)
                }

                Section("Kategorija") {
                    ForEach(ExerciseCategory.allCases, id: \.self) { category in
                        SelectionRow(title: category.title, value: category, selection: $filter.categories)
                    }
                }

                Section("Oprema") {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        SelectionRow(title: equipment.title, value: equipment, selection: $filter.equipment)
                    }
                }

                Section("Mišić") {
                    ForEach(Muscle.allCases, id: \.self) { muscle in
                        SelectionRow(title: muscle.title, value: muscle, selection: $filter.muscles)
                    }
                }

                if filter.isActive {
                    Section {
                        Button("Poništi filtere", role: .destructive) {
                            let query = filter.query
                            filter = ExerciseFilter()
                            filter.query = query
                        }
                    }
                }
            }
            .navigationTitle("Filteri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Redak s kvačicom za višestruki odabir.
struct SelectionRow<Value: Hashable>: View {
    let title: LocalizedStringResource
    let value: Value
    @Binding var selection: Set<Value>

    var body: some View {
        Button {
            if selection.contains(value) {
                selection.remove(value)
            } else {
                selection.insert(value)
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if selection.contains(value) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(selection.contains(value) ? .isSelected : [])
    }
}
