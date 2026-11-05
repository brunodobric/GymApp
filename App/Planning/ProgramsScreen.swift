import Catalog
import Models
import Planning
import SwiftData
import SwiftUI

/// Gotovi programi: jedan dodir stvara treninge i raspored.
struct ProgramsScreen: View {
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var added: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List(ProgramLibrary.all) { program in
                VStack(alignment: .leading, spacing: 6) {
                    Text(program.title).font(.headline)
                    Text(program.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Dodaj program", systemImage: "plus.circle") { install(program) }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Programi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
            .alert("Program je dodan", isPresented: Binding(get: { added != nil }, set: { if !$0 { added = nil } })) {
                Button("U redu") { dismiss() }
            } message: {
                Text("Raspored \(added ?? "") nalazi se u kartici Rasporedi, a ciljeve u treningu možeš prilagoditi.")
            }
            .errorAlert($errorText)
        }
    }

    private func install(_ program: Program) {
        do {
            let schedule = try ProgramInstaller(context: context).install(
                program, name: program.title, workoutName: \.title
            ) { id in
                catalogStore.catalog?.exercise(withID: id)?.displayName(language: catalogStore.language) ?? id
            }
            ReminderScheduler.refresh(context: context)
            added = schedule.name
        } catch {
            errorText = String(localized: "Program se nije mogao dodati.")
        }
    }
}
