import Catalog
import Models
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

    var detail: LocalizedStringKey {
        switch self {
        case .hypertrophy: "Veći mišići"
        case .strength: "Veća maksimalna težina"
        case .recomposition: "Manje masti, više mišića"
        case .generalFitness: "Zdravlje i forma"
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

/// Prvo pokretanje: nekoliko kratkih pitanja. Sve osim jedinica i odgovora o Apple Zdravlju je neobavezno,
/// a cijeli se onboarding može preskočiti. Odgovori se mogu kasnije promijeniti u Postavkama.
struct OnboardingScreen: View {
    private enum Step: Int, CaseIterable {
        case goal, units, body, health, experience, equipment
    }

    @Environment(\.modelContext) private var context
    @State private var step = Step.goal
    @State private var answers = OnboardingAnswers()
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var errorText: String?

    private var isLast: Bool { step == Step.allCases.last }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Korak \(step.rawValue + 1) od \(Step.allCases.count)")
                        .font(.footnote).foregroundStyle(.secondary)
                    content
                }
                .padding()
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Preskoči sve") { skipAll() }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .alert("Greška", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("U redu") {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .interactiveDismissDisabled()
    }

    private var title: LocalizedStringKey {
        switch step {
        case .goal: "Dobro došao"
        case .units: "Jedinice"
        case .body: "Tijelo"
        case .health: "Apple Zdravlje"
        case .experience: "Iskustvo"
        case .equipment: "Oprema i dani"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .goal: goalStep
        case .units: unitsStep
        case .body: bodyStep
        case .health: healthStep
        case .experience: experienceStep
        case .equipment: equipmentStep
        }
    }

    // MARK: Koraci

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Što je tvoj cilj?").font(.title3.bold())
            ForEach(TrainingGoal.allCases, id: \.self) { goal in
                ChoiceRow(isSelected: answers.goal == goal) {
                    answers.goal = answers.goal == goal ? nil : goal
                } label: {
                    VStack(alignment: .leading) {
                        Text(goal.title)
                        Text(goal.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var unitsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("U kojoj jedinici bilježiš težinu?").font(.title3.bold())
            ChoiceRow(isSelected: answers.unit == .kilograms) { answers.unit = .kilograms } label: {
                Text("Kilogrami (kg)")
            }
            ChoiceRow(isSelected: answers.unit == .pounds) { answers.unit = .pounds } label: {
                Text("Funte (lbs)")
            }
            Text("Težina se interno uvijek sprema u kilogramima, pa jedinicu možeš kasnije promijeniti u Postavkama.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visina i težina").font(.title3.bold())
            Text("Neobavezno. Služi za praćenje mjera tijela; možeš ih unijeti i kasnije.")
                .font(.footnote).foregroundStyle(.secondary)
            LabeledContent("Visina") {
                HStack {
                    TextField("Neobavezno", text: $heightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("cm").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Težina") {
                HStack {
                    TextField("Neobavezno", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text(answers.unit.symbol).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Povezati s Apple Zdravljem?").font(.title3.bold())
            Text("Treninzi se spremaju u Zdravlje i ulaze u Activity prstenove, a kardio treninzi, težina i visina dolaze iz njega. Aplikacija radi i bez toga, a odluku mijenjaš u Postavkama.")
                .font(.subheadline).foregroundStyle(.secondary)
            ChoiceRow(isSelected: answers.wantsHealthKit) {
                answers.wantsHealthKit = true
                // Sistemski list s dozvolama odmah, dok je objašnjenje na zaslonu.
                Task { await HealthService.shared.requestAuthorization() }
            } label: {
                Text("Da, poveži")
            }
            ChoiceRow(isSelected: !answers.wantsHealthKit) { answers.wantsHealthKit = false } label: {
                Text("Ne sada")
            }
        }
    }

    private var experienceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Koliko dugo treniraš?").font(.title3.bold())
            ForEach(ExperienceLevel.allCases, id: \.self) { level in
                ChoiceRow(isSelected: answers.experience == level) {
                    answers.experience = answers.experience == level ? nil : level
                } label: {
                    Text(level.title)
                }
            }
        }
    }

    private var equipmentStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dostupna oprema").font(.title3.bold())
            ForEach(Equipment.allCases, id: \.self) { item in
                ChoiceRow(isSelected: answers.equipment.contains(item), isMultiple: true) {
                    if answers.equipment.contains(item) {
                        answers.equipment.removeAll { $0 == item }
                    } else {
                        answers.equipment.append(item)
                    }
                } label: {
                    Text(item.title)
                }
            }
            Text("Koliko dana tjedno treniraš?").font(.title3.bold()).padding(.top, 8)
            HStack {
                ForEach(OnboardingAnswers.daysPerWeekRange, id: \.self) { days in
                    Button {
                        answers.daysPerWeek = answers.daysPerWeek == days ? nil : days
                    } label: {
                        Text("\(days)")
                            .frame(width: 36, height: 36)
                            .background(answers.daysPerWeek == days ? Color.accentColor : Color(.secondarySystemFill), in: Circle())
                            .foregroundStyle(answers.daysPerWeek == days ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(answers.daysPerWeek == days ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Navigacija

    private var bottomBar: some View {
        HStack {
            if step != .goal {
                Button("Natrag") { go(-1) }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(isLast ? "Gotovo" : "Dalje") { isLast ? finish() : go(1) }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation { step = next }
    }

    private func finish() {
        answers.heightCm = NumberInput.parse(heightText)
        answers.weight = NumberInput.parse(weightText)
        do {
            try OnboardingApplier(context: context).apply(answers)
            if answers.wantsHealthKit {
                Task { await HealthService.shared.importNewData(context: context) }
            }
        } catch {
            errorText = String(localized: "Odgovori se nisu mogli spremiti.")
        }
    }

    private func skipAll() {
        do {
            try OnboardingApplier(context: context).skip()
        } catch {
            errorText = String(localized: "Odgovori se nisu mogli spremiti.")
        }
    }
}

/// Redak izbora s kvačicom (jedan izbor) ili kućicom (više izbora).
private struct ChoiceRow<Label: View>: View {
    let isSelected: Bool
    var isMultiple = false
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack {
                label
                Spacer()
                Image(systemName: isSelected ? (isMultiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (isMultiple ? "square" : "circle"))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
