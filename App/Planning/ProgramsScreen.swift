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
    @Query private var settingsList: [UserSettings]
    @State private var added: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List(ProgramLibrary.all) { program in
                VStack(alignment: .leading, spacing: 6) {
                    Text(program.title).font(.itemTitle)
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
                Text("Raspored \(added ?? "") nalazi se u kartici Plan, a ciljeve u treningu možeš prilagoditi.")
            }
            .errorAlert($errorText)
        }
    }

    private func install(_ program: Program) {
        do {
            // Ponavljanja prema cilju i iskustvu, vježbe prema opremi iz profila.
            let profile = UserSettings.preferred(in: settingsList).map(TrainingProfile.init(settings:)) ?? TrainingProfile()
            added = try ProgramAdder.add(program, profile: profile, context: context, catalogStore: catalogStore).name
        } catch {
            errorText = String(localized: "Program se nije mogao dodati.")
        }
    }
}
