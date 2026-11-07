import Catalog
import Foundation
import Models
import SwiftData
import Testing
import Training
@testable import Stats

private let press = ExerciseRef(catalogId: "press", name: "Potisak")
private let curl = ExerciseRef(catalogId: "curl", name: "Pregib")
/// Petak 15. 1. 2027., 08:00 UTC.
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private let info: ExerciseInfoProvider = { key in
    switch key {
    case "c:press": ExerciseInfo(primary: [.chest], primaryRegions: ["chest"], isCompound: true)
    case "c:curl": ExerciseInfo(primary: [.biceps], primaryRegions: ["biceps"], isCompound: false)
    default: nil
    }
}

/// Završen trening s jednom vježbom; serije su (težina, ponavljanja, RPE), označene minutu jedna za drugom.
@discardableResult
private func addSession(
    _ context: ModelContext, ref: ExerciseRef = press, daysAgo: Double, sets: [(Double, Int, Double?)],
    templateId: UUID? = nil, restSeconds: TimeInterval = 120
) throws -> Session {
    let date = now.addingTimeInterval(-daysAgo * day)
    let session = Session(name: "Trening", startedAt: date)
    session.state = .finished
    session.endedAt = date.addingTimeInterval(3600)
    session.templateId = templateId
    context.insert(session)
    let exercise = SessionExercise(orderIndex: 0, exercise: ref, inputType: .weightReps)
    context.insert(exercise)
    exercise.session = session
    for (index, values) in sets.enumerated() {
        let set = SetLog(orderIndex: index, kind: .working)
        set.weightKg = values.0
        set.reps = values.1
        set.rpe = values.2
        set.completedAt = date.addingTimeInterval(600 + Double(index) * restSeconds)
        context.insert(set)
        set.exercise = exercise
    }
    try context.save()
    return session
}

private func trend(_ values: [Double], days: [Double], noise: Double = 0.03) -> ExerciseTrend {
    let points = zip(values, days).map { TrendPoint(date: now.addingTimeInterval(-$1 * day), value: $0) }
    return TrendAnalysis.trend(of: points, endingAt: now, defaultNoise: noise)
}

@Suite("Trend napretka")
struct TrendAnalysisTests {

    @Test("Theil–Sen nagib i medijan")
    func slope() throws {
        #expect(TrendAnalysis.median([3, 1, 2]) == 2)
        #expect(TrendAnalysis.median([4, 1, 2, 3]) == 2.5)
        #expect(TrendAnalysis.median([]) == nil)
        // Jedna iznimna točka ne mijenja nagib.
        let slope = try #require(TrendAnalysis.theilSenSlope([(0, 0), (1, 1), (2, 2), (3, 30), (4, 4)]))
        #expect(abs(slope - 1) < 1e-9)
        #expect(TrendAnalysis.theilSenSlope([(1, 1), (1, 2)]) == nil)
    }

    @Test("Napreduje, pada, stoji i plato")
    func statuses() {
        #expect(trend([100, 103, 106, 109], days: [42, 28, 14, 1]).status == .improving)
        #expect(trend([109, 106, 103, 100], days: [42, 28, 14, 1]).status == .declining)
        // Bez promjene tri tjedna: stoji; pet tjedana: plato.
        #expect(trend([100, 100.5, 100, 100.5], days: [21, 14, 7, 1]).status == .stable)
        #expect(trend([100, 100.5, 100, 100.5], days: [35, 21, 7, 1]).status == .plateau)
    }

    @Test("Premalo izvođenja ili izvan razdoblja: nema statusa")
    func insufficient() {
        #expect(trend([100, 105, 110], days: [21, 14, 7]).status == .insufficientData)
        #expect(trend([100, 105, 110, 115], days: [90, 80, 70, 7]).status == .insufficientData)
    }

    @Test("Mjesečna promjena je relativna, pa su +5 kg na mrtvom i na pregibu različiti napredak")
    func relativeChange() throws {
        let deadlift = try #require(trend([200, 202.5, 205, 207.5], days: [42, 28, 14, 0]).monthlyChange)
        let curls = try #require(trend([20, 22.5, 25, 27.5], days: [42, 28, 14, 0]).monthlyChange)
        #expect(deadlift > 0.02 && deadlift < 0.03)
        #expect(curls > 0.2)
    }

    @Test("Kolebanje se uči iz podataka od šest izvođenja, unutar granica")
    func learnedNoise() {
        let noisy = trend([100, 110, 95, 112, 96, 111], days: [50, 40, 30, 20, 10, 1])
        #expect(noisy.noise > 0.03 && noisy.noise <= TrendAnalysis.noiseRange.upperBound)
        #expect(noisy.status == .stable || noisy.status == .plateau)
        let smooth = trend([100, 100, 100, 100, 100, 100], days: [50, 40, 30, 20, 10, 1])
        #expect(smooth.noise == TrendAnalysis.noiseRange.lowerBound)
    }

    @Test("Točke za trend: procjena 1RM, a bez tereta ponavljanja")
    func points() throws {
        let strength = [ExercisePoint(date: now, bestWeightKg: 100, bestReps: 5, estimatedOneRepMaxKg: 116, volumeKg: 500)]
        #expect(TrendAnalysis.points(from: strength)?.measure == .oneRepMax)
        let bodyweight = [ExercisePoint(date: now, bestWeightKg: 0, bestReps: 12, estimatedOneRepMaxKg: nil, volumeKg: 0)]
        let reps = try #require(TrendAnalysis.points(from: bodyweight))
        #expect(reps.measure == .reps && reps.points.first?.value == 12)
        let tooMany = [ExercisePoint(date: now, bestWeightKg: 50, bestReps: 20, estimatedOneRepMaxKg: nil, volumeKg: 1000)]
        #expect(TrendAnalysis.points(from: tooMany) == nil)
    }
}

@Suite("Tjedni pregled i prijedlozi")
struct WeeklyReviewTests {

    private func entry(_ name: String, _ status: ExerciseStatus, region: String = "chest") -> ExerciseTrendEntry {
        ExerciseTrendEntry(
            key: "c:\(name)", name: name, measure: .oneRepMax,
            trend: ExerciseTrend(status: status, monthlyChange: 0.01, noise: 0.03, sessions: 4, latest: 100),
            primaryRegions: [region]
        )
    }

    @Test("Snaga: napreduje ili stoji je dobro, plato i pad nisu")
    func strength() {
        let good = WeeklyReviewBuilder.strength([entry("a", .improving), entry("b", .stable), entry("c", .improving), entry("d", .plateau)])
        #expect(good.level == .good && good.improving == 2 && good.plateau == 1)
        #expect(WeeklyReviewBuilder.strength([entry("a", .declining), entry("b", .plateau)]).level == .attention)
        #expect(WeeklyReviewBuilder.strength([entry("a", .insufficientData)]).level == .noData)
    }

    @Test("Volumen prema cilju: zona za rast je 10 do 20 serija, za snagu dovoljno manje")
    func volume() {
        let sets = Dictionary(uniqueKeysWithValues: BodyRegion.major.map { ($0, 6.0) })
        #expect(WeeklyReviewBuilder.volume(weeklySets: sets, goal: .hypertrophy).level == .attention)
        #expect(WeeklyReviewBuilder.volume(weeklySets: sets, goal: .strength).level == .good)
        #expect(WeeklyReviewBuilder.volume(weeklySets: [:], goal: nil).level == .noData)
    }

    @Test("Redovitost prema planu iz onboardinga ili prema broju treninga tjedno")
    func consistency() {
        #expect(WeeklyReviewBuilder.consistency(sessions: 11, weeks: 4, plannedPerWeek: 3).level == .good)
        #expect(WeeklyReviewBuilder.consistency(sessions: 6, weeks: 4, plannedPerWeek: 3).level == .attention)
        #expect(WeeklyReviewBuilder.consistency(sessions: 8, weeks: 4, plannedPerWeek: nil).level == .good)
        #expect(WeeklyReviewBuilder.consistency(sessions: 4, weeks: 4, plannedPerWeek: nil).level == .fair)
    }

    @Test("Napor: udio serija s RIR 0 do 3, tek s dovoljno ocijenjenih serija")
    func effort() {
        #expect(WeeklyReviewBuilder.effort(rpes: [8, 9]).level == .noData)
        let hard = WeeklyReviewBuilder.effort(rpes: Array(repeating: 8, count: 8) + [5, 6])
        #expect(hard.level == .good && hard.closeToFailureShare == 0.8)
    }

    @Test("Prijedlozi: lakši tjedan, manje dana, serije za mišić na platou, veća težina i mišić koji je izostao")
    func suggestions() {
        let consistency = WeeklyReviewBuilder.consistency(sessions: 4, weeks: 4, plannedPerWeek: 3)
        let input = SuggestionInput(
            trends: [entry("Potisak", .plateau), entry("Čučanj", .declining, region: "quads"), entry("Veslanje", .declining, region: "lats")],
            weeklySets: ["chest": 6, "quads": 12],
            lastTrained: ["biceps": now.addingTimeInterval(-20 * day), "chest": now.addingTimeInterval(-2 * day)],
            consistency: consistency, goal: .hypertrophy, easyExercises: ["Pregib"], now: now
        )
        let result = SuggestionEngine.suggestions(input)
        #expect(result.first == .deload(exercises: 2))
        #expect(result.contains(.fewerDays(sessionsPerWeek: 1, planned: 12)))
        #expect(result.contains(.addSets(region: "chest", exerciseName: "Potisak")))
        #expect(result.contains(.increaseLoad(exerciseName: "Pregib")))
        #expect(result.contains(.missedMuscle(region: "biceps", days: 20)))
        #expect(!result.contains(.missedMuscle(region: "chest", days: 2)))
    }

    @Test("Pregled iz baze: trend, volumen, redovitost i lagane vježbe")
    func fromDatabase() throws {
        let context = try makeContext()
        for (index, weight) in [60.0, 62.5, 65, 67.5].enumerated() {
            try addSession(context, daysAgo: Double(21 - index * 7), sets: [(weight, 5, 8), (weight, 5, 8), (weight, 5, 9)])
        }
        for daysAgo in [15.0, 8, 1] {
            try addSession(context, ref: curl, daysAgo: daysAgo, sets: [(12, 10, 5), (12, 10, 6)])
        }
        let engine = StatisticsEngine(context: context)
        let (review, suggestions) = try engine.weeklyReview(endingAt: now, goal: .hypertrophy, plannedPerWeek: 2, info: info)
        #expect(review.strength.improving == 1)
        #expect(review.consistency.sessions == 7)
        #expect(review.effort.ratedSets == 18)
        #expect(suggestions.contains(.increaseLoad(exerciseName: "Pregib")))
        #expect(try engine.easyExercises(endingAt: now) == ["Pregib"])
    }
}

@Suite("Sažetak odrađenog treninga")
struct SessionComparisonTests {

    @Test("Usporedba s prošlim izvođenjem istog treninga")
    func comparison() throws {
        let context = try makeContext()
        let template = UUID()
        try addSession(context, daysAgo: 7, sets: [(80, 8, nil), (80, 8, nil)], templateId: template)
        try addSession(context, daysAgo: 3, sets: [(100, 1, nil)])
        let current = try addSession(context, daysAgo: 0, sets: [(82.5, 8, nil), (82.5, 8, nil), (82.5, 6, 5)], templateId: template)
        let engine = StatisticsEngine(context: context)
        let comparison = try #require(try engine.comparison(of: current))
        #expect(comparison.previousDate == now.addingTimeInterval(-7 * day))
        #expect(comparison.hardSets == 2 && comparison.previousHardSets == 2)
        #expect(comparison.volumeKg == 82.5 * 22 && comparison.previousVolumeKg == 1280)
        #expect(try engine.comparison(of: try addSession(context, daysAgo: 0, sets: [(50, 5, nil)])) == nil)
    }

    @Test("Rezultat vježbe: najbolja serija, procjena 1RM, promjena i odmor")
    func exerciseResults() throws {
        let context = try makeContext()
        try addSession(context, daysAgo: 7, sets: [(80, 8, nil)])
        let current = try addSession(context, daysAgo: 0, sets: [(85, 8, nil), (60, 20, nil)], restSeconds: 150)
        let results = try StatisticsEngine(context: context).exerciseResults(of: current)
        let result = try #require(results.first)
        #expect(result.bestSet?.weightKg == 85)
        #expect(abs((result.change ?? 0) - (85.0 / 80 - 1)) < 1e-9)
        #expect(result.restSeconds == 150)
        #expect(result.hardSets == 2)
    }

    @Test("Odmor: medijan razmaka, bez dugih stanki")
    func medianRest() {
        let times = [0.0, 90, 210, 330, 3000].map { now.addingTimeInterval($0) }
        #expect(SessionMetrics.medianRest(times) == 120)
        #expect(SessionMetrics.medianRest([now]) == nil)
    }
}

@Suite("Detaljna statistika")
struct ProStatisticsTests {

    @Test("Tablica rekorda po ponavljanjima")
    func repMaxTable() throws {
        let context = try makeContext()
        try addSession(context, daysAgo: 7, sets: [(100, 5, nil), (80, 10, nil)])
        try addSession(context, daysAgo: 1, sets: [(110, 1, nil), (90, 8, nil)])
        let table = try StatisticsEngine(context: context).repMaxTable(of: press)
        #expect(table.map(\.reps) == [1, 3, 5, 8, 10])
        #expect(table.map(\.weightKg) == [110, 100, 100, 90, 80])
    }

    @Test("Napor po RIR-u i intenzitet prema najboljoj procjeni 1RM")
    func distributions() throws {
        let context = try makeContext()
        try addSession(context, daysAgo: 2, sets: [(100, 5, 10), (90, 5, 8), (50, 10, 4), (65, 5, nil)])
        let engine = StatisticsEngine(context: context)
        let effort = try engine.effortDistribution(from: now.addingTimeInterval(-7 * day), until: now)
        #expect(effort.counts == [1, 0, 1, 0, 1] && effort.unrated == 1)
        // Najbolja procjena: 100 × 5 do otkaza = 116,7 kg.
        let intensity = try engine.intensityDistribution(from: now.addingTimeInterval(-7 * day), until: now)
        // 50 i 65 kg ispod 60 %, 90 kg 77 %, 100 kg 86 %.
        #expect(intensity.counts == [2, 0, 1, 1])
        #expect(IntensityDistribution.zone(of: 0.9) == 3)
    }
}

@Suite("DOTS")
struct DotsTests {
    @Test("Formula daje poznate vrijednosti za muškarce i žene")
    func formula() throws {
        let male = try #require(Dots.points(totalKg: 600, bodyWeightKg: 100, sex: .male))
        let female = try #require(Dots.points(totalKg: 300, bodyWeightKg: 60, sex: .female))
        #expect(abs(male - 369.31) < 0.01)
        #expect(abs(female - 332.56) < 0.01)
        #expect(Dots.points(totalKg: 0, bodyWeightKg: 80, sex: .male) == nil)
        #expect(Dots.points(totalKg: 500, bodyWeightKg: 0, sex: .female) == nil)
    }

    @Test("Masa izvan raspona formule uzima se kao granica")
    func clampsBodyWeight() {
        #expect(Dots.points(totalKg: 600, bodyWeightKg: 250, sex: .male) == Dots.points(totalKg: 600, bodyWeightKg: 210, sex: .male))
        #expect(Dots.points(totalKg: 300, bodyWeightKg: 30, sex: .female) == Dots.points(totalKg: 300, bodyWeightKg: 40, sex: .female))
    }

    @Test("Zbroj je iz najbolje procjene 1RM triju dizanja u razdoblju")
    func scoreFromHistory() throws {
        let context = try makeContext()
        let squat = ExerciseRef(catalogId: "barbell-squat", name: "Čučanj")
        let bench = ExerciseRef(catalogId: "barbell-bench-press", name: "Potisak")
        let deadlift = ExerciseRef(catalogId: "barbell-deadlift", name: "Mrtvo")
        try addSession(context, ref: squat, daysAgo: 10, sets: [(150, 1, nil)])
        try addSession(context, ref: squat, daysAgo: 3, sets: [(140, 1, nil)])
        try addSession(context, ref: bench, daysAgo: 5, sets: [(100, 1, nil)])
        // Izvan 12 tjedana: ne ulazi.
        try addSession(context, ref: deadlift, daysAgo: 100, sets: [(250, 1, nil)])
        let engine = StatisticsEngine(context: context)

        let partial = try #require(try engine.dotsScore(bodyWeightKg: 90, sex: .male, endingAt: now))
        #expect(partial.missingLifts == ["barbell-deadlift"])
        #expect(partial.totalKg == nil && partial.points == nil)

        try addSession(context, ref: deadlift, daysAgo: 2, sets: [(200, 1, nil)])
        let score = try #require(try engine.dotsScore(bodyWeightKg: 90, sex: .male, endingAt: now))
        let total = [150.0, 100, 200].map { SetMetrics.estimatedOneRepMax(weightKg: $0, reps: 1) ?? 0 }.reduce(0, +)
        #expect(abs((score.totalKg ?? 0) - total) < 0.001)
        #expect(score.points == Dots.points(totalKg: total, bodyWeightKg: 90, sex: .male))
    }

    @Test("Bez ijednog od tri dizanja nema rezultata")
    func noLifts() throws {
        let context = try makeContext()
        try addSession(context, daysAgo: 2, sets: [(80, 5, nil)])
        #expect(try StatisticsEngine(context: context).dotsScore(bodyWeightKg: 80, sex: .female, endingAt: now) == nil)
    }
}
