import Connectivity
import Models
import SwiftUI
import Training
import Units

// MARK: - Kontrole

/// Trajanje, puls i kalorije preko većeg dijela zaslona, napredak treninga te završetak i odbacivanje pri dnu.
struct WatchControlsView: View {
    @Environment(WatchWorkoutStore.self) private var store
    @State private var confirmsFinish = false
    @State private var confirmsDiscard = false
    @State private var showsNothingCompleted = false
    @ScaledMetric(relativeTo: .largeTitle) var durationSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let active = store.active {
                Text(active.startedAt, style: .timer)
                    .font(.system(size: durationSize, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 2)
                if store.showsHealthMetrics {
                    metrics
                }
                if !store.isController {
                    Label("Trening vodi iPhone", systemImage: "iphone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                progress(active)
                Spacer(minLength: 2)
            }
            HStack {
                Button("Završi") { confirmsFinish = true }
                    .buttonStyle(.borderedProminent)
                Button("Odbaci", role: .destructive) { confirmsDiscard = true }
            }
            .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .scenePadding(.horizontal)
        // Iznad točkica stranica, da ih gumbi nikad ne prekriju.
        .padding(.bottom, 14)
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
        VStack(alignment: .leading, spacing: 0) {
            metric(store.health.heartRate, unit: "BPM", symbol: "heart.fill", color: .red)
            metric(store.health.activeEnergyKilocalories, unit: "kcal", symbol: "flame.fill", color: .orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ value: Double?, unit: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(.title, design: .rounded, weight: .semibold).monospacedDigit())
            Text(unit).font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// "9 serija · Vježbe: 3 od 6".
    private func progress(_ active: SessionSnapshot) -> some View {
        HStack(spacing: 4) {
            Text("\(active.completedSetCount) serija")
            Text(verbatim: "·")
            Text("Vježbe: \(active.completedExerciseCount) od \(active.visibleExercises.count)")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Popis vježbi

/// Pregled cijelog treninga i prethodnih serija, kao kartica vježbe na iPhoneu. Dodir na vježbu otvara je
/// na ekranu serije, a dodir na završenu seriju poništava kvačicu.
struct WatchExerciseListView: View {
    let onSelect: () -> Void
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        List {
            ForEach(store.active?.visibleExercises ?? []) { exercise in
                let isCurrent = exercise.id == store.currentExerciseID
                let nextSetID = store.currentSet.flatMap { $0.exercise.id == exercise.id ? $0.set.id : nil }
                Section {
                    Button {
                        store.select(exercise.id)
                        onSelect()
                    } label: {
                        header(exercise, isCurrent: isCurrent)
                    }
                    ForEach(exercise.orderedSets) { set in
                        setRow(set, exercise: exercise, isNext: isCurrent && set.id == nextSetID)
                    }
                    Button("Dodaj seriju", systemImage: "plus") { store.addSet(to: exercise.id) }
                        .font(.footnote)
                }
            }
        }
    }

    private func header(_ exercise: ExerciseSnapshot, isCurrent: Bool) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.exercise.name)
                    .font(.itemTitle)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary))
                Text("\(exercise.completedSetCount) od \(exercise.sets.count) serija")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if store.isCardio(exercise) {
                Image(systemName: "figure.run")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text("Kardio"))
            }
            if exercise.supersetGroupId != nil {
                Image(systemName: "link").accessibilityLabel(Text("Superset"))
            }
        }
    }

    private func setRow(_ set: SetSnapshot, exercise: ExerciseSnapshot, isNext: Bool) -> some View {
        let text = WatchSetField.fields(for: exercise.inputType)
            .map { $0.text(in: set, unit: store.unit) }
            .joined(separator: " × ")
        return HStack(spacing: 8) {
            WatchSetBadge(number: exercise.workingNumber(ofSet: set.id), isCurrent: isNext)
            Text(text)
                .font(.rowValue)
                .foregroundStyle(set.isCompleted || isNext ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if set.isCompleted {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text("Završeno"))
            }
        }
        .contentShape(.rect)
        .listRowBackground(
            isNext ? AnyView(RoundedRectangle(cornerRadius: 10).fill(.tint.opacity(0.25))) : nil
        )
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

/// Isti redci kao sažetak na iPhoneu: trening samo s kardiom nema serije ni volumen, a kardio dio
/// se prikazuje u minutama.
struct WatchSummaryView: View {
    let summary: WatchWorkoutStore.Summary
    let onClose: () -> Void
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    WatchWorkoutMixIcon(mix: summary.mix)
                    Text(summary.name)
                        .lineLimit(2)
                }
                .font(.cardTitle)

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(Array(rows.chunked(by: 2).enumerated()), id: \.offset) { _, pair in
                        GridRow {
                            ForEach(Array(pair.enumerated()), id: \.offset) { _, row in
                                cell(row.title, row.value)
                            }
                        }
                    }
                }

                Button("Gotovo", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scenePadding(.horizontal)
    }

    private struct Row {
        var title: LocalizedStringKey
        var value: String
    }

    private var rows: [Row] {
        var result = [Row(title: "Trajanje", value: Duration.seconds(summary.duration).formatted(.time(pattern: .hourMinuteSecond)))]
        if summary.mix != .cardio {
            result.append(Row(title: "Serije", value: "\(summary.completedSets)"))
            if summary.volumeKg > 0 {
                result.append(Row(title: "Volumen", value: WeightFormatter(unit: store.unit).string(fromKilograms: summary.volumeKg)))
            }
        }
        if let cardio = summary.cardio {
            let minutes = Int((Double(cardio.seconds) / 60).rounded())
            result.append(Row(title: "Kardio", value: String(localized: "\(String(minutes)) min")))
        }
        if let heartRate = summary.averageHeartRate {
            result.append(Row(title: "Prosječni puls", value: "\(Int(heartRate.rounded())) BPM"))
        }
        if let energy = summary.activeEnergyKilocalories {
            result.append(Row(title: "Kalorije", value: "\(Int(energy.rounded())) kcal"))
        }
        return result
    }

    private func cell(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private extension Array {
    /// Dijeli niz u skupine od najviše `size` elemenata (redci mreže sažetka).
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
