import Catalog
import Models
import Planning
import SwiftData
import SwiftUI
import Units

extension TrainingGoal {
    var title: LocalizedStringKey {
        switch self {
        case .hypertrophy: "Hipertrofija"
        case .strength: "Snaga"
        case .recomposition: "Rekompozicija"
        case .generalFitness: "Opća kondicija"
        }
    }
}

extension Sex {
    var title: LocalizedStringKey {
        switch self {
        case .female: "Žensko"
        case .male: "Muško"
        }
    }
}

extension ExperienceLevel {
    var title: LocalizedStringKey {
        switch self {
        case .beginner: "Početnik"
        case .intermediate: "Srednji"
        case .advanced: "Napredni"
        }
    }
}

extension TrainingGoal {
    /// Kratki naziv za kartice u onboardingu.
    var shortTitle: LocalizedStringKey {
        switch self {
        case .hypertrophy: "Mišići"
        case .strength: "Snaga"
        case .recomposition: "Rekompozicija"
        case .generalFitness: "Kondicija"
        }
    }

    var symbol: String {
        switch self {
        case .hypertrophy: "figure.strengthtraining.traditional"
        case .strength: "bolt.fill"
        case .recomposition: "arrow.triangle.2.circlepath"
        case .generalFitness: "heart.fill"
        }
    }
}

extension ExperienceLevel {
    /// Što razina znači, ispod odabira u onboardingu.
    var detail: LocalizedStringKey {
        switch self {
        case .beginner: "Redovno treniram manje od 6 mjeseci"
        case .intermediate: "Redovno treniram 6 mjeseci do 2 godine"
        case .advanced: "Redovno treniram više od 2 godine"
        }
    }
}

extension EquipmentPreset {
    /// Kratki naziv za kartice u onboardingu.
    var shortTitle: LocalizedStringKey {
        switch self {
        case .gym: "Teretana"
        case .homeGym: "Kućna teretana"
        case .dumbbells: "Bučice i trake"
        case .bodyweightOnly: "Bez opreme"
        }
    }
}

/// Onboarding kao list preko Početne, u dva kratka koraka: "Kako treniraš?" (cilj, dani, oprema) i
/// "Još malo o tebi" (iskustvo, težina, spol, Apple Zdravlje). Sve je neobavezno i bira se dodirom.
/// Ako je korisnik odgovorio o treningu, isti list naraste i nudi gotov raspored.
///
/// Isti list otvara i kartica "Postavi profil" na Početnoj (naknadno ispunjavanje), s odgovorima iz postavki.
/// "Preskoči" i zatvaranje povlačenjem spremaju samo da je onboarding obavljen i odgovor o Zdravlju.
struct OnboardingScreen: View {
    private enum Step {
        case training, about, recommendation
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var answers: OnboardingAnswers
    @State private var weightText = ""
    @State private var step = Step.training
    /// Program koji ima manje dana od cilja, dok korisnik ne odgovori na upozorenje.
    @State private var pendingProgram: Program?
    @State private var isConnectingHealth = false
    /// Odgovori su spremljeni (ili preskočeni): zatvaranje lista više ništa ne sprema.
    @State private var finished = false
    @State private var errorText: String?
    /// Visina sadržaja koraka, za list koji ne prekriva cijeli zaslon.
    @State private var contentHeight: CGFloat = 520
    @State private var detent = PresentationDetent.large

    init(settings: UserSettings? = nil) {
        _answers = State(initialValue: settings.map(OnboardingAnswers.init(settings:)) ?? OnboardingAnswers())
    }

    private var profile: TrainingProfile { TrainingProfile(answers: answers) }

    /// Visina lista za korak: sadržaj i ručica, a s velikim tekstom list se može povući do vrha.
    private var fittedDetent: PresentationDetent { .height(contentHeight + 24) }

    var body: some View {
        ScrollView {
            Group {
                switch step {
                case .training: trainingStep
                case .about: aboutStep
                case .recommendation: recommendationStep
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(step == .recommendation ? [.large] : [fittedDetent, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: step, initial: true) { updateDetent() }
        .onChange(of: contentHeight) { if step != .recommendation, detent != .large { detent = fittedDetent } }
        .daysGoalWarning(profile: profile, program: $pendingProgram) { program, days in complete(program, newDaysGoal: days) }
        .errorAlert($errorText)
        // Zatvaranje povlačenjem je isto što i "Preskoči".
        .onDisappear { if !finished { skip() } }
    }

    private func go(to next: Step) {
        withAnimation(reduceMotion ? nil : .default) { step = next }
    }

    private func updateDetent() {
        detent = step == .recommendation ? .large : fittedDetent
    }

    // MARK: Zaglavlje

    private func header(back: Bool, progress: Int?) -> some View {
        HStack {
            if back {
                Button("Natrag", systemImage: "chevron.left") { go(to: step == .recommendation ? .about : .training) }
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            if step != .recommendation {
                Button("Preskoči") { skip() }
            }
        }
        .overlay {
            if let progress {
                HStack(spacing: 5) {
                    ForEach(1...2, id: \.self) { index in
                        Capsule()
                            .fill(index <= progress ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: 20, height: 4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Korak \(progress) od 2"))
            }
        }
        .frame(minHeight: 32)
    }

    private func title(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.cardTitle).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, 20)
    }

    // MARK: 1. Kako treniraš

    private var trainingStep: some View {
        VStack(spacing: 0) {
            header(back: false, progress: 1)
            title("Kako treniraš?", subtitle: "Za prijedlog rasporeda. Sve možeš promijeniti poslije.")
                .padding(.top, 8)
            label("Cilj")
            ChoiceGrid(TrainingGoal.allCases, selection: $answers.goal) { goal in
                Label(goal.shortTitle, systemImage: goal.symbol)
            }
            label("Dana tjedno")
            DaysPicker(days: $answers.daysPerWeek)
            label("Gdje treniraš")
            ChoiceGrid(EquipmentPreset.allCases, selection: equipmentPreset) { preset in
                Text(preset.shortTitle)
            }
            primaryButton("Dalje") { go(to: .about) }
        }
    }

    /// Preset opreme; vlastiti popis iz Postavki ostaje dok korisnik ne odabere preset.
    private var equipmentPreset: Binding<EquipmentPreset?> {
        Binding(
            get: { EquipmentPreset.matching(answers.equipment) },
            set: { answers.equipment = $0?.equipment ?? [] }
        )
    }

    // MARK: 2. O tebi

    private var aboutStep: some View {
        VStack(spacing: 0) {
            header(back: true, progress: 2)
            title("Još malo o tebi", subtitle: "Neobavezno, za prijedlog i statistiku.")
                .padding(.top, 8)
            label("Iskustvo")
            Picker("Iskustvo", selection: $answers.experience) {
                ForEach(ExperienceLevel.allCases, id: \.self) { Text($0.title).tag(ExperienceLevel?.some($0)) }
            }
            .pickerStyle(.segmented)
            if let experience = answers.experience {
                Text(experience.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            label("Težina")
            HStack(spacing: 10) {
                TextField("Neobavezno", text: $weightText)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: CornerRadius.inner))
                    .accessibilityLabel(Text("Težina"))
                Picker("Jedinice", selection: $answers.unit) {
                    Text(WeightUnit.kilograms.symbol).tag(WeightUnit.kilograms)
                    Text(WeightUnit.pounds.symbol).tag(WeightUnit.pounds)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            label("Spol")
            ChoiceGrid(Sex.allCases, selection: $answers.sex) { Text($0.title) }
            Text("Za DOTS bodove i tijelo na prikazu mišića.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            if HealthService.shared.isAvailable {
                healthRow.padding(.top, 16)
            }
            primaryButton(profile.hasAnswers ? "Pokaži prijedlog" : "Gotovo") { saveAnswers() }
        }
    }

    /// Apple Zdravlje kao jedan redak: sistemska dozvola traži se tek na dodir "Poveži".
    private var healthRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .frame(width: 32, height: 32)
                .background(.background, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Zdravlje").font(.subheadline.weight(.semibold))
                Text("Treninzi u prstenove, kardio i težina").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if answers.wantsHealthKit {
                Label("Povezano", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            } else {
                Button("Poveži") { connectHealth() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(isConnectingHealth)
            }
        }
        .padding(12)
        .background(Color(.quaternarySystemFill), in: .rect(cornerRadius: CornerRadius.inner))
    }

    // MARK: Prijedlog

    private var recommendationStep: some View {
        VStack(spacing: 0) {
            header(back: true, progress: nil)
            title("Tvoj prijedlog", subtitle: "Prema tvojim odgovorima.")
                .padding(.top, 8)
            ProgramRecommendationCards(profile: profile) { choose($0) }
                .padding(.top, 16)
            Button("Složit ću sam") { complete(nil, newDaysGoal: nil) }
                .padding(.top, 24)
            Text("Svi programi su i u kartici Rasporedi.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: Spremanje

    private func saveAnswers() {
        answers.weight = NumberInput.parse(weightText)
        // Prijedlog samo kad ima na temelju čega: inače list odmah završava.
        if profile.hasAnswers {
            go(to: .recommendation)
        } else {
            complete(nil, newDaysGoal: nil)
        }
    }

    private func choose(_ program: Program) {
        if profile.lowerDaysGoal(for: program) != nil {
            pendingProgram = program
        } else {
            complete(program, newDaysGoal: nil)
        }
    }

    private func connectHealth() {
        isConnectingHealth = true
        Task {
            await HealthService.shared.requestAuthorization()
            isConnectingHealth = false
            answers.wantsHealthKit = true
        }
    }

    /// Sprema odgovore (onboarding je time obavljen) i po želji dodaje program. Novi cilj dana tjedno kad je
    /// korisnik u upozorenju pristao smanjiti ga.
    private func complete(_ program: Program?, newDaysGoal: Int?) {
        do {
            if let newDaysGoal { answers.daysPerWeek = newDaysGoal }
            try OnboardingApplier(context: context).apply(answers)
            if let program {
                try ProgramAdder.add(program, profile: profile, context: context, catalogStore: catalogStore)
            }
            finish()
        } catch {
            errorText = String(localized: "Odgovori se nisu mogli spremiti.")
        }
    }

    /// "Preskoči" i zatvaranje povlačenjem: od odgovora se sprema samo onaj o Zdravlju.
    private func skip() {
        guard !finished else { return }
        try? OnboardingApplier(context: context).skip(wantsHealthKit: answers.wantsHealthKit)
        finish()
    }

    private func finish() {
        finished = true
        if answers.wantsHealthKit {
            Task { await HealthService.shared.importNewData(context: context) }
        }
        dismiss()
    }
}
