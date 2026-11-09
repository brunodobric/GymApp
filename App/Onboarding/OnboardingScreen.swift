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

/// Prvo pokretanje: jedna kratka stranica. Sve osim jedinica je neobavezno, a sve se može preskočiti i
/// kasnije upisati u Postavkama. Nakon spremanja, ako je korisnik odgovorio o treningu, nudi se gotov raspored
/// prema cilju, danima, iskustvu i opremi. Na kraju (i nakon "Preskoči") zaseban zaslon traži izričit odgovor
/// o Apple Zdravlju, a sistemska dozvola traži se tek kad korisnik pristane.
struct OnboardingScreen: View {
    private enum Step {
        case profile, recommendation, health
    }

    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var answers = OnboardingAnswers()
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var step = Step.profile
    /// Korak prije zaslona o Zdravlju, za tipku Natrag.
    @State private var stepBeforeHealth = Step.profile
    /// "Preskoči": od odgovora se sprema samo onaj o Zdravlju.
    @State private var skipped = false
    /// Program odabran u prijedlogu; dodaje se tek na kraju, zajedno s odgovorima.
    @State private var chosenProgram: Program?
    /// Program koji ima manje dana od cilja, dok korisnik ne odgovori na upozorenje.
    @State private var pendingProgram: Program?
    @State private var isConnectingHealth = false
    @State private var errorText: String?

    private var profile: TrainingProfile { TrainingProfile(answers: answers) }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .profile: profilePage
                case .recommendation: recommendationPage
                case .health: healthPage
                }
            }
            .errorAlert($errorText)
        }
        .interactiveDismissDisabled()
    }

    private func go(to next: Step) {
        withAnimation(reduceMotion ? nil : .default) { step = next }
    }

    // MARK: Profil

    private var profilePage: some View {
        Form {
            Section {
                Text("Nekoliko pitanja za prijedlog treninga. Sve je neobavezno i možeš promijeniti u Postavkama.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            TrainingProfileSections(
                goal: $answers.goal, daysPerWeek: $answers.daysPerWeek,
                experience: $answers.experience, equipment: $answers.equipment
            )
            bodySection
        }
        .navigationTitle("Dobro došli")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Preskoči") { skipAll() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Spremi") { save() }
            }
        }
    }

    private var bodySection: some View {
        Section {
            Picker("Jedinice", selection: $answers.unit) {
                Text("Kilogrami (kg)").tag(WeightUnit.kilograms)
                Text("Funte (lbs)").tag(WeightUnit.pounds)
            }
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
            Picker("Spol", selection: $answers.sex) {
                Text("Bez odgovora").tag(Sex?.none)
                ForEach(Sex.allCases, id: \.self) { Text($0.title).tag(Sex?.some($0)) }
            }
        } header: {
            Text("Tijelo")
        } footer: {
            Text("Visina i težina služe za praćenje mjera tijela, a spol za DOTS bodove i tijelo na prikazu mišića.")
        }
    }

    // MARK: Prijedlog

    private var recommendationPage: some View {
        Form {
            Section {
                Text("Prema tvojim odgovorima. Treninge i raspored možeš poslije mijenjati, a svi programi su i u kartici Rasporedi.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ProgramRecommendationSections(profile: profile) { program in
                if profile.lowerDaysGoal(for: program) != nil {
                    pendingProgram = program
                } else {
                    choose(program, newDaysGoal: nil)
                }
            }
            Section {
                Button("Složit ću sam") { choose(nil, newDaysGoal: nil) }
            }
        }
        .daysGoalWarning(profile: profile, program: $pendingProgram) { program, days in choose(program, newDaysGoal: days) }
        .navigationTitle("Prijedlog rasporeda")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Natrag") { go(to: .profile) }
            }
        }
    }

    // MARK: Apple Zdravlje

    /// Zaseban zaslon s izričitim pristankom ili odbijanjem. Objašnjenje je ispred sistemskog lista s dozvolama.
    private var healthPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Apple Zdravlje")
                    .font(.screenTitle)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 14) {
                    Label("Treninzi se spremaju u Zdravlje i ulaze u Activity prstenove.", systemImage: "figure.strengthtraining.traditional")
                    Label("Kardio treninzi iz drugih aplikacija i sa sata dolaze u povijest.", systemImage: "figure.run")
                    Label("Težina i visina uvoze se iz Zdravlja.", systemImage: "scalemass")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Aplikacija radi i bez toga. Odluku možeš promijeniti u Postavkama > Zdravlje.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    connectHealth()
                } label: {
                    Text("Poveži s Apple Zdravljem").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Ne sada") { complete(wantsHealthKit: false) }
                    .controlSize(.large)
            }
            .disabled(isConnectingHealth)
            .frame(maxWidth: 560)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Natrag") {
                    skipped = false
                    go(to: stepBeforeHealth)
                }
                .disabled(isConnectingHealth)
            }
        }
    }

    // MARK: Spremanje

    private func save() {
        answers.heightCm = NumberInput.parse(heightText)
        answers.weight = NumberInput.parse(weightText)
        // Prijedlog samo kad ima na temelju čega: inače odmah dalje na Zdravlje.
        if profile.hasAnswers {
            go(to: .recommendation)
        } else {
            askHealth(from: .profile)
        }
    }

    private func skipAll() {
        skipped = true
        askHealth(from: .profile)
    }

    /// Odabir u prijedlogu. Novi cilj dana tjedno kad je korisnik u upozorenju pristao smanjiti ga.
    private func choose(_ program: Program?, newDaysGoal: Int?) {
        chosenProgram = program
        if let newDaysGoal { answers.daysPerWeek = newDaysGoal }
        askHealth(from: .recommendation)
    }

    /// Zaslon o Zdravlju, ako je Zdravlje dostupno na uređaju; inače onboarding odmah završava.
    private func askHealth(from previous: Step) {
        guard HealthService.shared.isAvailable else {
            complete(wantsHealthKit: false)
            return
        }
        stepBeforeHealth = previous
        go(to: .health)
    }

    private func connectHealth() {
        isConnectingHealth = true
        Task {
            await HealthService.shared.requestAuthorization()
            isConnectingHealth = false
            complete(wantsHealthKit: true)
        }
    }

    /// Sprema odgovore (onboarding je time obavljen i zaslon se zatvara) i po želji dodaje program.
    private func complete(wantsHealthKit: Bool) {
        do {
            let applier = OnboardingApplier(context: context)
            if skipped {
                try applier.skip(wantsHealthKit: wantsHealthKit)
            } else {
                answers.wantsHealthKit = wantsHealthKit
                try applier.apply(answers)
                if let chosenProgram {
                    try ProgramAdder.add(chosenProgram, profile: profile, context: context, catalogStore: catalogStore)
                }
            }
            if wantsHealthKit {
                Task { await HealthService.shared.importNewData(context: context) }
            }
        } catch {
            errorText = String(localized: "Odgovori se nisu mogli spremiti.")
        }
    }
}
