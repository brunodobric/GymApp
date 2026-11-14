import Catalog
import Models
import SwiftUI
import Training
import Units

/// Vježba u aktivnom treningu: zaglavlje i, kad je otvorena, retci serija i gumbi za dodavanje.
struct ExerciseCard: View {
    let exercise: SessionExercise
    /// Sličica ispred naziva (poster ili fotografija vlastite vježbe), nil kad slike nema.
    let thumbnail: ExerciseThumbnail.Source?
    let isOpen: Bool
    let isEditing: Bool
    let highlightedSetID: UUID?
    let previous: [SetValues]
    let unit: WeightUnit
    let effortScale: EffortScale
    /// Trajna bilješka vježbe (postavka sprave, hvat), `ExerciseNotes`.
    let persistentNote: String?
    /// Nudi se "Dodaj zagrijavanje" (`WorkoutEngine.canAddWarmUps`).
    let canAddWarmUps: Bool
    /// Završene serije koje obaraju rekord (`PersonalRecordDetector.liveRecordSets`).
    let recordSetIDs: Set<UUID>

    let onToggleOpen: () -> Void
    let onEdit: () -> Void
    let onToggleComplete: (SetLog) -> Void
    let onChangeKind: (SetLog, SetKind) -> Void
    let onDeleteSet: (SetLog) -> Void
    let onAddSet: (SetKind) -> Void
    let onRemove: () -> Void
    let onSuperset: () -> Void
    let onLeaveSuperset: () -> Void
    let onReplace: () -> Void
    let onEditNote: () -> Void
    let onAddWarmUps: () -> Void
    /// Otvara stranicu vježbe (animacija i upute). Nil kad vježba nije u katalogu ni među vlastitima.
    let onShowInfo: (() -> Void)?

    /// Svaki dio je svoj redak u listi (sekcija vježbe), da se serija može obrisati povlačenjem ulijevo.
    var body: some View {
        header
            .padding(.vertical, 6)
            .fullWidthSeparatorRow(vertical: Self.rowVerticalInset)
        if isOpen && !isEditing {
            if !exercise.orderedSets.isEmpty {
                // Naslovi stupaca su niži redak od serija: samo mali razmak iznad i ispod.
                SetTableHeader(inputType: exercise.inputType, unit: unit)
                    .fullWidthSeparatorRow(vertical: 6)
            }
            ForEach(rows, id: \.set.id) { row in
                SetRow(
                    set: row.set, inputType: exercise.inputType, position: row.position,
                    previousText: row.previous, suggestion: row.suggestion,
                    isHighlighted: row.set.id == highlightedSetID, unit: unit,
                    effortScale: effortScale, onEdit: onEdit, onToggleComplete: { onToggleComplete(row.set) },
                    onChangeKind: { onChangeKind(row.set, $0) }, onDelete: { onDeleteSet(row.set) }
                )
                .overlay(alignment: .topLeading) {
                    if recordSetIDs.contains(row.set.id) {
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .padding(.leading, 4)
                            .accessibilityLabel(Text("Osobni rekord"))
                    }
                }
                .fullWidthSeparatorRow(vertical: Self.rowVerticalInset)
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
            // Redak s gumbima je niži od serija.
            .fullWidthSeparatorRow(vertical: 8)
        }
    }

    /// Okomiti uvlak zaglavlja i redaka serija, isti kao zadani uvlak retka u grupiranoj listi.
    private static let rowVerticalInset: CGFloat = 15

    /// Sličica i naziv otvaraju i zatvaraju serije, a stranica vježbe (animacija i upute) je u izborniku s tri točkice.
    private var header: some View {
        HStack {
            Button(action: onToggleOpen) {
                HStack(spacing: 12) {
                    ExerciseRowThumbnail(source: thumbnail)
                    titles
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(isOpen ? "Zatvori vježbu" : "Otvori vježbu"))

            if !isEditing {
                Menu {
                    if let onShowInfo {
                        Button("Prikaži vježbu", systemImage: "info.circle", action: onShowInfo)
                        Divider()
                    }
                    Button("Zamijeni vježbu", systemImage: "arrow.triangle.2.circlepath", action: onReplace)
                    Button("Bilješka vježbe", systemImage: "note.text", action: onEditNote)
                    if canAddWarmUps {
                        Button("Dodaj zagrijavanje", systemImage: "flame", action: onAddWarmUps)
                    }
                    Divider()
                    Button("Superset", systemImage: "rectangle.stack", action: onSuperset)
                    if exercise.supersetGroupId != nil {
                        Button("Izbaci iz superseta", systemImage: "rectangle.stack.badge.minus", action: onLeaveSuperset)
                    }
                    Button("Izbaci vježbu", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    // Lagana siva ikona bez kruga, da se ne natječe s nazivom vježbe.
                    Label("Više", systemImage: "ellipsis")
                        .headerIcon()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            if exercise.supersetGroupId != nil {
                Text("Superset")
                    .font(.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(.tint)
            }
            Text(exercise.exerciseName).font(.itemTitle)
            HStack(spacing: 4) {
                Text("\(completedCount) od \(exercise.orderedSets.count) serija")
                if let target = targetText {
                    Text(verbatim: "·")
                    target
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let change = loadChangeText {
                Label { change } icon: { Image(systemName: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(isOpen ? nil : 1)
            }
        }
    }

    /// Cilj ponavljanja iz predloška: "cilj 8–12" ili "cilj 5".
    private var targetText: Text? {
        guard let lower = exercise.targetRepsMin else { return nil }
        let upper = exercise.targetRepsMax ?? lower
        return upper > lower ? Text("cilj \(lower)–\(upper)") : Text("cilj \(lower)")
    }

    /// Prijedlog dvostruke progresije: veća težina ili manja pomoć nego prošli put.
    private var loadChangeText: Text? {
        guard let change = exercise.loadChangeKg, abs(change) > 0.0001 else { return nil }
        let amount = WeightFormatter(unit: unit).string(fromKilograms: abs(change))
        if exercise.inputType == .assisted { return Text("Manje pomoći: −\(amount)") }
        return Text("Veća težina: +\(amount)")
    }

    /// Bilješka iz predloška i trajna bilješka vježbe, bez praznih i bez ponavljanja.
    private var notes: [String] {
        var result: [String] = []
        for note in [exercise.notes, persistentNote ?? ""] {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !result.contains(trimmed) { result.append(trimmed) }
        }
        return result
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

private extension View {
    /// Redak vježbe bez vodoravnog uvlaka liste, s vlastitim razmakom od ruba: crta ispod retka
    /// tako ide cijelom širinom kartice, od ruba do ruba.
    func fullWidthSeparatorRow(vertical: CGFloat) -> some View {
        padding(.horizontal, 16)
            .listRowInsets(EdgeInsets(top: vertical, leading: 0, bottom: vertical, trailing: 0))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
    }
}

private extension Label {
    /// Ikona u zaglavlju vježbe: veća sistemska ikona i dodirna površina od 44 × 44 pt (Apple HIG).
    func headerIcon() -> some View {
        labelStyle(.iconOnly)
            .font(.title2)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}
