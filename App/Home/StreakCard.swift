import Models
import Stats
import SwiftData
import SwiftUI

// MARK: - Streak

/// Streak: uzastopni tjedni s ispunjenim tjednim ciljem, treninzi ovog tjedna prema cilju i koliko ih još
/// treba do kraja tjedna da se niz ne izgubi (`StreakStatus`). Dodir otvara Pregled na tekućem tjednu.
struct StreakCard: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]
    @State private var status: StreakStatus?

    private var goal: Int? { UserSettings.preferred(in: settingsList)?.trainingDaysPerWeek }

    var body: some View {
        DetailLink(value: CardDestination.overview(.week)) {
            HomeCard(title: DashboardCardKind.streak.title, symbol: DashboardCardKind.streak.symbol) {
                if let status {
                    StreakContent(status: status)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: RefreshKey(version: DataVersion.shared.value, goal: goal, day: Calendar.current.startOfDay(for: .now))) {
            load()
        }
    }

    private struct RefreshKey: Equatable {
        /// Izmjena podataka (`DataVersion`): trening završen, uređen, obrisan ili stigao iz Zdravlja ili s iClouda.
        let version: Int
        let goal: Int?
        /// Novi dan mijenja broj preostalih dana, a novi tjedan i sam niz.
        let day: Date
    }

    private func load() {
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        let now = Date.now
        guard let progress = try? StatisticsEngine(context: context)
            .weekProgress(now: now, goal: goal, isCardio: ExerciseInfoBuilder.isCardio(info)) else { return }
        status = StreakStatus(progress: progress, now: now)
    }
}

/// Sadržaj kartice: plamen s brojem tjedana, poruka prema stanju tjedna i točke treninga do cilja.
private struct StreakContent: View {
    let status: StreakStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.weeks > 0 ? "flame.fill" : "flame")
                .font(.largeTitle)
                .foregroundStyle(status.weeks > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .symbolEffect(.bounce, value: status.weeks)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                headline
                    .font(.cardTitle)
                    .foregroundStyle(.primary)
                message
                    .font(.subheadline)
                    .foregroundStyle(status.state == .atRisk ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        if status.state != .secured {
            progressRow
        }
    }

    @ViewBuilder
    private var headline: some View {
        if status.weeks > 0 {
            Text("\(status.weeks) tjedana zaredom")
        } else {
            Text("Započni streak")
        }
    }

    @ViewBuilder
    private var message: some View {
        switch status.state {
        case .secured:
            Text("Cilj ovog tjedna je ispunjen, streak je siguran.")
        case .atRisk:
            Text("Još \(status.remaining) treninga do kraja tjedna ili gubiš streak.")
        case .canGrow:
            Text("Još \(status.remaining) treninga do kraja tjedna i streak raste.")
        case .notStarted:
            Text("Ispuni tjedni cilj i započni streak.")
        }
    }

    /// Točka za svaki trening cilja (ispunjena za odrađeni), "2 od 3" i dani do kraja tjedna.
    private var progressRow: some View {
        HStack(spacing: 6) {
            if status.target <= 7 {
                ForEach(0..<status.target, id: \.self) { index in
                    Circle()
                        .fill(index < status.sessions ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 10, height: 10)
                }
                .accessibilityHidden(true)
            }
            Text("\(status.sessions) od \(status.target)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            daysLeft
                .font(.subheadline)
                .foregroundStyle(status.isLastChance ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var daysLeft: some View {
        if status.daysLeft <= 1 {
            Text("Zadnji dan tjedna")
        } else {
            Text("Još \(status.daysLeft) dana")
        }
    }
}
