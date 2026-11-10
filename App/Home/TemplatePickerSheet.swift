import Models
import Planning
import SwiftData
import SwiftUI
import Training

/// Trening odabran u `TemplatePickerSheet`: trening rasporeda (s izmjenama ciklusa) ili spremljeni trening.
enum WorkoutChoice {
    case planned(PlannedWorkout)
    case template(WorkoutTemplate)
}

/// Treninzi jednog aktivnog rasporeda u izboru treninga.
struct ScheduleChoices {
    let schedule: Schedule
    /// Treninzi rasporeda, redom niza (`ScheduleEngine.workoutChoices`).
    let workouts: [PlannedWorkout]
    /// Sljedeći trening rasporeda, označen u popisu.
    let nextItemID: UUID?
}

/// Izbor treninga za pokretanje: popis treninga snage, dodir pokreće odabrani.
/// S aktivnim rasporedima gore su njihovi treninzi, svaki raspored u svom odjeljku, a ispod ostali spremljeni
/// treninzi; bez rasporeda samo spremljeni (`TemplateStarter.startable`). Pokretanje radi Početna tek kad se list zatvori.
struct TemplatePickerSheet: View {
    /// Aktivni rasporedi iz kojih je izbor otvoren; prazno kad je otvoren bez rasporeda.
    var groups: [ScheduleChoices] = []
    let templates: [WorkoutTemplate]
    let onSelect: (WorkoutChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !groups.isEmpty {
                    ForEach(groups, id: \.schedule.id) { group in
                        Section(group.schedule.name) {
                            ForEach(group.workouts, id: \.item.id) { planned in
                                row(.planned(planned)) {
                                    TemplatePickerRow(
                                        template: planned.template,
                                        isNext: planned.item.id == group.nextItemID
                                    )
                                }
                            }
                        }
                    }
                    if !otherTemplates.isEmpty {
                        Section("Ostali treninzi") { templateRows(otherTemplates) }
                    }
                } else {
                    templateRows(templates)
                }
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

    /// Spremljeni treninzi koji nisu ni u jednom od prikazanih rasporeda.
    private var otherTemplates: [WorkoutTemplate] {
        let inSchedule = Set(groups.flatMap { $0.workouts.map(\.template.id) })
        return templates.filter { !inSchedule.contains($0.id) }
    }

    private func templateRows(_ list: [WorkoutTemplate]) -> some View {
        ForEach(list) { template in
            row(.template(template)) { TemplatePickerRow(template: template, isNext: false) }
        }
    }

    private func row<Label: View>(_ choice: WorkoutChoice, @ViewBuilder label: () -> Label) -> some View {
        let content = label()
        return Button {
            onSelect(choice)
            dismiss()
        } label: {
            content
        }
        .accessibilityIdentifier("home.templatePicker.row")
    }
}

/// Red popisa: naziv treninga (zaobljeni bold, uz oznaku sljedećeg u rasporedu), ispod broj vježbi i prve vježbe redom.
private struct TemplatePickerRow: View {
    let template: WorkoutTemplate
    /// Sljedeći trening rasporeda.
    let isNext: Bool

    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]

    var body: some View {
        let exercises = template.orderedExercises
        HStack(spacing: 12) {
            WorkoutKindIcon(
                mix: SessionCardio.mix(of: template, isCardio: catalogStore.isCardio(custom: customExercises))
            )
            .foregroundStyle(.tint)
            .frame(width: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(template.name)
                        .font(.itemTitle)
                        .foregroundStyle(.primary)
                    if isNext {
                        Text("Sljedeći")
                            .font(.caption.bold())
                            .foregroundStyle(.tint)
                    }
                }
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
