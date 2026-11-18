import Catalog
import Foundation
import Models
import SwiftData
import Training

/// Sve što ekran Statistika prikazuje, izračunato odjednom. Aplikacija je slaže u pozadini (zasebni
/// `ModelContext`, ne glavna nit) čim se pokrene i nakon svake izmjene podataka, pa je tab spreman
/// prije nego što ga korisnik otvori.
public struct StatisticsSnapshot: Equatable, Sendable {
    /// Završeni treninzi i treninzi iz Zdravlja.
    public var sessionCount = 0
    /// Jesu li izračunate kartice detaljnog prikaza (`StatsDetail.pro`).
    public var isPro = false
    public var week: WeekProgress?
    public var month: PeriodSummary?
    public var year: PeriodSummary?
    public var frequency: [FrequencyPoint] = []
    public var records: [RecordEntry] = []
    public var trends: [StrengthTrend] = []
    public var review: WeeklyReview?
    public var suggestions: [Suggestion] = []
    public var effort = EffortDistribution()
    public var intensity = IntensityDistribution()
    public var dots: DotsScore?
    /// Razdoblje kartice Mišići u danima, za koje je izračunat `heatmap`.
    public var muscleDays: Int
    public var heatmap: [String: RegionLoad] = [:]

    public init(muscleDays: Int) {
        self.muscleDays = muscleDays
    }
}

/// Postavke koje mijenjaju statistiku, kao vrijednost. Aplikacija ih čita na glavnoj niti i predaje
/// pozadinskom izračunu: nespremljena promjena postavki inače još nije vidljiva drugom kontekstu.
public struct StatisticsSettings: Equatable, Sendable {
    public var goal: TrainingGoal?
    public var plannedPerWeek: Int?
    public var sex: Sex?
    public var isPro: Bool
    public var trackedKinds: Set<PRKind>
    public var excludedExercises: Set<String>

    public init(_ settings: UserSettings?) {
        goal = settings?.goal
        plannedPerWeek = settings?.trainingDaysPerWeek
        sex = settings?.sex
        isPro = settings?.statsDetail == .pro
        trackedKinds = PRKind.tracked(by: settings)
        excludedExercises = settings?.prExcludedExerciseKeys ?? []
    }
}

/// Slaže `StatisticsSnapshot` iz baze. Vlastite vježbe čita iz istog konteksta,
/// pa radi i u pozadinskom kontekstu bez ičega s glavne niti.
public enum StatisticsSnapshotBuilder {
    /// Kartica Napor i intenzitet gleda zadnja četiri tjedna.
    static let effortWindow: TimeInterval = 28 * 24 * 3600

    public static func make(
        context: ModelContext, catalog: ExerciseCatalog?, settings: StatisticsSettings, muscleDays: Int,
        now: Date = Date(), calendar: Calendar = .current
    ) -> StatisticsSnapshot {
        var snapshot = StatisticsSnapshot(muscleDays: muscleDays)
        let info = infoProvider(context: context, catalog: catalog)
        let engine = StatisticsEngine(context: context)
        let end = now.addingTimeInterval(1)
        let isCardio = ExerciseInfoBuilder.isCardio(info)
        let goal = settings.plannedPerWeek

        // Kardio iz Zdravlja (lokalna baza) broji se u učestalost treninga.
        let finished = FetchDescriptor<Session>(predicate: #Predicate { $0.stateRaw == "finished" })
        snapshot.sessionCount = ((try? context.fetchCount(finished)) ?? 0)
            + ((try? context.fetchCount(FetchDescriptor<HealthWorkout>())) ?? 0)
        snapshot.week = try? engine.weekProgress(now: now, goal: goal, calendar: calendar, isCardio: isCardio)
        snapshot.month = try? engine.periodSummary(
            .month, containing: now, now: now, goal: goal, calendar: calendar, isCardio: isCardio
        )
        snapshot.year = try? engine.periodSummary(
            .year, containing: now, now: now, goal: goal, calendar: calendar, isCardio: isCardio
        )
        snapshot.frequency = (try? engine.frequency(weeks: 12, endingAt: now, calendar: calendar)) ?? []
        snapshot.records = (try? engine.personalRecords(
            kinds: settings.trackedKinds, excluding: settings.excludedExercises
        )) ?? []

        // Ostale kartice su samo u detaljnom prikazu, pa se u osnovnom ne računaju.
        guard settings.isPro else { return snapshot }
        snapshot.isPro = true
        snapshot.heatmap = heatmap(engine: engine, info: info, days: muscleDays, now: now)
        snapshot.trends = (try? engine.strengthTrends(weeks: 4, endingAt: end, info: info)) ?? []
        let weekly = try? engine.weeklyReview(
            endingAt: now, goal: settings.goal, plannedPerWeek: goal, info: info
        )
        snapshot.review = weekly?.review
        snapshot.suggestions = weekly?.suggestions ?? []
        let monthStart = now.addingTimeInterval(-effortWindow)
        snapshot.effort = (try? engine.effortDistribution(from: monthStart, until: end)) ?? EffortDistribution()
        snapshot.intensity = (try? engine.intensityDistribution(from: monthStart, until: end)) ?? IntensityDistribution()
        // DOTS uz spol i zadnju upisanu tjelesnu težinu.
        if let sex = settings.sex,
           let bodyWeight = (try? BodyTracking(context: context).latest(of: .weight))?.value, bodyWeight > 0 {
            snapshot.dots = try? engine.dotsScore(bodyWeightKg: bodyWeight, sex: sex, endingAt: end)
        }
        return snapshot
    }

    /// Samo kartica Mišići, kad korisnik promijeni njeno razdoblje.
    public static func heatmap(
        context: ModelContext, catalog: ExerciseCatalog?, days: Int, now: Date = Date()
    ) -> [String: RegionLoad] {
        heatmap(
            engine: StatisticsEngine(context: context), info: infoProvider(context: context, catalog: catalog),
            days: days, now: now
        )
    }

    private static func heatmap(
        engine: StatisticsEngine, info: ExerciseInfoProvider, days: Int, now: Date
    ) -> [String: RegionLoad] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return (try? engine.heatmap(from: start, until: now.addingTimeInterval(1), info: info)) ?? [:]
    }

    private static func infoProvider(context: ModelContext, catalog: ExerciseCatalog?) -> ExerciseInfoProvider {
        let custom = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        return ExerciseInfoBuilder.provider(catalog: catalog, custom: custom)
    }
}
