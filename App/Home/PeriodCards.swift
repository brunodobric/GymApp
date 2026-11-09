import Charts
import Models
import Stats
import SwiftData
import SwiftUI
import Training

/// Sedam dana tjedna: odrađen dan je pun krug s ikonom vrste, danas je obrubljen.
/// Dijele ga kartica Ovaj tjedan na Početnoj i kartica Pregled u Statistici.
struct WeekDaysStrip: View {
    let progress: WeekProgress

    var body: some View {
        HStack(spacing: 0) {
            ForEach(progress.days, id: \.date) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(day.isTrained ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)))
                        if isToday && !day.isTrained {
                            Circle().strokeBorder(.tint, lineWidth: 2)
                        }
                        if let mix = day.mix {
                            WorkoutKindIcon(mix: mix)
                                .font(.footnote.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 32, height: 32)
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.caption)
                        .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dayLabel(day))
            }
        }
    }

    private func dayLabel(_ day: WeekProgress.Day) -> Text {
        let name = Text(day.date, format: .dateTime.weekday(.wide))
        guard let mix = day.mix else { return Text("\(name): bez treninga") }
        return Text("\(name): \(Text(mix.title))")
    }
}

/// Tvrde serije, kardio i ukupno vrijeme u malim pločicama; nula serija i kardija se ne prikazuje.
struct PeriodFigures: View {
    let hardSets: Int
    let cardioSeconds: Int
    let totalSeconds: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            if hardSets > 0 {
                figure(Text(hardSets, format: .number), label: "Tvrde serije")
            }
            if cardioSeconds >= 60 {
                figure(Text(WeekFormat.duration(Double(cardioSeconds))), label: "Kardio")
            }
            figure(Text(WeekFormat.duration(totalSeconds)), label: "Ukupno")
        }
    }

    private func figure(_ value: Text, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.rowValue)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: CornerRadius.inner))
        .accessibilityElement(children: .combine)
    }
}

enum PeriodText {
    /// Prosjek treninga tjedno, npr. "2,8 tjedno" ili s ciljem "2,8 od 4 tjedno".
    static func perWeek(_ summary: PeriodSummary) -> String {
        let value = summary.sessionsPerWeek.formatted(.number.precision(.fractionLength(0...1)))
        guard let goal = summary.weeklyGoal else { return String(localized: "\(value) tjedno") }
        return String(localized: "\(value) od \(goal) tjedno")
    }
}

// MARK: - Ovaj mjesec i Ova godina

/// Tekući mjesec ili godina na Početnoj: broj treninga, prosjek tjedno (uz cilj iz onboardinga), dani
/// mjeseca ili treninzi po mjesecima te tvrde serije, kardio i ukupno vrijeme. Dodir otvara Pregled na tom razdoblju.
struct PeriodCard: View {
    let period: OverviewPeriod

    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    /// Samo za osvježavanje kad se trening završi, obriše ili stigne iz Zdravlja.
    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }) private var sessions: [Session]
    @Query private var healthWorkouts: [HealthWorkout]
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]
    @State private var summary: PeriodSummary?

    private var goal: Int? { UserSettings.preferred(in: settingsList)?.trainingDaysPerWeek }
    private var kind: DashboardCardKind { period == .year ? .thisYear : .thisMonth }

    private struct RefreshKey: Equatable {
        let sessions: Int
        let health: Int
        let goal: Int?
        let day: Date
    }

    var body: some View {
        NavigationLink {
            OverviewScreen(period: period)
        } label: {
            HomeCard(title: kind.title, symbol: kind.symbol) {
                if let summary {
                    header(summary)
                    if period == .year {
                        YearMonthsBars(summary: summary)
                    } else {
                        MonthDaysStrip(days: summary.days)
                    }
                    if summary.sessions > 0 {
                        PeriodFigures(
                            hardSets: summary.hardSets, cardioSeconds: summary.cardioSeconds, totalSeconds: summary.totalSeconds
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: RefreshKey(sessions: sessions.count, health: healthWorkouts.count, goal: goal, day: Calendar.current.startOfDay(for: .now))) {
            load()
        }
    }

    /// "12 treninga" i prosjek tjedno.
    private func header(_ summary: PeriodSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(summary.sessions) treninga").font(.metric)
                Spacer(minLength: 8)
                Text(verbatim: PeriodText.perWeek(summary)).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(summary.sessions) treninga").font(.metric)
                Text(verbatim: PeriodText.perWeek(summary)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func load() {
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        summary = try? StatisticsEngine(context: context).periodSummary(
            period, containing: .now, goal: goal, isCardio: ExerciseInfoBuilder.isCardio(info)
        )
    }
}

/// Dani mjeseca u jednom redu: obojen je dan s treningom, a dani koji još nisu došli su prazni.
struct MonthDaysStrip: View {
    let days: [WeekProgress.Day]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(days, id: \.date) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(fill(day))
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Dana s treningom: \(days.filter(\.isTrained).count)"))
    }

    private func fill(_ day: WeekProgress.Day) -> AnyShapeStyle {
        if day.isTrained { return AnyShapeStyle(.tint) }
        if day.date > .now { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(Color(.tertiarySystemFill))
    }
}

/// Treninzi po mjesecima godine, mali stupci s početnim slovom mjeseca.
struct YearMonthsBars: View {
    let summary: PeriodSummary

    var body: some View {
        Chart(summary.months, id: \.start) { month in
            BarMark(
                x: .value("Mjesec", month.start, unit: .month),
                y: .value("Treninga", month.sessions)
            )
            .foregroundStyle(.tint)
        }
        .chartXAxis {
            AxisMarks(values: summary.months.map(\.start)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 64)
        .accessibilityLabel(Text("Graf treninga po mjesecima"))
    }
}
