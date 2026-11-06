import Catalog
import Models
import SwiftUI
import Training
import Units

/// Jedan redak tablice serija: oznaka, prošli put (i napor ispod njega), polja u stupcima i velika kvačica desno.
/// Stupci su iste širine u svim retcima i u zaglavlju (`SetTableHeader`), pa su brojevi poravnati.
/// Kod najvećih veličina teksta redak prelazi u okomiti raspored bez stupaca.
/// Završena serija se zasivi, a kvačica ostaje zelena.
/// Polja drže vlastiti tekst. Izmjena ide u model (i u bazu) kad korisnik potvrdi kotačić ili tipka u polje.
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
    /// Tekst koji je polje dobilo iz modela (promjena sa sata ili iz Live Activityja). Njegov `onChange` ne smije
    /// vratiti vrijednost u model, jer bi se zaokružena vratila natrag i još jednom spremila.
    @State private var syncedTexts: [Field: String] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    private var metrics = SetTableMetrics()

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
        HStack(spacing: 12) {
            content
                // Završena serija se zasivi i priguši, osim kad korisnik traži jači kontrast.
                .saturation(isDimmed ? 0 : 1)
                .opacity(isDimmed ? 0.45 : 1)
            completeButton
        }
        // Kvačica se rasteže na visinu cijelog retka.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.2), value: set.isCompleted)
        .sheet(isPresented: $showsPlates) {
            PlateCalculatorSheet(targetText: weightText, unit: unit)
        }
        // Boja aktivne serije je samo pozadina retka; polja, oznaka i kvačica su na neprozirnoj podlozi iznad nje.
        .listRowBackground(isHighlighted ? highlightBackground : nil)
        // Serija se može promijeniti i izvana (sat, Live Activity). Polje tada preuzima novu vrijednost,
        // da ga kvačica (`applyAllFields`) ne bi vratila na staru. Vlastiti unos se ne dira, jer nakon
        // `apply` model već odgovara tekstu u polju.
        .onChange(of: Self.load(of: set, inputType: inputType)) { syncWeight() }
        .onChange(of: unit) { syncWeight() }
        .onChange(of: set.reps) { syncReps() }
        .onChange(of: set.durationSeconds) { syncDuration() }
        .onChange(of: set.distanceMeters) { syncDistance() }
    }

    /// Boja aktivne serije preko obične boje retka, da redak ostane neprozirna kartica.
    private var highlightBackground: some View {
        Color.accentColor.opacity(0.12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var isDimmed: Bool {
        dimsCompleted && set.isCompleted && contrast != .increased
    }

    // `self.` je nužan: redak koji počinje sa `set` Swift čita kao setter.
    private var showsEffort: Bool {
        self.set.rpe != nil || isHighlighted || !set.isCompleted
    }

    /// Lijevi dio retka: oznaka, prošli put s naporom ispod i polja u stupcima.
    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Kod najvećih veličina teksta svaki dio ide u svoj redak, da se ništa ne reže.
            VStack(alignment: .leading, spacing: 8) {
                kindBadge
                HStack(spacing: 6) { fields }
                infoLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: metrics.columnSpacing) {
                kindBadge
                    .frame(width: metrics.badge)
                VStack(alignment: .leading, spacing: 4) {
                    previousValue
                    if showsEffort { effortMenu }
                }
                .padding(.leading, metrics.previousInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                tableFields
            }
        }
    }

    /// Prošli put i napor u jednom retku ispod brojeva.
    @ViewBuilder
    private var infoLine: some View {
        if previousText != nil || showsEffort {
            HStack(spacing: 8) {
                previous
                if showsEffort { effortMenu }
            }
        }
    }

    // MARK: Dijelovi

    @ViewBuilder
    private var previous: some View {
        if let previousText {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.footnote)
                Text(verbatim: previousText)
                    .font(.rowValueSmall)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
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
            mainWeightField
            timesSign
            repsField
        case .bodyweight:
            repsField
        case .weightedBodyweight:
            weightField("Dodatna težina", "+\(unit.symbol)")
            timesSign
            repsField
        case .assisted:
            weightField("Pomoć", "−\(unit.symbol)")
            timesSign
            repsField
        case .duration:
            durationField
        case .durationDistance:
            durationField
            distanceField
        }
    }

    private func field(
        _ title: LocalizedStringKey, _ hint: String, _ text: Binding<String>, key: Field,
        keyboard: UIKeyboardType = .decimalPad, apply: @escaping () -> Void
    ) -> some View {
        TextField(hint, text: text)
            .keyboardType(keyboard)
            .setFieldFrame()
            .accessibilityLabel(Text(title))
            .onChange(of: text.wrappedValue) { _, new in userChanged(key, new, apply: apply) }
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
                .opaqueFill(.quaternary, in: .capsule)
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("Napor"))
        .accessibilityValue(set.rpe.map { Text(effortLabel($0)) } ?? Text("Bez ocjene"))
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

    /// Polja retka, za razlikovanje vlastitog unosa od teksta koji je stigao iz modela.
    private enum Field: Hashable {
        case weight, reps, duration, distance
    }

    /// Tekst polja se promijenio: vlastiti unos ide u model, a tekst koji je upisao `sync…` se preskače.
    private func userChanged(_ field: Field, _ text: String, apply: () -> Void) {
        if let synced = syncedTexts[field], synced == text {
            syncedTexts[field] = nil
            return
        }
        syncedTexts[field] = nil
        apply()
    }

    private func syncWeight() {
        let shown = Self.load(of: set, inputType: inputType).map { WeightConversion.displayValue(fromKilograms: $0, in: unit) }
        // Prikaz se zaokružuje na 0,05, pa unos s više decimala (npr. 82,53) ne smije prepisati sam sebe.
        guard !Self.same(NumberInput.parse(weightText), shown, tolerance: 0.051) else { return }
        setFromModel(.weight, NumberInput.format(shown), into: $weightText)
    }

    private func syncReps() {
        guard Int(reps.trimmingCharacters(in: .whitespaces)) != set.reps else { return }
        setFromModel(.reps, set.reps.map(String.init) ?? "", into: $reps)
    }

    private func syncDuration() {
        guard DurationInput.parse(duration) != set.durationSeconds else { return }
        setFromModel(.duration, DurationInput.format(set.durationSeconds), into: $duration)
    }

    private func syncDistance() {
        let kilometres = set.distanceMeters.map { $0 / 1000 }
        guard !Self.same(NumberInput.parse(distance), kilometres) else { return }
        setFromModel(.distance, NumberInput.format(kilometres), into: $distance)
    }

    private func setFromModel(_ field: Field, _ text: String, into binding: Binding<String>) {
        guard binding.wrappedValue != text else { return }
        syncedTexts[field] = text
        binding.wrappedValue = text
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

// MARK: Stupci tablice

extension SetRow {
    /// Prošli put u svom stupcu tablice, bez ikone (stupac ima naslov u zaglavlju).
    @ViewBuilder
    private var previousValue: some View {
        if let previousText {
            Text(verbatim: previousText)
                .font(.rowValueSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(Text("Prošli put \(previousText)"))
        }
    }

    /// Polja u stupcima fiksne širine, bez znaka × (stupci imaju naslove u zaglavlju).
    @ViewBuilder
    private var tableFields: some View {
        switch inputType {
        case .weightReps:
            mainWeightField.environment(\.setFieldWidth, metrics.wideField)
            repsField.environment(\.setFieldWidth, metrics.narrowField)
        case .bodyweight:
            repsField.environment(\.setFieldWidth, metrics.narrowField)
        case .weightedBodyweight:
            weightField("Dodatna težina", "+\(unit.symbol)").environment(\.setFieldWidth, metrics.wideField)
            repsField.environment(\.setFieldWidth, metrics.narrowField)
        case .assisted:
            weightField("Pomoć", "−\(unit.symbol)").environment(\.setFieldWidth, metrics.wideField)
            repsField.environment(\.setFieldWidth, metrics.narrowField)
        case .duration:
            durationField.environment(\.setFieldWidth, metrics.wideField)
        case .durationDistance:
            durationField.environment(\.setFieldWidth, metrics.wideField)
            distanceField.environment(\.setFieldWidth, metrics.wideField)
        }
    }

    private var mainWeightField: some View {
        WheelInputField.weight(
            "Težina", hint: unit.symbol, text: $weightText, unit: unit, fallback: weightFallback,
            longPress: ("Kalkulator ploča", { showsPlates = true })
        )
        .onChange(of: weightText) { _, new in userChanged(.weight, new, apply: applyWeight) }
    }

    private var durationField: some View {
        field("Trajanje", "m:ss", $duration, key: .duration, keyboard: .numbersAndPunctuation) { applyDuration() }
    }

    private var distanceField: some View {
        field("Udaljenost", "km", $distance, key: .distance) { applyDistance() }
    }
}

// MARK: Kotačić za težinu i ponavljanja

extension SetRow {
    private func weightField(_ title: LocalizedStringKey, _ hint: String) -> some View {
        WheelInputField.weight(title, hint: hint, text: $weightText, unit: unit, fallback: weightFallback)
            .onChange(of: weightText) { _, new in userChanged(.weight, new, apply: applyWeight) }
    }

    private var repsField: some View {
        WheelInputField.reps("Ponavljanja", hint: "×", text: $reps, fallback: suggestion?.reps ?? WheelOptions.defaultReps)
            .onChange(of: reps) { _, new in userChanged(.reps, new, apply: applyReps) }
    }

    /// Početak kotačića za praznu težinu: prošli trening, inače prazna šipka (ili 0 za dodatnu težinu i pomoć).
    private var weightFallback: Double {
        let isExtraLoad = inputType == .weightedBodyweight || inputType == .assisted
        let kilograms = isExtraLoad ? suggestion?.extraWeightKg : suggestion?.weightKg
        return kilograms.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) }
            ?? WheelOptions.defaultWeight(for: unit, isExtraLoad: isExtraLoad)
    }
}

// MARK: Kvačica i znak ×

extension SetRow {
    /// Znak između težine i ponavljanja; VoiceOver ga preskače jer polja imaju svoje nazive.
    private var timesSign: some View {
        Text(verbatim: "×")
            .font(.title3)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    /// Velika zelena kvačica uz desni rub retka: obrubljena dok serija nije završena, puna kad jest.
    private var completeButton: some View {
        Button {
            // Tekst iz polja ide u model prije provjere, i kad je polje još u fokusu, da prvi dodir ne javi lažnu grešku.
            if !set.isCompleted { applyAllFields() }
            onToggleComplete()
        } label: {
            Image(systemName: "checkmark")
                .font(.title2.weight(.bold))
                .foregroundStyle(set.isCompleted ? Color.white : Color.green)
                .frame(minWidth: metrics.check, maxHeight: .infinity)
                .frame(minHeight: metrics.rowHeight)
                .opaqueFill(
                    set.isCompleted ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.green.opacity(0.14)),
                    in: .rect(cornerRadius: CornerRadius.inner)
                )
                .overlay {
                    // Uz jači kontrast nezavršena kvačica dobiva i obrub, ne samo svijetlu pozadinu.
                    if !set.isCompleted && contrast == .increased {
                        RoundedRectangle(cornerRadius: CornerRadius.inner).strokeBorder(Color.green, lineWidth: 2)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(set.isCompleted ? Text("Poništi završetak serije") : Text("Označi seriju završenom"))
    }
}

// MARK: Zaglavlje tablice

/// Naslovi stupaca iznad serija vježbe, iste širine kao stupci u `SetRow`.
/// Kod najvećih veličina teksta retci nemaju stupce, pa se zaglavlje ne prikazuje.
struct SetTableHeader: View {
    let inputType: ExerciseInputType
    let unit: WeightUnit
    /// U uređivaču odrađenog treninga nema prošlog puta, pa stupac ostaje bez naslova.
    var showsPrevious = true

    private var metrics = SetTableMetrics()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(inputType: ExerciseInputType, unit: WeightUnit, showsPrevious: Bool = true) {
        self.inputType = inputType
        self.unit = unit
        self.showsPrevious = showsPrevious
    }

    var body: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 12) {
                HStack(spacing: metrics.columnSpacing) {
                    Text("Ser.")
                        .frame(width: metrics.badge)
                    Group {
                        if showsPrevious { Text("Prošli put") } else { Color.clear.frame(height: 1) }
                    }
                    .padding(.leading, metrics.previousInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        column.title
                            .frame(width: column.width)
                    }
                }
                Color.clear.frame(width: metrics.check, height: 1)
            }
            .font(.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityHidden(true)
        }
    }

    private var columns: [(title: Text, width: CGFloat)] {
        let reps = (title: Text("Pon."), width: metrics.narrowField)
        switch inputType {
        case .weightReps:
            return [(Text(verbatim: unit.symbol), metrics.wideField), reps]
        case .bodyweight:
            return [reps]
        case .weightedBodyweight:
            return [(Text(verbatim: "+\(unit.symbol)"), metrics.wideField), reps]
        case .assisted:
            return [(Text(verbatim: "−\(unit.symbol)"), metrics.wideField), reps]
        case .duration:
            return [(Text("Vrijeme"), metrics.wideField)]
        case .durationDistance:
            return [(Text("Vrijeme"), metrics.wideField), (Text(verbatim: "km"), metrics.wideField)]
        }
    }
}
