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

/// Postavke > Profil > Predloži raspored.
struct ProgramRecommendationScreen: View {
    let profile: TrainingProfile

    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.modelContext) private var context
    @State private var added: String?
    @State private var errorText: String?

    var body: some View {
        Form {
            ProgramRecommendationSections(profile: profile) { program in
                do {
                    added = try ProgramAdder.add(program, profile: profile, context: context, catalogStore: catalogStore).name
                } catch {
                    errorText = String(localized: "Program se nije mogao dodati.")
                }
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
}
