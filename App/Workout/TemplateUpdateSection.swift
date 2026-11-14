import Models
import Planning
import SwiftData
import SwiftUI

/// Na kraju treninga pokrenutog iz predloška: što je drugačije od predloška (dodane i preskočene vježbe,
/// broj serija, redoslijed) i gumb koji to sprema u predložak (`TemplateEngine.updateTemplate`).
struct TemplateUpdateSection: View {
    let session: Session
    let template: WorkoutTemplate
    let changes: TemplateChanges

    @Environment(\.modelContext) private var context
    @State private var isUpdated = false

    /// Predložak iz kojeg je trening pokrenut i promjene, nil kad predloška nema ili je trening odrađen po njemu.
    static func load(for session: Session, context: ModelContext) -> (WorkoutTemplate, TemplateChanges)? {
        guard let id = session.templateId else { return nil }
        let descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == id })
        guard let template = try? context.fetch(descriptor).first else { return nil }
        let changes = TemplateEngine(context: context).changes(from: session, to: template)
        return changes.isEmpty ? nil : (template, changes)
    }

    var body: some View {
        Section {
            if isUpdated {
                Label("Trening je ažuriran.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                if !changes.added.isEmpty {
                    Text("Dodano: \(changes.added.formatted(.list(type: .and)))")
                }
                if !changes.removed.isEmpty {
                    Text("Nije rađeno: \(changes.removed.formatted(.list(type: .and)))")
                }
                ForEach(changes.setCounts, id: \.name) { item in
                    Text("\(item.name): serije \(item.from) → \(item.to)")
                }
                if changes.reordered {
                    Text("Drugačiji redoslijed vježbi")
                }
                Button("Ažuriraj trening", systemImage: "arrow.triangle.2.circlepath", action: update)
            }
        } header: {
            Text("Promjene u treningu")
        } footer: {
            if !isUpdated {
                Text("Sprema se samo raspored vježbi i serija. Težine aplikacija predlaže sama.")
            }
        }
    }

    private func update() {
        guard (try? TemplateEngine(context: context).updateTemplate(template, from: session)) != nil else { return }
        isUpdated = true
    }
}
