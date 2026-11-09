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
        // RIR 2: računa se kao 10 ponavljanja do otkaza.
        let reserve = try #require(SetMetrics.estimatedOneRepMax(weightKg: 100, reps: 8, rir: 2))
        #expect(abs(reserve - 133.333) < 0.01)
    }

    @Test("Pouzdana procjena: RIR iz RPE-a, do 12 ponavljanja do otkaza, samo radne serije s teretom")
    func strengthEstimate() {
        #expect(SetMetrics.repsInReserve(SetValues(reps: 5, rpe: 8.5)) == 1.5)
        #expect(SetMetrics.repsInReserve(SetValues(reps: 5)) == 0)
        #expect(SetMetrics.strengthEstimate(work(100, 12), inputType: .weightReps) != nil)
        #expect(SetMetrics.strengthEstimate(SetValues(weightKg: 100, reps: 10, rpe: 7), inputType: .weightReps) == nil)
        #expect(SetMetrics.strengthEstimate(SetValues(kind: .warmUp, weightKg: 100, reps: 5), inputType: .weightReps) == nil)
        #expect(SetMetrics.strengthEstimate(SetValues(reps: 5, extraWeightKg: 20), inputType: .weightedBodyweight) != nil)
        #expect(SetMetrics.strengthEstimate(SetValues(reps: 5), inputType: .bodyweight) == nil)
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

    /// Povijest s dovoljno izvođenja za rekorde: prvo izvođenje ponovljeno do kalibracije.
    private func past(_ sessions: [[SetValues]], _ type: ExerciseInputType = .weightReps) -> RecordHistory {
        let padding = Array(repeating: sessions[0], count: max(0, RecordHistory.calibrationSessions - sessions.count))
        return RecordHistory(sessions: padding + sessions, inputType: type)
    }

    private func records(
        _ current: [SetValues], _ sessions: [[SetValues]], _ type: ExerciseInputType = .weightReps
    ) -> [PersonalRecord] {
        PersonalRecordDetector.records(current: current, history: past(sessions, type), inputType: type)
    }

    @Test("Bez povijesti i u prva tri izvođenja nema rekorda")
    func calibration() {
        #expect(PersonalRecordDetector.records(current: [work(100, 5)], history: RecordHistory(), inputType: .weightReps).isEmpty)
        let two = RecordHistory(sessions: [[work(80, 5)], [work(80, 5)]], inputType: .weightReps)
        #expect(PersonalRecordDetector.records(current: [work(100, 5)], history: two, inputType: .weightReps).isEmpty)
        let three = RecordHistory(sessions: [[work(80, 5)], [work(80, 5)], [work(80, 5)]], inputType: .weightReps)
        #expect(!PersonalRecordDetector.records(current: [work(100, 5)], history: three, inputType: .weightReps).isEmpty)
    }

    @Test("Procjena 1RM je glavni rekord, s pragom od 1 %")
    func oneRepMax() {
        // 180 × 5 = 210 kg, 185 × 5 = 215,8 kg (+2,8 %).
        let better = records([work(185, 5)], [[work(180, 5)]])
        let record = better.first { $0.kind == .estimatedOneRepMax }
        #expect(abs((record?.value ?? 0) - 215.833) < 0.01)
        #expect(abs((record?.previousBest ?? 0) - 210) < 0.01)
        // 140 → 140,5 kg je ispod praga.
        #expect(records([work(140.5, 5)], [[work(140, 5)]]).isEmpty)
    }

    @Test("RIR iz RPE-a ulazi u procjenu, a serije iznad 12 ponavljanja do otkaza ne")
    func oneRepMaxUsesReserve() {
        // 100 × 8 uz RPE 8 (RIR 2) je kao 10 do otkaza: 133,3 kg.
        let withReserve = SetValues(weightKg: 100, reps: 8, rpe: 8)
        let found = records([withReserve], [[work(100, 8)]])
        #expect(abs((found.first { $0.kind == .estimatedOneRepMax }?.value ?? 0) - 133.333) < 0.01)
        let tooMany = records([work(60, 20)], [[work(100, 5)]])
        #expect(!kinds(tooMany).contains(.estimatedOneRepMax))
    }

    @Test("Rekord po rasponu ponavljanja: jedan, najviši nadmašeni raspon")
    func repMax() {
        let history = [[work(100, 5), work(80, 10)]]
        let five = records([work(102.5, 5)], history)
        let record = five.first { $0.kind == .repMax }
        #expect(record?.reps == 5 && record?.value == 102.5 && record?.previousBest == 100)
        #expect(five.filter { $0.kind == .repMax }.count == 1)
        // 85 × 10 nadmašuje i raspon 10 i 8: prijavljuje se 10.
        #expect(records([work(85, 10)], history).first { $0.kind == .repMax }?.reps == 10)
    }

    @Test("Najveća težina ide u sažetak samo uz blizu najbolju procjenu 1RM")
    func milestone() {
        // 185 × 4 je teže od 180 × 5, a procjena 1RM je gotovo ista (209,7 prema 210 kg): ide u sažetak.
        let close = records([work(185, 4)], [[work(180, 5)]]).first { $0.kind == .maxWeight }
        #expect(close?.showsInSummary == true)
        // 190 × 1 je procjena 190 kg, 10 % ispod najbolje: samo u povijesti.
        let far = records([work(190, 1)], [[work(180, 5)]]).first { $0.kind == .maxWeight }
        #expect(far?.value == 190 && far?.showsInSummary == false)
    }

    @Test("Tonaža vježbe je rekord treninga, ali ne ide u sažetak")
    func exerciseVolume() {
        let record = records([work(80, 8), work(80, 8), work(80, 8)], [[work(80, 8), work(80, 8)]])
            .first { $0.kind == .exerciseVolume }
        #expect(record?.value == 1920 && record?.previousBest == 1280 && record?.showsInSummary == false)
    }

    @Test("Warm-up serije ne mogu biti rekord")
    func warmUpIgnored() {
        let warmUp = SetValues(kind: .warmUp, weightKg: 200, reps: 20)
        #expect(records([warmUp], [[work(80, 5)]]).isEmpty)
        // Ni warm-up u povijesti ne smije dizati prag.
        let pastWarmUp = records([work(85, 5)], [[warmUp, work(80, 5)]])
        #expect(pastWarmUp.first { $0.kind == .maxWeight }?.value == 85)
    }

    @Test("Vlastita težina: samo ponavljanja")
    func bodyweight() {
        #expect(kinds(records([SetValues(reps: 15)], [[SetValues(reps: 12)]], .bodyweight)) == [.maxReps])
    }

    @Test("Potpomognuta: rekord je manja pomoć")
    func assisted() {
        let history = [[SetValues(reps: 8, extraWeightKg: 30)]]
        #expect(records([SetValues(reps: 8, extraWeightKg: 25)], history, .assisted).first { $0.kind == .lowestAssistance }?.value == 25)
        #expect(!kinds(records([SetValues(reps: 8, extraWeightKg: 35)], history, .assisted)).contains(.lowestAssistance))
        #expect(records([SetValues(reps: 10, extraWeightKg: 30)], history, .assisted).first { $0.kind == .maxReps }?.value == 10)
    }

    @Test("Trajanje i udaljenost: najdulje")
    func durationAndDistance() {
        #expect(kinds(records([SetValues(durationSeconds: 90)], [[SetValues(durationSeconds: 60)]], .duration)) == [.longestDuration])
        let cardio = records(
            [SetValues(durationSeconds: 1800, distanceMeters: 6000)],
            [[SetValues(durationSeconds: 1800, distanceMeters: 5000)]],
            .durationDistance
        )
        #expect(kinds(cardio) == [.longestDistance])
    }

    @Test("Nakon pauze od 6 tjedana prva dva izvođenja nemaju rekorda")
    func returnAfterPause() {
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var history = RecordHistory()
        for index in 0..<4 {
            history.add([work(80, 5)], inputType: .weightReps, date: start.addingTimeInterval(Double(index) * 7 * day))
        }
        let back = start.addingTimeInterval(3 * 7 * day + 50 * day)
        #expect(!history.allowsRecords(at: back))
        history.add([work(70, 5)], inputType: .weightReps, date: back)
        #expect(!history.allowsRecords(at: back.addingTimeInterval(3 * day)))
        history.add([work(75, 5)], inputType: .weightReps, date: back.addingTimeInterval(3 * day))
        #expect(history.allowsRecords(at: back.addingTimeInterval(6 * day)))
    }

    @Test("Isključeni tipovi se ne prijavljuju")
    func trackedKinds() {
        let result = PersonalRecordDetector.records(
            current: [work(90, 5), work(90, 5)], history: past([[work(80, 5)]]), inputType: .weightReps,
            kinds: PRKind.kinds(fromSettings: ["maxVolume"])
        )
        #expect(kinds(result) == [.exerciseVolume])
        #expect(PRKind.kinds(fromSettings: []).isEmpty)
    }

    @Test("PR-ovi isključeni u postavkama ne prate ništa")
    func trackingFollowsSettings() {
        let settings = UserSettings()
        #expect(PRKind.tracked(by: settings) == PRKind.kinds(fromSettings: ["maxWeight", "maxVolume", "maxReps"]))
        settings.trackedPRKinds = ["maxVolume"]
        #expect(PRKind.tracked(by: settings) == [.exerciseVolume])
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

    @Test("Boje koje su izašle iz ponude čitaju se kao zadana Apolon plava")
    func removedAccentsFallBackToDefault() {
        let settings = UserSettings()
        for removed in ["green", "orange", "red"] {
            settings.accentColorRaw = removed
            settings.liveActivityAccentRaw = removed
            #expect(settings.accent == .blue)
            #expect(settings.liveActivityAccent == .blue)
        }
        #expect(AccentChoice.allCases == [.blue, .indigo, .purple, .pink, .teal, .graphite])
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

    @Test("Nakon zadnje serije vježbe otvara se sljedeća, i kad je serija potvrđena u Live Activityju")
    func advanceAfterCompletion() {
        #expect(WorkoutFlow.advance(openGroupDone: false, isFullyCompleted: [false, false]) == .stay)
        #expect(WorkoutFlow.advance(openGroupDone: true, isFullyCompleted: [true, false, false]) == .open(1))
        // Preskočena vježba iznad otvorene ima prednost.
        #expect(WorkoutFlow.advance(openGroupDone: true, isFullyCompleted: [false, true, false]) == .open(0))
        #expect(WorkoutFlow.advance(openGroupDone: true, isFullyCompleted: [true, true]) == .finished)
    }

    @Test("Nova završena serija od zadnjeg pogleda")
    func newCompletion() {
        #expect(WorkoutFlow.hasNewCompletion(completedCount: 4, lastSeen: 3))
        #expect(!WorkoutFlow.hasNewCompletion(completedCount: 3, lastSeen: 3))
        #expect(!WorkoutFlow.hasNewCompletion(completedCount: 2, lastSeen: 3))
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
            distanceMeters: Double(Int.random(in: 0...50, using: &random)) * 100,
            rpe: Int.random(in: 0..<3, using: &random) == 0 ? nil : Double(Int.random(in: 12...20, using: &random)) / 2
        )
    }

    @Test("Sa sažetom poviješću rekordi su isti kao s punom, za svaku vrstu unosa")
    func sameRecords() {
        var random = SeededGenerator(state: 14)
        for type in ExerciseInputType.allCases {
            var all: [SetValues] = []
            var bestVolume = 0.0
            var sessions = 0
            var condensed = RecordHistory()
            for _ in 0..<120 {
                let current = (0..<Int.random(in: 1...5, using: &random)).map { _ in randomSet(&random) }
                let full = RecordHistory(uncondensed: all, bestSessionVolume: bestVolume, sessionCount: sessions)
                let expected = PersonalRecordDetector.records(current: current, history: full, inputType: type)
                let actual = PersonalRecordDetector.records(current: current, history: condensed, inputType: type)
                #expect(actual == expected, "\(type)")
                let working = current.filter { $0.kind == .working }
                if !working.isEmpty {
                    all += working
                    sessions += 1
                    bestVolume = max(bestVolume, working.reduce(0) { $0 + SetMetrics.volume($1, inputType: type) })
                }
                condensed.add(current, inputType: type, date: nil)
            }
        }
    }

    @Test("Sažeta povijest ostaje mala")
    func staysSmall() {
        var random = SeededGenerator(state: 7)
        var history = RecordHistory()
        for _ in 0..<500 {
            history.add((0..<4).map { _ in randomSet(&random) }, inputType: .weightReps, date: nil)
        }
        // Granica po težini ima najviše 21 razinu, pa je sažetak ograničen bez obzira na broj treninga.
        #expect(history.sets.count < 120)
        #expect(PersonalRecordDetector.condensed([]).isEmpty)
        #expect(PersonalRecordDetector.condensed([SetValues(kind: .warmUp, weightKg: 20, reps: 10)]).isEmpty)
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

@Suite("Uključivanje i isključivanje ploča")
struct PlateToggleTests {
    @Test("Uključena ploča se dodaje na svoje mjesto, bez duplikata")
    func enable() {
        #expect(PlateCalculator.setting(5, enabled: true, in: [20, 1.25, 10]) == [1.25, 5, 10, 20])
        #expect(PlateCalculator.setting(10, enabled: true, in: [10, 20]) == [10, 20])
    }

    @Test("Isključena ploča se miče, ostale ostaju")
    func disable() {
        #expect(PlateCalculator.setting(10, enabled: false, in: [1.25, 10, 20]) == [1.25, 20])
        #expect(PlateCalculator.setting(0.5, enabled: false, in: [10]) == [10])
    }
}
