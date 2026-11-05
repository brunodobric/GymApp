import Catalog
import Models
import SwiftUI
import Training
import Units

/// Jedan redak serije: oznaka, prošli put, polja za unos i kvačica.
/// Polja drže vlastiti tekst, a svaka izmjena odmah ide u model (i u bazu).
/// Težina i ponavljanja se biraju kotačićem (`WheelInputField`), trajanje i udaljenost tipkovnicom.
struct SetRow: View {
    let set: SetLog
    let inputType: ExerciseInputType
    let position: Int
    let previousText: String?
    /// Vrijednosti prošlog treninga za ovu seriju, na koje se kotačić postavi kad je polje prazno.
    let suggestion: SetValues?
    let isHighlighted: Bool
    let unit: WeightUnit
    let effortScale: EffortScale
    /// Završene serije su prigušene u aktivnom treningu; u uređivaču odrađenog treninga su sve završene.
    let dimsCompleted: Bool
    let onEdit: () -> Void
    let onToggleComplete: () -> Void
    let onChangeKind: (SetKind) -> Void
    let onDelete: () -> Void

    @State private var weightText: String
    @State private var reps: String
    @State private var duration: String
    @State private var distance: String
    @State private var showsPlates = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        set: SetLog, inputType: ExerciseInputType, position: Int, previousText: String?, suggestion: SetValues?,
        isHighlighted: Bool,
        unit: WeightUnit, effortScale: EffortScale, dimsCompleted: Bool = true,
        onEdit: @escaping () -> Void, onToggleComplete: @escaping () -> Void,
        onChangeKind: @escaping (SetKind) -> Void, onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.inputType = inputType
        self.position = position
        self.previousText = previousText
        self.suggestion = suggestion
        self.isHighlighted = isHighlighted
        self.unit = unit
        self.effortScale = effortScale
        self.dimsCompleted = dimsCompleted
        self.onEdit = onEdit
        self.onToggleComplete = onToggleComplete
        self.onChangeKind = onChangeKind
        self.onDelete = onDelete

        _weightText = State(initialValue: Self.weightText(Self.load(of: set, inputType: inputType), unit: unit))
        _reps = State(initialValue: set.reps.map(String.init) ?? "")
        _duration = State(initialValue: DurationInput.format(set.durationSeconds))
        _distance = State(initialValue: NumberInput.format(set.distanceMeters.map { $0 / 1000 }))
    }

    /// Težina koju polje prikazuje: dodatna težina ili pomoć za vježbe s vlastitom težinom, inače težina.
    private static func load(of set: SetLog, inputType: ExerciseInputType) -> Double? {
        inputType == .weightedBodyweight || inputType == .assisted ? set.extraWeightKg : set.weightKg
    }

    private static func weightText(_ kilograms: Double?, unit: WeightUnit) -> String {
        NumberInput.format(kilograms.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                // Kod najvećih veličina teksta polja idu u svoj redak, da se ništa ne reže.
                HStack(spacing: 8) {
                    kindBadge
                    previous
                    Spacer(minLength: 0)
                    completeButton
                }
                HStack(spacing: 8) { fields }
            } else {
                HStack(spacing: 8) {
                    kindBadge
                    previous
                    fields
                    Spacer(minLength: 0)
                    completeButton
                }
            }
            if set.rpe != nil || isHighlighted || !set.isCompleted {
                effortMenu
            }
        }
        .padding(.vertical, 4)
        // Završene serije su prigušene, osim kad korisnik traži jači kontrast.
        .opacity(dimsCompleted && set.isCompleted && contrast != .increased ? 0.6 : 1)
        .sheet(isPresented: $showsPlates) {
            PlateCalculatorSheet(targetText: weightText, unit: unit)
        }
        .listRowBackground(isHighlighted ? Color.accentColor.opacity(0.12) : nil)
        // Serija se može promijeniti i izvana (sat, Live Activity). Polje tada preuzima novu vrijednost,
        // da ga kvačica (`applyAllFields`) ne bi vratila na staru. Vlastiti unos se ne dira, jer nakon
        // `apply` model već odgovara tekstu u polju.
        .onChange(of: Self.load(of: set, inputType: inputType)) { syncWeight() }
        .onChange(of: unit) { syncWeight() }
        .onChange(of: set.reps) { syncReps() }
        .onChange(of: set.durationSeconds) { syncDuration() }
        .onChange(of: set.distanceMeters) { syncDistance() }
    }

    // MARK: Dijelovi

    @ViewBuilder
    private var previous: some View {
        if let previousText {
            Text(previousText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .leading)
                .accessibilityLabel(Text("Prošli put \(previousText)"))
        }
    }

    private var kindBadge: some View {
        Menu {
            Button("Radna serija") { onChangeKind(.working) }
            Button("Zagrijavanje") { onChangeKind(.warmUp) }
            Button("Obriši seriju", role: .destructive, action: onDelete)
        } label: {
            SetBadge(kind: set.kind, number: position)
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var fields: some View {
        switch inputType {
        case .weightReps:
            WheelInputField.weight(
                "Težina", hint: unit.symbol, text: $weightText, unit: unit, fallback: weightFallback,
                longPress: ("Kalkulator ploča", { showsPlates = true })
            )
            .onChange(of: weightText) { _, _ in applyWeight() }
            repsField
        case .bodyweight:
            repsField
        case .weightedBodyweight:
            weightField("Dodatna težina", "+\(unit.symbol)")
            repsField
        case .assisted:
            weightField("Pomoć", "−\(unit.symbol)")
            repsField
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
            .setFieldFrame()
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
        .accessibilityLabel(Text("Napor"))
        .accessibilityValue(set.rpe.map { Text(effortLabel($0)) } ?? Text("Bez ocjene"))
        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 38)
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

    // MARK: Promjene izvana

    private func syncWeight() {
        let shown = Self.load(of: set, inputType: inputType).map { WeightConversion.displayValue(fromKilograms: $0, in: unit) }
        // Prikaz se zaokružuje na 0,05, pa unos s više decimala (npr. 82,53) ne smije prepisati sam sebe.
        guard !Self.same(NumberInput.parse(weightText), shown, tolerance: 0.051) else { return }
        weightText = NumberInput.format(shown)
    }

    private func syncReps() {
        guard Int(reps.trimmingCharacters(in: .whitespaces)) != set.reps else { return }
        reps = set.reps.map(String.init) ?? ""
    }

    private func syncDuration() {
        guard DurationInput.parse(duration) != set.durationSeconds else { return }
        duration = DurationInput.format(set.durationSeconds)
    }

    private func syncDistance() {
        let kilometres = set.distanceMeters.map { $0 / 1000 }
        guard !Self.same(NumberInput.parse(distance), kilometres) else { return }
        distance = NumberInput.format(kilometres)
    }

    private static func same(_ lhs: Double?, _ rhs: Double?, tolerance: Double = 0.001) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): abs(lhs - rhs) < tolerance
        default: false
        }
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

// MARK: Kotačić za težinu i ponavljanja

extension SetRow {
    private func weightField(_ title: LocalizedStringKey, _ hint: String) -> some View {
        WheelInputField.weight(title, hint: hint, text: $weightText, unit: unit, fallback: weightFallback)
            .onChange(of: weightText) { _, _ in applyWeight() }
    }

    private var repsField: some View {
        WheelInputField.reps("Ponavljanja", hint: "×", text: $reps, fallback: suggestion?.reps ?? WheelOptions.defaultReps)
            .onChange(of: reps) { _, _ in applyReps() }
    }

    /// Početak kotačića za praznu težinu: prošli trening, inače prazna šipka (ili 0 za dodatnu težinu i pomoć).
    private var weightFallback: Double {
        let isExtraLoad = inputType == .weightedBodyweight || inputType == .assisted
        let kilograms = isExtraLoad ? suggestion?.extraWeightKg : suggestion?.weightKg
        return kilograms.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) }
            ?? WheelOptions.defaultWeight(for: unit, isExtraLoad: isExtraLoad)
    }
}
