import Catalog
import Models
import SwiftData
import SwiftUI
import Stats
import Units

/// Detalji odrađenog treninga: sve vježbe, sve serije po vježbi i bilješke na dnu. Trening se može obrisati.
struct SessionDetailScreen: View {
    let session: Session
    let unit: WeightUnit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Datum", value: session.startedAt.formatted(date: .complete, time: .shortened))
                if let end = session.endedAt {
                    LabeledContent("Trajanje", value: Duration.seconds(max(0, end.timeIntervalSince(session.startedAt)))
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
                if let meters = session.distanceMeters {
                    LabeledContent("Udaljenost", value: "\(NumberInput.format(meters / 1000)) km")
                }
                if let heartRate = session.averageHeartRate {
                    LabeledContent("Prosječni puls", value: "\(Int(heartRate)) otk/min")
                }
            }
            ForEach(session.orderedExercises.filter { !$0.isRemoved }) { exercise in
                Section(exercise.exerciseName) {
                    ForEach(Array(exercise.orderedSets.filter(\.isCompleted).enumerated()), id: \.element.id) { index, set in
                        SetLine(set: set, inputType: exercise.inputType, unit: unit, number: number(of: set, in: exercise, fallback: index))
                    }
                }
            }
            if !session.notes.isEmpty {
                Section("Bilješke") {
                    Text(session.notes)
                }
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Obriši", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            }
        }
        .confirmationDialog("Obrisati trening?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Obriši trening", role: .destructive) { delete() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Trening i njegove serije bit će trajno obrisani, a rekordi i statistika preračunat će se bez njega.")
        }
        .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("U redu") {}
        } message: {
            Text(errorText ?? "")
        }
    }

    /// Redni broj radne serije; zagrijavanje nema broj.
    private func number(of set: SetLog, in exercise: SessionExercise, fallback: Int) -> Int? {
        guard set.kind == .working else { return nil }
        let working = exercise.orderedSets.filter { $0.isCompleted && $0.kind == .working }
        return (working.firstIndex { $0.id == set.id } ?? fallback) + 1
    }

    private func delete() {
        do {
            try HistoryQueries(context: context).delete(session)
            dismiss()
        } catch {
            errorText = String(localized: "Trening se nije mogao obrisati.")
        }
    }
}

private struct SetLine: View {
    let set: SetLog
    let inputType: ExerciseInputType
    let unit: WeightUnit
    let number: Int?

    var body: some View {
        HStack(spacing: 10) {
            Text(number.map(String.init) ?? "Z")
                .font(.subheadline.bold())
                .frame(width: 28, height: 28)
                .background(set.kind == .warmUp ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.15), in: .circle)
            Text(text)
            Spacer()
            if let rpe = set.rpe {
                Text("RPE \(NumberInput.format(rpe))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var text: String {
        let formatter = WeightFormatter(unit: unit)
        switch inputType {
        case .weightReps:
            return "\(formatter.string(fromKilograms: set.weightKg ?? 0)) × \(set.reps ?? 0)"
        case .bodyweight:
            return "× \(set.reps ?? 0)"
        case .weightedBodyweight:
            return "+\(formatter.string(fromKilograms: set.extraWeightKg ?? 0)) × \(set.reps ?? 0)"
        case .assisted:
            return "−\(formatter.string(fromKilograms: set.extraWeightKg ?? 0)) × \(set.reps ?? 0)"
        case .duration:
            return DurationInput.format(set.durationSeconds ?? 0)
        case .durationDistance:
            let time = DurationInput.format(set.durationSeconds ?? 0)
            guard let meters = set.distanceMeters else { return time }
            return "\(time) · \(NumberInput.format(meters / 1000)) km"
        }
    }
}
