import Catalog
import Models
import SwiftUI
import Units

/// Jedan redak serije: oznaka, prošli put, polja za unos i kvačica.
/// Polja drže vlastiti tekst, a svaka izmjena odmah ide u model (i u bazu).
struct SetRow: View {
    let set: SetLog
    let inputType: ExerciseInputType
    let position: Int
    let previousText: String?
    let isHighlighted: Bool
    let unit: WeightUnit
    let effortScale: EffortScale
    let onEdit: () -> Void
    let onToggleComplete: () -> Void
    let onChangeKind: (SetKind) -> Void
    let onDelete: () -> Void

    @State private var weightText: String
    @State private var reps: String
    @State private var duration: String
    @State private var distance: String
    @State private var showsPlates = false

    init(
        set: SetLog, inputType: ExerciseInputType, position: Int, previousText: String?, isHighlighted: Bool,
        unit: WeightUnit, effortScale: EffortScale,
        onEdit: @escaping () -> Void, onToggleComplete: @escaping () -> Void,
        onChangeKind: @escaping (SetKind) -> Void, onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.inputType = inputType
        self.position = position
        self.previousText = previousText
        self.isHighlighted = isHighlighted
        self.unit = unit
        self.effortScale = effortScale
        self.onEdit = onEdit
        self.onToggleComplete = onToggleComplete
        self.onChangeKind = onChangeKind
        self.onDelete = onDelete

        let load = inputType == .weightedBodyweight || inputType == .assisted ? set.extraWeightKg : set.weightKg
        _weightText = State(initialValue: NumberInput.format(load.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) }))
        _reps = State(initialValue: set.reps.map(String.init) ?? "")
        _duration = State(initialValue: DurationInput.format(set.durationSeconds))
        _distance = State(initialValue: NumberInput.format(set.distanceMeters.map { $0 / 1000 }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                kindBadge
                if let previousText {
                    Text(previousText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52, alignment: .leading)
                        .accessibilityLabel(Text("Prošli put \(previousText)"))
                }
                fields
                Spacer(minLength: 0)
                completeButton
            }
            if set.rpe != nil || isHighlighted || !set.isCompleted {
                effortMenu
            }
        }
        .padding(.vertical, 4)
        .opacity(set.isCompleted ? 0.6 : 1)
        .sheet(isPresented: $showsPlates) {
            PlateCalculatorSheet(targetText: weightText, unit: unit)
        }
        .listRowBackground(isHighlighted ? Color.accentColor.opacity(0.12) : nil)
    }

    // MARK: Dijelovi

    private var kindBadge: some View {
        Menu {
            Button("Radna serija") { onChangeKind(.working) }
            Button("Zagrijavanje") { onChangeKind(.warmUp) }
            Button("Obriši seriju", role: .destructive, action: onDelete)
        } label: {
            Text(set.kind == .warmUp ? "Z" : "\(position)")
                .font(.subheadline.bold())
                .frame(width: 30, height: 30)
                .background(set.kind == .warmUp ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.15), in: .circle)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(set.kind == .warmUp ? Text("Zagrijavanje") : Text("Serija \(position)"))
    }

    @ViewBuilder
    private var fields: some View {
        switch inputType {
        case .weightReps:
            field("Težina", unit.symbol, $weightText) { applyWeight() }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in showsPlates = true })
            field("Ponavljanja", "×", $reps) { applyReps() }
        case .bodyweight:
            field("Ponavljanja", "×", $reps) { applyReps() }
        case .weightedBodyweight:
            field("Dodatna težina", "+\(unit.symbol)", $weightText) { applyWeight() }
            field("Ponavljanja", "×", $reps) { applyReps() }
        case .assisted:
            field("Pomoć", "−\(unit.symbol)", $weightText) { applyWeight() }
            field("Ponavljanja", "×", $reps) { applyReps() }
        case .duration:
            field("Trajanje", "m:ss", $duration, keyboard: .numbersAndPunctuation) { applyDuration() }
        case .durationDistance:
            field("Trajanje", "m:ss", $duration, keyboard: .numbersAndPunctuation) { applyDuration() }
            field("Udaljenost", "km", $distance) { applyDistance() }
        }
    }

    private func field(
        _ title: LocalizedStringKey, _ hint: String, _ text: Binding<String>,
        keyboard: UIKeyboardType = .decimalPad, apply: @escaping () -> Void
    ) -> some View {
        TextField(hint, text: text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .frame(minWidth: 52, maxWidth: 80)
            .padding(.vertical, 8)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .accessibilityLabel(Text(title))
            .onChange(of: text.wrappedValue) { _, _ in apply() }
    }

    private var completeButton: some View {
        Button {
            // Tekst iz polja ide u model prije provjere, i kad je polje još u fokusu, da prvi dodir ne javi lažnu grešku.
            if !set.isCompleted { applyAllFields() }
            onToggleComplete()
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(set.isCompleted ? Color.green : Color.secondary)
        .accessibilityLabel(set.isCompleted ? Text("Poništi završetak serije") : Text("Označi seriju završenom"))
    }

    private var effortMenu: some View {
        Menu {
            Button("Bez ocjene") { setRPE(nil) }
            ForEach(effortOptions, id: \.self) { rpe in
                Button(effortLabel(rpe)) { setRPE(rpe) }
            }
        } label: {
            Text(set.rpe.map { effortLabel($0) } ?? String(localized: effortScale == .rpe ? "RPE" : "RIR"))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 38)
    }

    // MARK: RPE

    /// RPE od 10 do 1 u koracima od 0,5. Uz RIR se nudi do 5 ponavljanja u rezervi (RPE 5).
    private var effortOptions: [Double] {
        stride(from: 10.0, through: effortScale == .rpe ? 1.0 : 5.0, by: -0.5).map { $0 }
    }

    private func effortLabel(_ rpe: Double) -> String {
        let value = effortScale == .rpe ? rpe : RPE.rir(fromRPE: rpe)
        let text = NumberInput.format(value)
        return effortScale == .rpe ? "RPE \(text)" : "RIR \(text)"
    }

    private func setRPE(_ value: Double?) {
        set.rpe = value
        onEdit()
    }

    // MARK: Primjena unosa

    private func applyAllFields() {
        switch inputType {
        case .weightReps, .weightedBodyweight, .assisted:
            applyWeight()
            applyReps()
        case .bodyweight:
            applyReps()
        case .duration:
            applyDuration()
        case .durationDistance:
            applyDuration()
            applyDistance()
        }
    }

    private func applyWeight() {
        let kilograms = NumberInput.parse(weightText).map { WeightConversion.kilograms(from: $0, in: unit) }
        if inputType == .weightedBodyweight || inputType == .assisted {
            set.extraWeightKg = kilograms
        } else {
            set.weightKg = kilograms
        }
        onEdit()
    }

    private func applyReps() {
        set.reps = Int(reps.trimmingCharacters(in: .whitespaces))
        onEdit()
    }

    private func applyDuration() {
        set.durationSeconds = DurationInput.parse(duration)
        onEdit()
    }

    private func applyDistance() {
        set.distanceMeters = NumberInput.parse(distance).map { $0 * 1000 }
        onEdit()
    }
}
