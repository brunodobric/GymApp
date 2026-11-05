import Models
import SwiftUI

/// Izbor spremljenog treninga kad nema rasporeda: popis treninga snage, dodir pokreće odabrani.
/// Popis daje `TemplateStarter.startable`, a pokretanje radi Početna tek kad se list zatvori.
struct TemplatePickerSheet: View {
    let templates: [WorkoutTemplate]
    let onSelect: (WorkoutTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(templates) { template in
                Button {
                    onSelect(template)
                    dismiss()
                } label: {
                    TemplatePickerRow(template: template)
                }
                .accessibilityIdentifier("home.templatePicker.row")
            }
            .navigationTitle("Odaberi trening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Odustani") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Red popisa: naziv treninga (zaobljeni bold), ispod broj vježbi i prve vježbe redom.
private struct TemplatePickerRow: View {
    let template: WorkoutTemplate

    var body: some View {
        let exercises = template.orderedExercises
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.itemTitle)
                    .foregroundStyle(.primary)
                Text("\(exercises.count) vježbi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !exercises.isEmpty {
                    Text(exercises.map(\.exerciseName).formatted(.list(type: .and)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "play.fill")
                .font(.footnote.bold())
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Pokreće trening"))
    }
}
