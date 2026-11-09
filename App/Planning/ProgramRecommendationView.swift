import Catalog
import Models
import Planning
import SwiftData
import SwiftUI

extension RecommendationReason {
    var text: String {
        switch self {
        case .days(let days): String(localized: "\(days) dana tjedno")
        case .goal(let goal): String(localized: goal.reasonText)
        case .level(let level): String(localized: level.reasonText)
        case .equipment: String(localized: "samo vježbe za tvoju opremu")
        }
    }
}

private extension TrainingGoal {
    var reasonText: LocalizedStringResource {
        switch self {
        case .hypertrophy: "ponavljanja za rast mišića"
        case .strength: "teže serije za snagu"
        case .recomposition: "ponavljanja za rekompoziciju"
        case .generalFitness: "lakši obim za opću kondiciju"
        }
    }
}

private extension ExperienceLevel {
    var reasonText: LocalizedStringResource {
        switch self {
        case .beginner: "za početnike"
        case .intermediate: "za srednju razinu"
        case .advanced: "za napredne"
        }
    }
}

/// Dodaje gotov program s nazivima na jeziku sučelja. Ponavljanja prema cilju i iskustvu, vježbe prema opremi.
@MainActor
enum ProgramAdder {
    @discardableResult
    static func add(
        _ program: Program, profile: TrainingProfile, context: ModelContext, catalogStore: CatalogStore
    ) throws -> Schedule {
        let schedule = try ProgramInstaller(context: context).install(
            program, profile: profile, name: program.title, workoutName: \.title
        ) { id in
            catalogStore.catalog?.exercise(withID: id)?.displayName(language: catalogStore.language) ?? id
        }
        ReminderScheduler.refresh(context: context)
        return schedule
    }
}

/// Preporučeni programi za profil: najbolji i dvije alternative, svaki s razlozima i tipkom za dodavanje.
struct ProgramRecommendationSections: View {
    let profile: TrainingProfile
    /// Poziva se s odabranim programom.
    let onAdd: (Program) -> Void

    private var recommendations: [ProgramRecommendation] { ProgramRecommender.recommend(for: profile) }

    var body: some View {
        ForEach(Array(recommendations.enumerated()), id: \.element.program.id) { index, item in
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.program.title).font(.itemTitle)
                    Text(item.program.details).font(.subheadline).foregroundStyle(.secondary)
                    if !item.reasons.isEmpty {
                        Text(item.reasons.map(\.text).formatted(.list(type: .and)))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if index == 0 {
                    Button("Dodaj i aktiviraj") { onAdd(item.program) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Dodaj i aktiviraj") { onAdd(item.program) }
                }
            } header: {
                index == 0 ? Text("Preporučeno") : Text("Druga opcija")
            }
        }
    }
}

extension View {
    /// Upozorenje kad odabrani program ima manje dana treninga od cilja dana tjedno, s ponudom da se cilj
    /// smanji. `onAdd` dobiva program i novi cilj (nil kad korisnik zadrži stari).
    func daysGoalWarning(
        profile: TrainingProfile, program: Binding<Program?>, onAdd: @escaping (Program, Int?) -> Void
    ) -> some View {
        alert(
            "Raspored ima manje dana od cilja",
            isPresented: Binding(get: { program.wrappedValue != nil }, set: { if !$0 { program.wrappedValue = nil } }),
            presenting: program.wrappedValue
        ) { item in
            let days = profile.lowerDaysGoal(for: item) ?? item.daysPerWeek
            let goal = profile.daysPerWeek ?? days
            Button("Smanji na \(days) dana") { onAdd(item, days) }
            Button("Zadrži \(goal) dana") { onAdd(item, nil) }
            Button("Odustani", role: .cancel) {}
        } message: { item in
            let days = profile.lowerDaysGoal(for: item) ?? item.daysPerWeek
            let goal = profile.daysPerWeek ?? days
            Text(
                "Raspored ima \(days) dana treninga tjedno, a cilj ti je \(goal). Možeš smanjiti cilj ili ga zadržati i dodatni trening ili kardio odraditi sam."
            )
        }
    }
}

/// Postavke > Profil > Predloži raspored.
struct ProgramRecommendationScreen: View {
    let settings: UserSettings
    /// Profil u trenutku otvaranja, da se popis ne mijenja kad se smanji cilj.
    let profile: TrainingProfile

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.modelContext) private var context
    @State private var added: String?
    @State private var pendingProgram: Program?
    @State private var errorText: String?

    init(settings: UserSettings) {
        self.settings = settings
        profile = TrainingProfile(settings: settings)
    }

    var body: some View {
        Form {
            ProgramRecommendationSections(profile: profile) { program in
                if profile.lowerDaysGoal(for: program) != nil {
                    pendingProgram = program
                } else {
                    add(program, newDaysGoal: nil)
                }
            }
        }
        .daysGoalWarning(profile: profile, program: $pendingProgram) { program, days in
            // Potvrda o dodavanju je drugo upozorenje: čeka da se prvo zatvori, inače se ne prikaže.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                add(program, newDaysGoal: days)
            }
        }
        .navigationTitle("Prijedlog rasporeda")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Program je dodan", isPresented: Binding(get: { added != nil }, set: { if !$0 { added = nil } })) {
            Button("U redu") {}
        } message: {
            Text("Raspored \(added ?? "") nalazi se u kartici Rasporedi, a ciljeve u treningu možeš prilagoditi.")
        }
        .errorAlert($errorText)
    }

    private func add(_ program: Program, newDaysGoal: Int?) {
        do {
            if let newDaysGoal { settings.trainingDaysPerWeek = newDaysGoal }
            added = try ProgramAdder.add(program, profile: profile, context: context, catalogStore: catalogStore).name
        } catch {
            errorText = String(localized: "Program se nije mogao dodati.")
        }
    }
}
