import Catalog
import Foundation
import Models
import Testing
@testable import Training

private func work(_ weight: Double, _ reps: Int) -> SetValues {
    SetValues(kind: .working, weightKg: weight, reps: reps)
}

@Suite("Volumen i 1RM")
struct MetricsTests {

    @Test("Volumen po vrsti unosa")
    func volumeByInputType() {
        #expect(SetMetrics.volume(work(80, 8), inputType: .weightReps) == 640)
        #expect(SetMetrics.volume(SetValues(reps: 12), inputType: .bodyweight) == 0)
        #expect(SetMetrics.volume(SetValues(reps: 8, extraWeightKg: 10), inputType: .weightedBodyweight) == 80)
        #expect(SetMetrics.volume(SetValues(reps: 8, extraWeightKg: 30), inputType: .assisted) == 0)
        #expect(SetMetrics.volume(SetValues(durationSeconds: 60), inputType: .duration) == 0)
    }

    @Test("Warm-up nikad ne ulazi u volumen")
    func warmUpExcluded() {
        let warmUp = SetValues(kind: .warmUp, weightKg: 40, reps: 10)
        #expect(SetMetrics.volume(warmUp, inputType: .weightReps) == 0)
    }

    @Test("1RM po Epleyju i Brzyckom")
    func oneRepMax() throws {
        #expect(SetMetrics.estimatedOneRepMax(weightKg: 100, reps: 1) == 100)
        let epley = try #require(SetMetrics.estimatedOneRepMax(weightKg: 100, reps: 10, formula: .epley))
        #expect(abs(epley - 133.333) < 0.01)
        let brzycki = try #require(SetMetrics.estimatedOneRepMax(weightKg: 100, reps: 10, formula: .brzycki))
        #expect(abs(brzycki - 133.333) < 0.01)
        #expect(SetMetrics.estimatedOneRepMax(weightKg: 100, reps: 37, formula: .brzycki) == nil)
        #expect(SetMetrics.estimatedOneRepMax(weightKg: 0, reps: 5) == nil)
        #expect(SetMetrics.estimatedOneRepMax(weightKg: 100, reps: 0) == nil)
    }

    @Test("Što serija treba da bi se mogla označiti")
    func completeness() {
        #expect(SetMetrics.isComplete(work(80, 8), inputType: .weightReps))
        #expect(!SetMetrics.isComplete(SetValues(reps: 8), inputType: .weightReps))
        #expect(!SetMetrics.isComplete(work(80, 0), inputType: .weightReps))
        #expect(SetMetrics.isComplete(SetValues(reps: 8), inputType: .bodyweight))
        #expect(SetMetrics.isComplete(SetValues(durationSeconds: 30), inputType: .duration))
        #expect(!SetMetrics.isComplete(SetValues(), inputType: .duration))
        #expect(SetMetrics.isComplete(SetValues(distanceMeters: 5000), inputType: .durationDistance))
    }
}

@Suite("Smart defaults")
struct SmartDefaultsTests {
    let previous = [
        SetValues(kind: .warmUp, weightKg: 40, reps: 10),
        work(80, 8), work(85, 8), work(90, 6),
    ]

    @Test("Pozicija se računa zasebno za radne serije i warm-up")
    func positionPerKind() {
        #expect(SmartDefaults.defaults(forPosition: 0, kind: .working, previous: previous)?.weightKg == 80)
        #expect(SmartDefaults.defaults(forPosition: 1, kind: .working, previous: previous)?.weightKg == 85)
        #expect(SmartDefaults.defaults(forPosition: 2, kind: .working, previous: previous)?.reps == 6)
        #expect(SmartDefaults.defaults(forPosition: 0, kind: .warmUp, previous: previous)?.weightKg == 40)
        #expect(SmartDefaults.defaults(forPosition: 1, kind: .warmUp, previous: previous)?.weightKg == 40)
    }

    @Test("Više serija nego prošli put koristi zadnju prošlu seriju")
    func extraSets() {
        #expect(SmartDefaults.defaults(forPosition: 5, kind: .working, previous: previous)?.weightKg == 90)
    }

    @Test("Bez povijesti nema zadanih vrijednosti, a RPE se ne prenosi")
    func noHistoryAndRPE() {
        #expect(SmartDefaults.defaults(forPosition: 0, kind: .working, previous: []) == nil)
        #expect(SmartDefaults.defaults(forPosition: 0, kind: .warmUp, previous: [work(80, 8)]) == nil)
        let withRPE = [SetValues(weightKg: 80, reps: 8, rpe: 9)]
        #expect(SmartDefaults.defaults(forPosition: 0, kind: .working, previous: withRPE)?.rpe == nil)
    }
}

@Suite("Osobni rekordi")
struct PersonalRecordTests {

    private func kinds(_ records: [PersonalRecord]) -> Set<PRKind> { Set(records.map(\.kind)) }

    @Test("Prvi trening s vježbom nema rekorda")
    func noHistory() {
        #expect(PersonalRecordDetector.records(current: [work(100, 5)], history: [], inputType: .weightReps).isEmpty)
    }

    @Test("Veća težina je rekord težine")
    func maxWeight() {
        let result = PersonalRecordDetector.records(
            current: [work(85, 5)], history: [[work(80, 5)]], inputType: .weightReps
        )
        let record = result.first { $0.kind == .maxWeight }
        #expect(record?.value == 85)
        #expect(record?.previousBest == 80)
    }

    @Test("Ista težina nije rekord težine")
    func sameWeight() {
        let result = PersonalRecordDetector.records(current: [work(80, 5)], history: [[work(80, 5)]], inputType: .weightReps)
        #expect(!kinds(result).contains(.maxWeight))
    }

    @Test("Volumen je rekord po jednoj seriji")
    func maxVolume() {
        let history = [[work(80, 8), work(80, 8)]]
        let better = PersonalRecordDetector.records(
            current: [work(80, 8), work(80, 9)], history: history, inputType: .weightReps
        )
        #expect(better.first { $0.kind == .maxVolume }?.value == 720)
        let worse = PersonalRecordDetector.records(
            current: [work(80, 8), work(80, 8), work(80, 8)], history: history, inputType: .weightReps
        )
        #expect(!kinds(worse).contains(.maxVolume))
    }

    @Test("Ponavljanja su rekord samo uz istu ili veću težinu")
    func maxReps() {
        let history = [[work(100, 5), work(80, 12)]]
        // 6 ponavljanja sa 100 kg je rekord, 10 sa 80 kg nije (ranije 12 sa 80).
        let heavy = PersonalRecordDetector.records(current: [work(100, 6)], history: history, inputType: .weightReps)
        #expect(heavy.first { $0.kind == .maxReps }?.value == 6)
        let light = PersonalRecordDetector.records(current: [work(80, 10)], history: history, inputType: .weightReps)
        #expect(!kinds(light).contains(.maxReps))
        // 13 sa 80 je rekord.
        let more = PersonalRecordDetector.records(current: [work(80, 13)], history: history, inputType: .weightReps)
        #expect(more.first { $0.kind == .maxReps }?.value == 13)
    }

    @Test("Warm-up serije ne mogu biti rekord")
    func warmUpIgnored() {
        let warmUp = SetValues(kind: .warmUp, weightKg: 200, reps: 20)
        let result = PersonalRecordDetector.records(current: [warmUp], history: [[work(80, 5)]], inputType: .weightReps)
        #expect(result.isEmpty)
        // Ni warm-up u povijesti ne smije dizati prag.
        let pastWarmUp = PersonalRecordDetector.records(
            current: [work(85, 5)], history: [[warmUp, work(80, 5)]], inputType: .weightReps
        )
        #expect(pastWarmUp.first { $0.kind == .maxWeight }?.value == 85)
    }

    @Test("Vlastita težina: samo ponavljanja")
    func bodyweight() {
        let result = PersonalRecordDetector.records(
            current: [SetValues(reps: 15)], history: [[SetValues(reps: 12)]], inputType: .bodyweight
        )
        #expect(kinds(result) == [.maxReps])
    }

    @Test("Potpomognuta: rekord je manja pomoć")
    func assisted() {
        let history = [[SetValues(reps: 8, extraWeightKg: 30)]]
        let better = PersonalRecordDetector.records(
            current: [SetValues(reps: 8, extraWeightKg: 25)], history: history, inputType: .assisted
        )
        #expect(better.first { $0.kind == .lowestAssistance }?.value == 25)
        let worse = PersonalRecordDetector.records(
            current: [SetValues(reps: 8, extraWeightKg: 35)], history: history, inputType: .assisted
        )
        #expect(!kinds(worse).contains(.lowestAssistance))
    }

    @Test("Trajanje i udaljenost: najdulje")
    func durationAndDistance() {
        let duration = PersonalRecordDetector.records(
            current: [SetValues(durationSeconds: 90)], history: [[SetValues(durationSeconds: 60)]], inputType: .duration
        )
        #expect(kinds(duration) == [.longestDuration])
        let cardio = PersonalRecordDetector.records(
            current: [SetValues(durationSeconds: 1800, distanceMeters: 6000)],
            history: [[SetValues(durationSeconds: 1800, distanceMeters: 5000)]],
            inputType: .durationDistance
        )
        #expect(kinds(cardio) == [.longestDistance])
    }

    @Test("Isključeni tipovi se ne prijavljuju")
    func trackedKinds() {
        let result = PersonalRecordDetector.records(
            current: [work(90, 5)], history: [[work(80, 5)]], inputType: .weightReps,
            kinds: PRKind.kinds(fromSettings: ["maxVolume"])
        )
        #expect(kinds(result) == [.maxVolume])
        #expect(PRKind.kinds(fromSettings: []).isEmpty)
    }

    @Test("PR-ovi isključeni u postavkama ne prate ništa")
    func trackingFollowsSettings() {
        let settings = UserSettings()
        #expect(PRKind.tracked(by: settings) == PRKind.kinds(fromSettings: ["maxWeight", "maxVolume", "maxReps"]))
        settings.trackedPRKinds = ["maxVolume"]
        #expect(PRKind.tracked(by: settings) == [.maxVolume])
        settings.prEnabled = false
        #expect(PRKind.tracked(by: settings).isEmpty)
        #expect(PRKind.tracked(by: nil) == Set(PRKind.allCases))
    }

    @Test("Tema i boja imaju zadane vrijednosti i ignoriraju nepoznate")
    func themeAndAccent() {
        let settings = UserSettings()
        #expect(settings.theme == .system)
        #expect(settings.accent == .blue)
        settings.theme = .dark
        settings.accent = .teal
        #expect(settings.themeRaw == "dark" && settings.accentColorRaw == "teal")
        settings.themeRaw = "nepoznato"
        settings.accentColorRaw = "nepoznato"
        #expect(settings.theme == .system && settings.accent == .blue)
    }
}

@Suite("Rest timer i tijek")
struct RestTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Preostalo vrijeme i istek")
    func remaining() {
        let timer = RestTimer(startedAt: start, seconds: 90)
        #expect(timer.remaining(at: start.addingTimeInterval(30)) == 60)
        #expect(!timer.isExpired(at: start.addingTimeInterval(89)))
        #expect(timer.isExpired(at: start.addingTimeInterval(90)))
        #expect(timer.remaining(at: start.addingTimeInterval(500)) == 0)
        #expect(timer.progress(at: start.addingTimeInterval(45)) == 0.5)
    }

    @Test("+10 i −10 sekundi, bez skraćivanja ispod trenutka pritiska")
    func adjust() {
        let timer = RestTimer(startedAt: start, seconds: 90)
        let now = start.addingTimeInterval(20)
        #expect(timer.adjusted(bySeconds: 10, at: now).remaining(at: now) == 80)
        #expect(timer.adjusted(bySeconds: -10, at: now).remaining(at: now) == 60)
        #expect(timer.adjusted(bySeconds: -500, at: now).remaining(at: now) == 0)
    }

    @Test("Timer spremljen kao trenutak završetka ispravno se nastavlja nakon oporavka")
    func recovery() {
        let timer = RestTimer(startedAt: start, seconds: 120)
        let restored = RestTimer(startedAt: timer.startedAt, endsAt: timer.endsAt)
        #expect(restored.remaining(at: start.addingTimeInterval(100)) == 20)
        #expect(restored.isExpired(at: start.addingTimeInterval(3600)))
    }

    @Test("Pauza u supersetu: 0 osim nakon zadnje vježbe")
    func supersetRest() {
        #expect(RestPolicy.seconds(positionInGroup: 0, groupSize: 2, configured: nil, defaultSeconds: 90) == 0)
        #expect(RestPolicy.seconds(positionInGroup: 1, groupSize: 2, configured: nil, defaultSeconds: 90) == 90)
        #expect(RestPolicy.seconds(positionInGroup: 0, groupSize: 3, configured: 60, defaultSeconds: 120) == 0)
        #expect(RestPolicy.seconds(positionInGroup: 2, groupSize: 3, configured: nil, defaultSeconds: 120) == 120)
        #expect(RestPolicy.seconds(positionInGroup: 0, groupSize: 1, configured: 45, defaultSeconds: 90) == 45)
        #expect(RestPolicy.seconds(positionInGroup: 0, groupSize: 1, configured: nil, defaultSeconds: 90) == 90)
    }

    @Test("Naizmjenični redoslijed superseta")
    func supersetOrder() {
        let order = SupersetSequence.order(setCounts: [3, 2])
        #expect(order == [
            SetPosition(exercise: 0, set: 0), SetPosition(exercise: 1, set: 0),
            SetPosition(exercise: 0, set: 1), SetPosition(exercise: 1, set: 1),
            SetPosition(exercise: 0, set: 2),
        ])
        let completed: [SetPosition] = [SetPosition(exercise: 0, set: 0), SetPosition(exercise: 1, set: 0)]
        let next = SupersetSequence.nextIncomplete(setCounts: [3, 2]) { completed.contains($0) }
        #expect(next == SetPosition(exercise: 0, set: 1))
        let none = SupersetSequence.nextIncomplete(setCounts: [1, 1]) { _ in true }
        #expect(none == nil)
    }

    @Test("Prva nekompletirana vježba")
    func firstIncomplete() {
        #expect(WorkoutFlow.firstIncompleteExercise(isFullyCompleted: [true, false, false]) == 1)
        #expect(WorkoutFlow.firstIncompleteExercise(isFullyCompleted: [true, true]) == nil)
    }

    @Test("Zaboravljeni trening nakon 6 sati bez aktivnosti")
    func stale() {
        let lastSet = start.addingTimeInterval(600)
        let fresh = RecoveryAssessment.assess(
            startedAt: start, lastActivityAt: lastSet, lastCompletedSetAt: lastSet, now: lastSet.addingTimeInterval(3600)
        )
        #expect(!fresh.isStale)
        let stale = RecoveryAssessment.assess(
            startedAt: start, lastActivityAt: lastSet, lastCompletedSetAt: lastSet, now: lastSet.addingTimeInterval(7 * 3600)
        )
        #expect(stale.isStale)
        #expect(stale.suggestedEnd == lastSet)
        let noSets = RecoveryAssessment.assess(startedAt: start, lastActivityAt: start, lastCompletedSetAt: nil, now: start)
        #expect(noSets.suggestedEnd == start)
    }
}

@Suite("Kalkulator ploča")
struct PlateTests {
    let plates = [1.25, 2.5, 5, 10, 15, 20, 25]

    @Test("100 kg na šipki od 20 kg")
    func exact() {
        let result = PlateCalculator.calculate(target: 100, barbell: 20, plates: plates)
        #expect(result.perSide == [25, 15])
        #expect(result.isExact)
        #expect(result.achievedTotal == 100)
    }

    @Test("Decimalne ploče")
    func fractional() {
        let result = PlateCalculator.calculate(target: 62.5, barbell: 20, plates: plates)
        #expect(result.perSide == [20, 1.25])
        #expect(result.isExact)
    }

    @Test("Težina koja se ne može složiti daje najbližu manju")
    func notReachable() {
        let result = PlateCalculator.calculate(target: 61, barbell: 20, plates: plates)
        #expect(!result.isExact)
        #expect(result.achievedTotal == 60)
        #expect(abs(result.shortfall - 1) < 1e-9)
    }

    @Test("Manje od šipke i sama šipka")
    func edges() {
        #expect(PlateCalculator.calculate(target: 15, barbell: 20, plates: plates).isBelowBar)
        let bar = PlateCalculator.calculate(target: 20, barbell: 20, plates: plates)
        #expect(bar.perSide.isEmpty)
        #expect(bar.isExact)
        #expect(PlateCalculator.calculate(target: 100, barbell: 20, plates: []).perSide.isEmpty)
    }

    @Test("Nestandardan skup ploča: najmanji broj ploča, ne pohlepni izbor")
    func nonCanonical() {
        // Cilj 6 po strani s pločama 4, 3: pohlepno bi uzelo 4 pa stalo na 4, optimalno je 3 + 3.
        let result = PlateCalculator.calculate(target: 32, barbell: 20, plates: [4, 3])
        #expect(result.perSide == [3, 3])
        #expect(result.isExact)
    }

    @Test("Funti")
    func pounds() {
        let result = PlateCalculator.calculate(target: 225, barbell: 45, plates: [45, 35, 25, 10, 5, 2.5])
        #expect(result.perSide == [45, 45])
        #expect(result.isExact)
    }
}

/// Ponovljivi pseudoslučajni brojevi (LCG), da test uvijek provjerava iste podatke.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite("Sažeta povijest rekorda")
struct CondensedHistoryTests {

    private func randomSet(_ random: inout SeededGenerator) -> SetValues {
        SetValues(
            kind: Int.random(in: 0..<8, using: &random) == 0 ? .warmUp : .working,
            weightKg: Double(Int.random(in: 0...20, using: &random)) * 2.5,
            reps: Int.random(in: 0...15, using: &random),
            extraWeightKg: Double(Int.random(in: 0...12, using: &random)) * 2.5,
            durationSeconds: Int.random(in: 0...600, using: &random),
            distanceMeters: Double(Int.random(in: 0...50, using: &random)) * 100
        )
    }

    @Test("Sa sažetom poviješću rekordi su isti kao s punom, za svaku vrstu unosa")
    func sameRecords() {
        var random = SeededGenerator(state: 14)
        for type in ExerciseInputType.allCases {
            var full: [[SetValues]] = []
            var condensed: [[SetValues]] = []
            for _ in 0..<120 {
                let current = (0..<Int.random(in: 1...5, using: &random)).map { _ in randomSet(&random) }
                let expected = PersonalRecordDetector.records(current: current, history: full, inputType: type)
                let actual = PersonalRecordDetector.records(current: current, history: condensed, inputType: type)
                #expect(actual == expected, "\(type)")
                full.append(current)
                condensed = PersonalRecordDetector.condensed(condensed + [current])
            }
        }
    }

    @Test("Sažeta povijest ostaje mala")
    func staysSmall() {
        var random = SeededGenerator(state: 7)
        var condensed: [[SetValues]] = []
        for _ in 0..<500 {
            let current = (0..<4).map { _ in randomSet(&random) }
            condensed = PersonalRecordDetector.condensed(condensed + [current])
        }
        // Granica po težini ima najviše 21 razinu, pa je sažetak ograničen bez obzira na broj treninga.
        #expect(condensed.count == 1)
        #expect(condensed[0].count < 120)
        #expect(PersonalRecordDetector.condensed([]).isEmpty)
        #expect(PersonalRecordDetector.condensed([[SetValues(kind: .warmUp, weightKg: 20, reps: 10)]]).isEmpty)
    }
}

@Suite("Grupiranje ploča")
struct PlateGroupingTests {
    @Test("Iste ploče se zbrajaju po veličini")
    func grouping() {
        let result = PlateCalculator.grouped([20, 20, 5, 1.25, 1.25])
        #expect(result == [
            .init(plate: 20, count: 2), .init(plate: 5, count: 1), .init(plate: 1.25, count: 2)
        ])
        #expect(PlateCalculator.grouped([]).isEmpty)
    }
}
