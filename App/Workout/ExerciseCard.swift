import Catalog
import Models
import SwiftUI
import Training
import Units

/// Vježba u aktivnom treningu: zaglavlje i, kad je otvorena, retci serija i gumbi za dodavanje.
struct ExerciseCard: View {
    let exercise: SessionExercise
    let isOpen: Bool
    let isEditing: Bool
    let highlightedSetID: UUID?
    let previous: [SetValues]
    let unit: WeightUnit
    let effortScale: EffortScale

    let onToggleOpen: () -> Void
    let onEdit: () -> Void
    let onToggleComplete: (SetLog) -> Void
    let onChangeKind: (SetLog, SetKind) -> Void
    let onDeleteSet: (SetLog) -> Void
    let onAddSet: (SetKind) -> Void
    let onRemove: () -> Void
    let onSuperset: () -> Void
    let onLeaveSuperset: () -> Void
    /// Otvara stranicu vježbe (animacija i upute). Nil kad vježba nije u katalogu ni među vlastitima.
    let onShowInfo: (() -> Void)?

    /// Svaki dio je svoj redak u listi (sekcija vježbe), da se serija može obrisati povlačenjem ulijevo.
    var body: some View {
        header
            .padding(.vertical, 6)
        if isOpen && !isEditing {
            if !exercise.orderedSets.isEmpty {
                SetTableHeader(inputType: exercise.inputType, unit: unit)
            }
            ForEach(rows, id: \.set.id) { row in
                SetRow(
                    set: row.set, inputType: exercise.inputType, position: row.position,
                    previousText: row.previous, suggestion: row.suggestion,
                    isHighlighted: row.set.id == highlightedSetID, unit: unit,
                    effortScale: effortScale, onEdit: onEdit, onToggleComplete: { onToggleComplete(row.set) },
                    onChangeKind: { onChangeKind(row.set, $0) }, onDelete: { onDeleteSet(row.set) }
                )
                // Akcent boja cijele aplikacije (.tint u RootView) inače oboji i ovaj gumb, pa je crvena izričita.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Obriši", systemImage: "trash", role: .destructive) { onDeleteSet(row.set) }
                        .tint(.red)
                }
            }
            HStack {
                Button("Dodaj seriju", systemImage: "plus") { onAddSet(.working) }
                Spacer()
                Button("Zagrijavanje", systemImage: "flame") { onAddSet(.warmUp) }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onToggleOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    if exercise.supersetGroupId != nil {
                        Text("Superset")
                            .font(.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(.tint)
                    }
                    Text(exercise.exerciseName).font(.itemTitle)
                    Text("\(completedCount) od \(exercise.orderedSets.count) serija")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(isOpen ? "Zatvori vježbu" : "Otvori vježbu"))

            if !isEditing, let onShowInfo {
                Button(action: onShowInfo) {
                    Label("Upute za vježbu", systemImage: "info.circle").headerIcon()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Upute: \(exercise.exerciseName)"))
            }

            if !isEditing {
                Menu {
                    Button("Superset", systemImage: "rectangle.stack", action: onSuperset)
                    if exercise.supersetGroupId != nil {
                        Button("Izbaci iz superseta", systemImage: "rectangle.stack.badge.minus", action: onLeaveSuperset)
                    }
                    Button("Izbaci vježbu", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Label("Više", systemImage: "ellipsis.circle").headerIcon()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var completedCount: Int {
        exercise.orderedSets.filter(\.isCompleted).count
    }

    private struct Row {
        let set: SetLog
        let position: Int
        let previous: String?
        let suggestion: SetValues?
    }

    /// Redni broj se računa zasebno za radne serije, a zagrijavanje se označava slovom.
    private var rows: [Row] {
        var working = 0
        var warmUp = 0
        return exercise.orderedSets.map { set in
            let index: Int
            if set.kind == .working {
                working += 1
                index = working - 1
            } else {
                warmUp += 1
                index = warmUp - 1
            }
            let old = SmartDefaults.defaults(forPosition: index, kind: set.kind, previous: previous)
            return Row(
                set: set, position: set.kind == .working ? working : warmUp, previous: old.flatMap(previousText),
                suggestion: old
            )
        }
    }

    private func previousText(_ values: SetValues) -> String? {
        let formatter = WeightFormatter(unit: unit)
        switch exercise.inputType {
        case .weightReps:
            guard let weight = values.weightKg, let reps = values.reps else { return nil }
            return "\(formatter.number(fromKilograms: weight)) × \(reps)"
        case .bodyweight:
            return values.reps.map { "× \($0)" }
        case .weightedBodyweight, .assisted:
            guard let reps = values.reps else { return nil }
            let load = values.extraWeightKg.map { formatter.number(fromKilograms: $0) } ?? "0"
            return "\(load) × \(reps)"
        case .duration:
            return values.durationSeconds.map { DurationInput.format($0) }
        case .durationDistance:
            let time = values.durationSeconds.map { DurationInput.format($0) }
            let km = values.distanceMeters.map { NumberInput.format($0 / 1000) + " km" }
            return [time, km].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

private extension Label where Title == Text, Icon == Image {
    /// Ikona u zaglavlju vježbe: veća sistemska ikona i dodirna površina od 44 × 44 pt (Apple HIG).
    func headerIcon() -> some View {
        labelStyle(.iconOnly)
            .font(.title2)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}
