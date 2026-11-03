import Connectivity
import Models
import SwiftUI
import Units

// MARK: - Kontrole

/// Trajanje, puls i kalorije, uz završetak i odbacivanje treninga.
struct WatchControlsView: View {
    @Environment(WatchWorkoutStore.self) private var store
    @State private var confirmsFinish = false
    @State private var confirmsDiscard = false
    @State private var showsNothingCompleted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Gumbi su gore, da ih točkice stranica pri dnu nikad ne prekriju.
                HStack {
                    Button("Završi") { confirmsFinish = true }
                        .tint(.green)
                    Button("Odbaci", role: .destructive) { confirmsDiscard = true }
                }
                if let active = store.active {
                    Text(active.startedAt, style: .timer)
                        .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.yellow)
                    if store.isController {
                        metrics
                    } else {
                        Label("Trening vodi iPhone", systemImage: "iphone")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Serije: \(active.completedSetCount)")
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
        .scenePadding(.horizontal)
        .confirmationDialog("Završiti trening?", isPresented: $confirmsFinish) {
            Button("Završi trening") {
                if !store.finish() { showsNothingCompleted = true }
            }
            Button("Nastavi", role: .cancel) {}
        } message: {
            Text("Serije koje nisu označene završenima neće se spremiti.")
        }
        .confirmationDialog("Odbaciti trening?", isPresented: $confirmsDiscard) {
            Button("Odbaci trening", role: .destructive) { store.discard() }
            Button("Nastavi", role: .cancel) {}
        } message: {
            Text("Trening i sve serije bit će obrisani.")
        }
        .alert("Nema završenih serija", isPresented: $showsNothingCompleted) {
            Button("Odbaci trening", role: .destructive) { store.discard() }
            Button("Nastavi", role: .cancel) {}
        } message: {
            Text("Trening bez ijedne završene serije ne može se spremiti.")
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 2) {
            metric(store.health.heartRate, unit: "BPM", symbol: "heart.fill", color: .red)
            metric(store.health.activeEnergyKilocalories, unit: "kcal", symbol: "flame.fill", color: .orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ value: Double?, unit: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(.title3, design: .rounded).monospacedDigit())
            Text(unit).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Popis vježbi

/// Pregled cijelog treninga i prethodnih serija. Dodir na vježbu otvara je na ekranu serije.
struct WatchExerciseListView: View {
    let onSelect: () -> Void
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        List {
            ForEach(store.active?.visibleExercises ?? []) { exercise in
                Section {
                    Button {
                        store.select(exercise.id)
                        onSelect()
                    } label: {
                        HStack {
                            Text(exercise.exercise.name)
                                .font(.headline)
                                .foregroundStyle(exercise.id == store.currentExerciseID ? .green : .primary)
                            if exercise.supersetGroupId != nil {
                                Image(systemName: "link").accessibilityLabel(Text("Superset"))
                            }
                        }
                    }
                    ForEach(exercise.orderedSets) { set in
                        setRow(set, exercise: exercise)
                    }
                    Button("Dodaj seriju", systemImage: "plus") { store.addSet(to: exercise.id) }
                        .font(.footnote)
                }
            }
        }
    }

    private func setRow(_ set: SetSnapshot, exercise: ExerciseSnapshot) -> some View {
        let text = WatchSetField.fields(for: exercise.inputType)
            .map { $0.text(in: set, unit: store.unit) }
            .joined(separator: " × ")
        return HStack {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(set.isCompleted ? .green : .secondary)
            Text(text).monospacedDigit()
            if set.kind == .warmUp {
                Text("Z").font(.caption2).foregroundStyle(.orange)
                    .accessibilityLabel(Text("Zagrijavanje"))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            // Završena serija se dodirom vraća u nezavršene (npr. greškom označena).
            if set.isCompleted {
                store.uncomplete(set.id)
            } else {
                store.select(exercise.id)
                onSelect()
            }
        }
    }
}

// MARK: - Sažetak

struct WatchSummaryView: View {
    let summary: WatchWorkoutStore.Summary
    let onClose: () -> Void
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.name).font(.headline)
                row("Trajanje", Duration.seconds(summary.duration).formatted(.time(pattern: .hourMinuteSecond)))
                row("Serije", "\(summary.completedSets)")
                if summary.volumeKg > 0 {
                    row("Volumen", WeightFormatter(unit: store.unit).string(fromKilograms: summary.volumeKg))
                }
                if let energy = summary.activeEnergyKilocalories {
                    row("Kalorije", "\(Int(energy.rounded())) kcal")
                }
                if let heartRate = summary.averageHeartRate {
                    row("Prosječni puls", "\(Int(heartRate.rounded())) BPM")
                }
                Button("Zatvori", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).monospacedDigit())
        }
    }
}
