import Backup
import SwiftUI

/// Pregled prije uvoza treninga iz druge aplikacije: koliko je novih treninga i kamo ide koja vježba.
struct ForeignImportSheet: View {
    let preview: ForeignWorkoutImport.Preview
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Novi treninzi") { Text(preview.newWorkouts.count, format: .number) }
                    if preview.alreadyImported > 0 {
                        LabeledContent("Već uvezeni") { Text(preview.alreadyImported, format: .number) }
                    }
                    if let first = preview.firstDate, let last = preview.lastDate {
                        LabeledContent("Razdoblje") {
                            Text((first..<max(first, last)).formatted(.interval.day().month().year()))
                        }
                    }
                    LabeledContent("Serije") { Text(preview.setCount, format: .number) }
                } header: {
                    Text("Treninzi")
                } footer: {
                    if preview.newWorkouts.isEmpty {
                        Text("Svi treninzi iz ove datoteke već su uvezeni.")
                    }
                }

                if !preview.exercises.isEmpty {
                    Section {
                        ForEach(preview.exercises) { mapping in
                            ExerciseMappingRow(mapping: mapping)
                        }
                    } header: {
                        Text("Vježbe")
                    } footer: {
                        Text("Vježbe kojih nema u katalogu dodaju se kao tvoje vlastite vježbe. Prazne serije se ne uvoze.")
                    }
                }
            }
            .navigationTitle("Uvoz treninga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Odustani") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uvezi") {
                        onImport()
                        dismiss()
                    }
                    .disabled(preview.newWorkouts.isEmpty)
                }
            }
        }
    }
}

/// Vježba iz datoteke (naziv i oprema) i vježba u koju se uvozi.
private struct ExerciseMappingRow: View {
    let mapping: ForeignWorkoutImport.ExerciseMapping

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mapping.sourceName)
            if !mapping.sourceEquipment.isEmpty {
                Text(mapping.sourceEquipment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            target
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var target: some View {
        switch mapping.target {
        case .catalog(_, let name):
            Label(name, systemImage: "books.vertical")
        case .existingCustom(_, let name):
            Label(name, systemImage: "person")
        case .newCustom:
            Label("Nova vlastita vježba", systemImage: "plus.circle")
        }
    }
}
