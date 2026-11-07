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
/// kasnije upisati u Postavkama > Profil. Nakon spremanja, ako je korisnik odgovorio o treningu, nudi se
/// gotov raspored prema cilju, danima, iskustvu i opremi.
struct OnboardingScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var answers = OnboardingAnswers()
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var showsRecommendation = false
    @State private var errorText: String?

    private var profile: TrainingProfile { TrainingProfile(answers: answers) }

    var body: some View {
        NavigationStack {
            Group {
                if showsRecommendation {
                    recommendationPage
                } else {
                    profilePage
                }
            }
            .errorAlert($errorText)
        }
        .interactiveDismissDisabled()
    }

    // MARK: Profil

    private var profilePage: some View {
        Form {
            Section {
                Text("Nekoliko pitanja za prijedlog treninga. Sve je neobavezno i možeš promijeniti u Postavkama > Profil.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            TrainingProfileSections(
                goal: $answers.goal, daysPerWeek: $answers.daysPerWeek,
                experience: $answers.experience, equipment: $answers.equipment
            )
            bodySection
            healthSection
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

    private var healthSection: some View {
        Section {
            Toggle("Poveži s Apple Zdravljem", isOn: Binding(
                get: { answers.wantsHealthKit },
                set: { isOn in
                    answers.wantsHealthKit = isOn
                    // Sistemski list s dozvolama odmah, dok je objašnjenje na zaslonu.
                    if isOn { Task { await HealthService.shared.requestAuthorization() } }
                }
            ))
        } footer: {
            Text("Treninzi se spremaju u Zdravlje i ulaze u Activity prstenove, a kardio treninzi, težina i visina dolaze iz njega. Aplikacija radi i bez toga.")
        }
    }

    // MARK: Prijedlog

    private var recommendationPage: some View {
        Form {
            Section {
                Text("Prema tvojim odgovorima. Treninge i raspored možeš poslije mijenjati, a svi programi su i u kartici Rasporedi.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ProgramRecommendationSections(profile: profile) { program in finish(adding: program) }
            Section {
                Button("Složit ću sam") { finish(adding: nil) }
            }
        }
        .navigationTitle("Prijedlog rasporeda")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Natrag") { withAnimation(reduceMotion ? nil : .default) { showsRecommendation = false } }
            }
        }
    }

    // MARK: Spremanje

    private func save() {
        answers.heightCm = NumberInput.parse(heightText)
        answers.weight = NumberInput.parse(weightText)
        // Prijedlog samo kad ima na temelju čega: inače se odmah sprema i onboarding završava.
        if profile.hasAnswers {
            withAnimation(reduceMotion ? nil : .default) { showsRecommendation = true }
        } else {
            finish(adding: nil)
        }
    }

    /// Sprema odgovore (onboarding je time obavljen i zaslon se zatvara) i po želji dodaje program.
    private func finish(adding program: Program?) {
        do {
            try OnboardingApplier(context: context).apply(answers)
            if let program {
                try ProgramAdder.add(program, profile: profile, context: context, catalogStore: catalogStore)
            }
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
