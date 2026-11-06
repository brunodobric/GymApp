import Catalog
import Foundation
import Models
import SwiftData
import Testing
import Training
@testable import Stats

private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let squat = ExerciseRef(catalogId: "squat", name: "Čučanj")
/// Petak 15. 1. 2027., 08:00 UTC.
private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private struct Work {
    let weight: Double
    let reps: Int
    var kind: SetKind = .working
    var rpe: Double?
}

private struct Lift {
    let ref: ExerciseRef
    let sets: [Work]
}

/// Dodaje završen trening izravno u bazu (bez WorkoutEnginea), s jednim spremanjem na kraju.
@discardableResult
private func addSession(
    _ context: ModelContext, at date: Date, kind: WorkoutKind = .strength, lifts: [Lift], save: Bool = true
) throws -> Session {
    let session = Session(name: "Trening", kind: kind, startedAt: date)
    session.state = .finished
    session.endedAt = date.addingTimeInterval(3600)
    context.insert(session)
    for (index, lift) in lifts.enumerated() {
        let exercise = SessionExercise(orderIndex: index, exercise: lift.ref, inputType: .weightReps)
        context.insert(exercise)
        exercise.session = session
        for (setIndex, work) in lift.sets.enumerated() {
            let set = SetLog(orderIndex: setIndex, kind: work.kind)
            set.weightKg = work.weight
            set.reps = work.reps
            set.rpe = work.rpe
            set.completedAt = date.addingTimeInterval(600)
            context.insert(set)
            set.exercise = exercise
        }
    }
    if save { try context.save() }
    return session
}

private let infoProvider: ExerciseInfoProvider = { key in
    switch key {
    case "c:bench":
        ExerciseInfo(primary: [.chest], secondary: [.triceps], primaryRegions: ["chest"], secondaryRegions: ["triceps"])
    case "c:squat":
        ExerciseInfo(primary: [.quadriceps], secondary: [.glutes], primaryRegions: ["quads"], secondaryRegions: ["glutes"])
    default:
        nil
    }
}

@Suite("Povijest treninga")
struct HistoryTests {

    @Test("Filter po vrsti i sortiranje po datumu")
    func filterAndSort() throws {
        let context = try makeContext()
        let lifts = [Lift(ref: bench, sets: [Work(weight: 80, reps: 5)])]
        let old = try addSession(context, at: base, lifts: lifts)
        let new = try addSession(context, at: base.addingTimeInterval(day), kind: .cardio, lifts: lifts)
        let history = HistoryQueries(context: context)

        #expect(try history.sessions().map(\.id) == [new.id, old.id])
        #expect(try history.sessions(filter: HistoryFilter(sort: .oldestFirst)).map(\.id) == [old.id, new.id])
        #expect(try history.sessions(filter: HistoryFilter(kinds: [.cardio])).map(\.id) == [new.id])
    }

    @Test("Ispod kalendara su treninzi prikazanog mjeseca, a s odabranim danom samo tog dana")
    func calendarList() throws {
        let context = try makeContext()
        // 15. 1., 31. 1. u 23:00 i 1. 2. 2027.
        let jan15 = try addSession(context, at: base, lifts: [])
        let jan31 = try addSession(context, at: base.addingTimeInterval(16 * day + 15 * 3600), kind: .cardio, lifts: [])
        let feb1 = try addSession(context, at: base.addingTimeInterval(17 * day), lifts: [])
        let all = [jan15, jan31, feb1]
        let filter = HistoryFilter()

        #expect(filter.apply(to: all, month: base, day: nil, calendar: calendar).map(\.id) == [jan31.id, jan15.id])
        #expect(filter.apply(to: all, month: feb1.startedAt, day: nil, calendar: calendar).map(\.id) == [feb1.id])
        #expect(filter.apply(to: all, month: base, day: jan31.startedAt, calendar: calendar).map(\.id) == [jan31.id])
        #expect(filter.apply(to: all, month: base, day: base.addingTimeInterval(day), calendar: calendar).isEmpty)
        #expect(HistoryFilter(kinds: [.strength]).apply(to: all, month: base, day: nil, calendar: calendar).map(\.id) == [jan15.id])
    }

    @Test("Treninzi koji nisu završeni nisu u povijesti")
    func onlyFinished() throws {
        let context = try makeContext()
        let session = try addSession(context, at: base, lifts: [])
        session.state = .active
        try context.save()
        #expect(try HistoryQueries(context: context).sessions().isEmpty)
    }

    @Test("Dani s treningom za kalendar i popis treninga za dan")
    func calendarDays() throws {
        let context = try makeContext()
        let lifts = [Lift(ref: bench, sets: [Work(weight: 80, reps: 5)])]
        try addSession(context, at: base, lifts: lifts)
        try addSession(context, at: base.addingTimeInterval(3 * 3600), lifts: lifts)
        try addSession(context, at: base.addingTimeInterval(2 * day), lifts: lifts)
        let history = HistoryQueries(context: context)

        let month = try #require(calendar.dateInterval(of: .month, for: base))
        let days = try history.workoutDays(in: month, calendar: calendar)
        #expect(days == [calendar.startOfDay(for: base), calendar.startOfDay(for: base.addingTimeInterval(2 * day))])
        #expect(try history.sessions(on: base, calendar: calendar).count == 2)
        #expect(try history.sessions(on: base.addingTimeInterval(day), calendar: calendar).isEmpty)
    }

    @Test("Brisanje treninga briše i njegove vježbe i serije")
    func deleteCascade() throws {
        let context = try makeContext()
        let session = try addSession(context, at: base, lifts: [Lift(ref: bench, sets: [Work(weight: 80, reps: 5)])])
        try HistoryQueries(context: context).delete(session)
        #expect(try context.fetch(FetchDescriptor<Session>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    }
}

@Suite("Statistika")
struct StatisticsTests {

    @Test("Napredak vježbe: najbolja težina, 1RM i volumen bez zagrijavanja")
    func progress() throws {
        let context = try makeContext()
        try addSession(context, at: base, lifts: [Lift(ref: bench, sets: [
            Work(weight: 40, reps: 10, kind: .warmUp), Work(weight: 100, reps: 5), Work(weight: 90, reps: 8)
        ])])
        try addSession(context, at: base.addingTimeInterval(7 * day), lifts: [Lift(ref: bench, sets: [Work(weight: 105, reps: 5)])])
        try addSession(context, at: base.addingTimeInterval(day), lifts: [Lift(ref: squat, sets: [Work(weight: 150, reps: 5)])])

        let points = try StatisticsEngine(context: context).progress(of: bench)
        #expect(points.count == 2)
        #expect(points[0].date < points[1].date)
        #expect(points[0].bestWeightKg == 100)
        #expect(points[0].volumeKg == 100 * 5 + 90 * 8)
        // Epley: 100 × (1 + 5/30) = 116,67; 90 × (1 + 8/30) = 114.
        #expect(abs((points[0].estimatedOneRepMaxKg ?? 0) - 116.6667) < 0.01)
        let brzycki = try StatisticsEngine(context: context).progress(of: bench, formula: .brzycki)
        #expect(abs((brzycki[0].estimatedOneRepMaxKg ?? 0) - 112.5) < 0.01)
    }

    @Test("Tjedni volumen po mišiću, mjeseci i vrijeme izvan raspona")
    func volumeBuckets() throws {
        let context = try makeContext()
        // Tjedan od ponedjeljka 11. 1.: dva treninga prsa i noge; prethodni tjedan jedan; stariji od raspona.
        try addSession(context, at: base, lifts: [
            Lift(ref: bench, sets: [Work(weight: 100, reps: 5), Work(weight: 20, reps: 10, kind: .warmUp)]),
            Lift(ref: squat, sets: [Work(weight: 120, reps: 5)]),
        ])
        try addSession(context, at: base.addingTimeInterval(day), lifts: [Lift(ref: bench, sets: [Work(weight: 100, reps: 4)])])
        try addSession(context, at: base.addingTimeInterval(-7 * day), lifts: [Lift(ref: bench, sets: [Work(weight: 90, reps: 5)])])
        try addSession(context, at: base.addingTimeInterval(-60 * day), lifts: [Lift(ref: bench, sets: [Work(weight: 90, reps: 5)])])

        let engine = StatisticsEngine(context: context)
        let weeks = try engine.volumeBuckets(size: .week, count: 2, endingAt: base, calendar: calendar, info: infoProvider)
        #expect(weeks.count == 2)
        #expect(weeks[0].loads["chest"] == MuscleLoad(volumeKg: 450, sets: 1))
        #expect(weeks[1].loads["chest"] == MuscleLoad(volumeKg: 900, sets: 2))
        #expect(weeks[1].loads["quads"] == MuscleLoad(volumeKg: 600, sets: 1))
        #expect(weeks[1].totalVolumeKg == 1500)
        #expect(weeks[1].totalSets == 3)
        // Pomoćne regije dobivaju pola serije, ali ne i tonažu.
        #expect(weeks[1].loads["triceps"] == MuscleLoad(volumeKg: 0, sets: 1))
        #expect(weeks[1].loads["glutes"] == MuscleLoad(volumeKg: 0, sets: 0.5))

        let months = try engine.volumeBuckets(size: .month, count: 3, endingAt: base, calendar: calendar, info: infoProvider)
        #expect(months.count == 3)
        #expect(months[2].loads["chest"]?.sets == 3)
        #expect(months[0].loads["chest"]?.sets == 1)
    }

    @Test("Serije s vlastitom težinom broje se u serije, a ne u tonažu")
    func bodyweightSetsCount() throws {
        let context = try makeContext()
        let session = try addSession(context, at: base, lifts: [Lift(ref: bench, sets: [Work(weight: 0, reps: 12)])])
        session.orderedExercises.first?.inputType = .bodyweight
        try context.save()
        let weeks = try StatisticsEngine(context: context)
            .volumeBuckets(size: .week, count: 1, endingAt: base, calendar: calendar, info: infoProvider)
        #expect(weeks[0].loads["chest"] == MuscleLoad(volumeKg: 0, sets: 1))
        #expect(weeks[0].totalSets == 1)
    }

    @Test("Frekvencija po tjednima")
    func frequency() throws {
        let context = try makeContext()
        let lifts = [Lift(ref: bench, sets: [Work(weight: 80, reps: 5)])]
        try addSession(context, at: base, lifts: lifts)
        try addSession(context, at: base.addingTimeInterval(day), lifts: lifts)
        try addSession(context, at: base.addingTimeInterval(-7 * day), lifts: lifts)
        let points = try StatisticsEngine(context: context).frequency(weeks: 3, endingAt: base, calendar: calendar)
        #expect(points.map(\.sessions) == [0, 1, 2])
    }

    @Test("Rekordi kroz povijest: prvi trening nije rekord, kasniji jesu")
    func records() throws {
        let context = try makeContext()
        try addSession(context, at: base, lifts: [Lift(ref: bench, sets: [Work(weight: 80, reps: 5)])])
        try addSession(context, at: base.addingTimeInterval(7 * day), lifts: [Lift(ref: bench, sets: [Work(weight: 85, reps: 5)])])
        try addSession(context, at: base.addingTimeInterval(14 * day), lifts: [Lift(ref: bench, sets: [Work(weight: 82, reps: 5)])])

        let entries = try StatisticsEngine(context: context).personalRecords()
        let weight = entries.filter { $0.record.kind == .maxWeight }
        #expect(weight.count == 1)
        #expect(weight[0].record.value == 85 && weight[0].record.previousBest == 80)
        #expect(weight[0].exerciseName == "Potisak s klupe")
        // Najnoviji prvi.
        #expect(entries.map(\.date) == entries.map(\.date).sorted(by: >))
        #expect(try StatisticsEngine(context: context).personalRecords(kinds: []).isEmpty)
    }

    @Test("Heatmap: serije tjedno na fiksnoj skali, pomoćne upola, učestalost samo s cijelom serijom")
    func heatmap() throws {
        let context = try makeContext()
        try addSession(context, at: base, lifts: [Lift(ref: bench, sets: [Work(weight: 100, reps: 5)])])
        try addSession(context, at: base.addingTimeInterval(day), lifts: [
            Lift(ref: bench, sets: [Work(weight: 100, reps: 5)]),
            Lift(ref: squat, sets: [Work(weight: 100, reps: 5)]),
        ])

        // Prvi trening je na početku razdoblja, pa je razdoblje kraće od tjedna i prosjek se računa na 1 tjedan.
        let result = try StatisticsEngine(context: context).heatmap(
            from: base.addingTimeInterval(-day), until: base.addingTimeInterval(3 * day), info: infoProvider
        )
        let chest = try #require(result["chest"])
        #expect(chest.sessions == 2 && chest.sets == 2 && chest.weeklySets == 2 && chest.volumeKg == 1000)
        #expect(chest.weeklyLevel == 1 && chest.intensity == 0.25)
        #expect(chest.lastTrained == base.addingTimeInterval(day))
        // Pomoćna regija: dvije polovine serije u dva treninga, ni u jednom cijela serija.
        #expect(result["triceps"]?.sets == 1 && result["triceps"]?.sessions == 0 && result["triceps"]?.volumeKg == 500)
        #expect(result["quads"]?.sessions == 1)
        #expect(result["glutes"]?.volumeKg == 250)
        #expect(result["lats"] == nil)
    }

    @Test("Heatmap: prosjek po tjednima razdoblja i razine skale")
    func heatmapWeeklyAverage() throws {
        let context = try makeContext()
        // Stari trening izvan razdoblja: razdoblje od 14 dana računa se cijelo.
        try addSession(context, at: base.addingTimeInterval(-60 * day), lifts: [Lift(ref: bench, sets: [Work(weight: 80, reps: 5)])])
        let ten = (0..<10).map { _ in Work(weight: 80, reps: 8) }
        try addSession(context, at: base.addingTimeInterval(-3 * day), lifts: [Lift(ref: bench, sets: ten)])
        try addSession(context, at: base.addingTimeInterval(-10 * day), lifts: [Lift(ref: bench, sets: ten)])
        let result = try StatisticsEngine(context: context).heatmap(
            from: base.addingTimeInterval(-14 * day), until: base, info: infoProvider
        )
        #expect(abs((result["chest"]?.weeklySets ?? 0) - 10) < 0.001)
        #expect(result["chest"]?.weeklyLevel == 3)
        #expect(abs((result["chest"]?.sessionsPerWeek ?? 0) - 1) < 0.001)
        #expect(result["triceps"]?.weeklyLevel == 2)
    }

    @Test("Trend snage: promjena najbolje procjene 1RM po regiji između dva razdoblja")
    func strengthTrends() throws {
        let context = try makeContext()
        try addSession(context, at: base.addingTimeInterval(-35 * day), lifts: [Lift(ref: bench, sets: [Work(weight: 100, reps: 5)])])
        try addSession(context, at: base.addingTimeInterval(-3 * day), lifts: [
            Lift(ref: bench, sets: [Work(weight: 105, reps: 5), Work(weight: 60, reps: 20)]),
            Lift(ref: squat, sets: [Work(weight: 120, reps: 5)]),
        ])
        let trends = try StatisticsEngine(context: context).strengthTrends(weeks: 4, endingAt: base, info: infoProvider)
        #expect(trends.map(\.region) == ["chest"])
        #expect(abs(trends[0].change - 0.05) < 0.0001)
        #expect(trends[0].exercises == 1)
    }
}

@Suite("Praćenje tijela")
struct BodyTrackingTests {

    @Test("Unos, povijest, promjena i brisanje")
    func basics() throws {
        let context = try makeContext()
        let tracking = BodyTracking(context: context)
        try tracking.add(.weight, value: 82, date: base)
        let last = try tracking.add(.weight, value: 80.5, date: base.addingTimeInterval(7 * day))
        try tracking.add(.waist, value: 90, date: base)

        #expect(try tracking.measurements(of: .weight).map(\.value) == [82, 80.5])
        #expect(try tracking.latest(of: .weight)?.value == 80.5)
        #expect(try tracking.change(of: .weight) == -1.5)
        #expect(try tracking.change(of: .waist) == nil)
        try tracking.delete(last)
        #expect(try tracking.measurements(of: .weight).count == 1)
    }

    @Test("Neispravne vrijednosti se odbijaju")
    func validation() throws {
        let tracking = BodyTracking(context: try makeContext())
        #expect(throws: BodyTrackingError.invalidValue) { try tracking.add(.weight, value: 0) }
        #expect(throws: BodyTrackingError.invalidValue) { try tracking.add(.weight, value: -3) }
        #expect(throws: BodyTrackingError.invalidValue) { try tracking.add(.weight, value: .nan) }
    }

    @Test("Vlastite mjere se razlikuju po nazivu")
    func customMeasurements() throws {
        let context = try makeContext()
        let tracking = BodyTracking(context: context)
        try tracking.add(.custom, value: 35, customName: "Podlaktica")
        try tracking.add(.custom, value: 38, customName: " Vrat ")
        try tracking.add(.custom, value: 36, date: base.addingTimeInterval(day), customName: "Podlaktica")
        #expect(try tracking.customNames() == ["Podlaktica", "Vrat"])
        #expect(try tracking.measurements(of: .custom, customName: "Podlaktica").map(\.value) == [35, 36])
        #expect(try tracking.measurements(of: .custom, customName: "Vrat").count == 1)
    }
}

@Suite("Brzina statistike")
struct StatisticsPerformanceTests {

    /// Godinu dana podataka: 156 treninga (3 tjedno), 5 vježbi, 4 serije.
    @Test("Statistika za godinu dana podataka računa se brzo")
    func yearOfData() throws {
        let context = try makeContext()
        let refs = (0..<5).map { ExerciseRef(catalogId: "ex\($0)", name: "Vježba \($0)") }
        for index in 0..<156 {
            let date = base.addingTimeInterval(Double(index) * 2.3 * day - 365 * day)
            let lifts = refs.map { ref in
                Lift(ref: ref, sets: (0..<4).map { Work(weight: 60 + Double(index) * 0.2 + Double($0), reps: 8) })
            }
            try addSession(context, at: date, lifts: lifts, save: false)
        }
        try context.save()

        let provider: ExerciseInfoProvider = { _ in ExerciseInfo(primary: [.chest], primaryRegions: ["chest"]) }
        let engine = StatisticsEngine(context: context)
        let start = Date()
        let records = try engine.personalRecords()
        let weekly = try engine.volumeBuckets(size: .week, count: 52, endingAt: base, calendar: calendar, info: provider)
        let points = try engine.progress(of: refs[0])
        let heat = try engine.heatmap(from: base.addingTimeInterval(-400 * day), until: base, info: provider)
        let elapsed = Date().timeIntervalSince(start)
        print("Statistika za godinu dana: \(elapsed) s")

        #expect(!records.isEmpty && weekly.count == 52 && points.count == 156 && !heat.isEmpty)
        // Test hvata algoritamske kvarove (red veličine), ne mikro-razlike. Na Macu traje oko 1 s, a na dijeljenom
        // CI runneru uz paralelne testove izmjereno je 4,7 s, zato je granica 10 s. Cilj na uređaju je ispod 0,5 s.
        #expect(elapsed < 10, "Statistika je trajala \(elapsed) s")
    }
}

@Suite("ExerciseInfoBuilder")
struct ExerciseInfoBuilderTests {
    @Test func customExerciseGetsRegionsFromMuscles() {
        let custom = CustomExercise(name: "Moja")
        custom.muscles = [.chest, .middleBack, .neck, .traps]
        let provider = ExerciseInfoBuilder.provider(catalog: nil, custom: [custom])
        let info = provider("u:\(custom.id.uuidString)")
        #expect(info?.primary == [.chest, .middleBack, .neck, .traps])
        #expect(info?.primaryRegions == ["chest", "upperBack", "traps"])
        #expect(provider("c:nepoznato") == nil)
    }

    @Test func majorRegionsAreKnown() {
        #expect(BodyRegion.major.allSatisfy(BodyRegion.all.contains))
    }

    @Test func everyMuscleHasKnownRegion() {
        for muscle in Muscle.allCases {
            #expect(BodyRegion.all.contains(BodyRegion.region(for: muscle)))
        }
    }

    @Test("Svaka regija ima boju, bliske regije dijele boju, a nepoznata nema")
    func colorGroups() {
        for region in BodyRegion.all {
            #expect(BodyRegion.colorGroup(for: region) != nil)
        }
        #expect(BodyRegion.colorGroup(for: "lats") == BodyRegion.colorGroup(for: "lowerBack"))
        #expect(BodyRegion.colorGroup(for: "quads") == .legs)
        #expect(BodyRegion.colorGroup(for: "chest") != BodyRegion.colorGroup(for: "triceps"))
        #expect(BodyRegion.colorGroup(for: "neck") == nil)
        // Sve boje se koriste.
        let used = Set(BodyRegion.all.compactMap { BodyRegion.colorGroup(for: $0) })
        #expect(used.count == BodyRegion.ColorGroup.allCases.count)
    }
}

@Suite("ExerciseRef ključ")
struct ExerciseRefKeyTests {
    @Test func roundTrip() {
        let catalogRef = ExerciseRef(catalogId: "bench", name: "A")
        #expect(ExerciseRef(key: catalogRef.key, name: "A") == catalogRef)
        let customRef = ExerciseRef(customExerciseId: UUID(), name: "B")
        #expect(ExerciseRef(key: customRef.key, name: "B") == customRef)
        #expect(ExerciseRef(key: "x:1", name: "C") == nil)
        #expect(ExerciseRef(key: "u:nije-uuid", name: "C") == nil)
        #expect(ExerciseRef(key: "c:", name: "C") == nil)
    }
}

@Suite("BodyMap")
struct BodyMapTests {
    @Test func parsesMoveLineCurveClose() {
        let commands = SVGPathParser.parse("M1.5 2L3-4C1 2 3 4 5 6Z")
        #expect(commands == [
            .move(toX: 1.5, toY: 2), .line(toX: 3, toY: -4),
            .curve(c1x: 1, c1y: 2, c2x: 3, c2y: 4, toX: 5, toY: 6), .close
        ])
    }

    @Test func repeatsImplicitArguments() {
        let commands = SVGPathParser.parse("M0 0 1 1 2 2C1 1 2 2 3 3 4 4 5 5 6 6")
        #expect(commands.count == 5)
        #expect(commands[1] == .line(toX: 1, toY: 1))
        #expect(commands[4] == .curve(c1x: 4, c1y: 4, c2x: 5, c2y: 5, toX: 6, toY: 6))
    }

    @Test func handlesAdjacentDecimalsAndMultipleSubpaths() {
        let commands = SVGPathParser.parse("M1.5.5L2 2ZM5 5L6 6Z")
        #expect(commands.first == .move(toX: 1.5, toY: 0.5))
        #expect(commands.filter { $0 == .close }.count == 2)
    }

    @Test func stopsOnUnsupportedOrIncompleteInput() {
        #expect(SVGPathParser.parse("M0 0A1 1 0 0 1 2 2") == [.move(toX: 0, toY: 0)])
        #expect(SVGPathParser.parse("M0 0L5") == [.move(toX: 0, toY: 0)])
        #expect(SVGPathParser.parse("").isEmpty)
    }

    @Test func decodesDiagramAndMapsGroups() throws {
        let json = """
        {"male-front":{"viewBox":[0,0,10,20],"bounds":[1,2,8,16],"outline":[{"id":"BODY","d":"M0 0Z"}],
        "muscles":[{"id":"A","group":"QUADS","d":"M0 0Z"}]}}
        """
        let diagrams = try BodyMap.decode(Data(json.utf8))
        let diagram = try #require(diagrams[BodyMap.key(female: false, back: false)])
        #expect(diagram.muscles.first?.group == "QUADS")
        #expect(diagram.outline.first?.group == nil)
        #expect(diagram.bounds == [1, 2, 8, 16])
    }

    @Test func everyBodyMapGroupMapsToKnownRegion() {
        let groups = [
            "CHEST", "SHOULDERS_FRONT", "SHOULDERS_SIDE", "SHOULDERS_REAR", "BICEPS", "TRICEPS", "FOREARMS", "CORE",
            "OBLIQUES", "QUADS", "HAMSTRINGS", "ADDUCTORS", "ABDUCTORS", "TRAPEZIUS", "RHOMBOIDS", "LATS",
            "BACK_LOWER", "GLUTES", "CALVES"
        ]
        for group in groups {
            let region = BodyRegion.region(forBodyMapGroup: group)
            #expect(region != nil && BodyRegion.all.contains(region ?? ""))
        }
        #expect(BodyRegion.region(forBodyMapGroup: "HIP_FLEXORS") == nil)
    }
}

@Suite("Regije treninga")
struct SessionRegionsTests {
    @Test("Boja jednog treninga je na fiksnoj skali, pomoćne serije upola")
    func primaryAndSecondary() throws {
        let context = try makeContext()
        let six = (0..<6).map { _ in Work(weight: 80, reps: 5) }
        let session = try addSession(context, at: base, lifts: [Lift(ref: bench, sets: six)])
        let regions = SessionRegions.worked(in: session, info: infoProvider)
        #expect(regions["chest"]?.intensity == 0.75)
        #expect(regions["triceps"]?.intensity == 0.5)
        #expect(regions["triceps"]?.sets == 3)
        #expect(regions["quads"] == nil)
    }

    @Test("Lagan trening ostaje svijetao: boja ne ovisi o najopterećenijoj regiji")
    func intensityBySets() throws {
        let context = try makeContext()
        let session = try addSession(context, at: base, lifts: [
            Lift(ref: bench, sets: [Work(weight: 80, reps: 5), Work(weight: 80, reps: 5)]),
            Lift(ref: squat, sets: [
                Work(weight: 100, reps: 5), Work(weight: 100, reps: 5),
                Work(weight: 100, reps: 5), Work(weight: 100, reps: 5)
            ])
        ])
        let sets = SessionRegions.sets(in: session, info: infoProvider)
        #expect(sets.map(\.region) == ["quads", "chest", "glutes", "triceps"])
        #expect(sets.first == RegionSets(region: "quads", primarySets: 4, volumeKg: 2000))
        #expect(sets.last == RegionSets(region: "triceps", secondarySets: 2, volumeKg: 400))

        let heatmap = SessionRegions.heatmap(sets)
        #expect(heatmap["quads"]?.intensity == 0.5)
        #expect(heatmap["chest"]?.intensity == 0.25)
        #expect(heatmap["glutes"]?.intensity == 0.25)
        #expect(heatmap["triceps"]?.intensity == 0.25)
    }

    @Test("Serija s RPE ispod 6 se ne broji, s RPE 6 ili bez RPE-a se broji")
    func easySetsIgnored() throws {
        let context = try makeContext()
        let session = try addSession(context, at: base, lifts: [Lift(ref: bench, sets: [
            Work(weight: 40, reps: 10, rpe: 5), Work(weight: 60, reps: 8, rpe: 6), Work(weight: 70, reps: 6)
        ])])
        let sets = SessionRegions.sets(in: session, info: infoProvider)
        #expect(sets.first { $0.region == "chest" }?.primarySets == 2)
    }

    @Test("Serije iste regije iz više vježbi se zbrajaju, glavne i pomoćne odvojeno")
    func setsAddUpAcrossExercises() throws {
        let context = try makeContext()
        let session = try addSession(context, at: base, lifts: [
            Lift(ref: bench, sets: [Work(weight: 80, reps: 5), Work(weight: 80, reps: 5)]),
            Lift(ref: squat, sets: [Work(weight: 100, reps: 5)])
        ])
        let sets = SessionRegions.sets(in: session, info: { key in
            key == "c:squat"
                ? ExerciseInfo(primaryRegions: ["triceps"], secondaryRegions: ["chest", "triceps"])
                : infoProvider(key)
        })
        #expect(sets.first { $0.region == "chest" }?.primarySets == 2)
        #expect(sets.first { $0.region == "chest" }?.secondarySets == 1)
        // Regija koja je u vježbi i glavna i pomoćna broji se samo kao glavna.
        #expect(sets.first { $0.region == "triceps" }?.primarySets == 1)
        #expect(sets.first { $0.region == "triceps" }?.secondarySets == 2)
    }

    @Test("Warm-up i nezavršene vježbe se ne broje, a trening bez serija nema heatmap")
    func warmupIgnored() throws {
        let context = try makeContext()
        let session = try addSession(context, at: base, lifts: [
            Lift(ref: squat, sets: [Work(weight: 100, reps: 5, kind: .warmUp)])
        ])
        #expect(SessionRegions.sets(in: session, info: infoProvider).isEmpty)
        #expect(SessionRegions.worked(in: session, info: infoProvider).isEmpty)
    }
}

@Suite("Usporedba volumena")
struct VolumeComparisonTests {

    @Test("Zadnje razdoblje uspoređuje se s prethodnim u serijama, regije od najviše serija")
    func compareLastTwo() throws {
        let buckets = [
            VolumeBucket(start: base.addingTimeInterval(-14 * day), loads: ["chest": MuscleLoad(volumeKg: 5000, sets: 9)], totalSets: 9),
            VolumeBucket(start: base.addingTimeInterval(-7 * day), loads: [
                "chest": MuscleLoad(volumeKg: 1000, sets: 3),
                "quads": MuscleLoad(volumeKg: 3000, sets: 5),
            ], totalSets: 8),
            VolumeBucket(start: base, loads: [
                "chest": MuscleLoad(volumeKg: 1500, sets: 4),
                "biceps": MuscleLoad(volumeKg: 300, sets: 2),
            ], totalSets: 6),
        ]
        let comparison = try #require(VolumeComparison(buckets: buckets))
        #expect(comparison.currentStart == base)
        #expect(comparison.previousStart == base.addingTimeInterval(-7 * day))
        #expect(comparison.currentSets == 6)
        #expect(comparison.previousSets == 8)
        #expect(comparison.change == -0.25)
        #expect(comparison.muscles.map(\.region) == ["quads", "chest", "biceps"])
        #expect(comparison.muscles[0] == MuscleComparison(region: "quads", currentSets: 0, previousSets: 5))
        #expect(comparison.muscles[2] == MuscleComparison(region: "biceps", currentSets: 2, previousSets: 0))
    }

    @Test("Bez prethodnih serija nema postotka, a s jednim razdobljem nema usporedbe")
    func edgeCases() {
        #expect(VolumeComparison(buckets: [VolumeBucket(start: base)]) == nil)
        let comparison = VolumeComparison(buckets: [
            VolumeBucket(start: base.addingTimeInterval(-7 * day)),
            VolumeBucket(start: base, loads: ["chest": MuscleLoad(volumeKg: 100, sets: 1)], totalSets: 1),
        ])
        #expect(comparison?.change == nil)
        #expect(comparison?.muscles.count == 1)
    }
}

@Suite("Tvrde serije i skala")
struct EffectiveSetsTests {
    @Test("Skala tjednih serija i serija jednog treninga")
    func scales() {
        #expect([0, 1, 4.5, 5, 9.5, 10, 20, 20.5].map(LoadScale.weeklyLevel) == [0, 1, 1, 2, 2, 3, 3, 4])
        #expect([0, 0.5, 2.5, 3, 5.5, 6, 9.5, 10].map(LoadScale.sessionLevel) == [0, 1, 1, 2, 2, 3, 3, 4])
        #expect(LoadScale.intensity(level: 2) == 0.5 && LoadScale.intensity(level: 9) == 1)
    }

    @Test("Warm-up i serija s niskim RPE-om nisu tvrde")
    func hardSets() {
        #expect(EffectiveSets.isHard(SetValues(weightKg: 50, reps: 10)))
        #expect(EffectiveSets.isHard(SetValues(weightKg: 50, reps: 10, rpe: 6)))
        #expect(!EffectiveSets.isHard(SetValues(weightKg: 50, reps: 10, rpe: 5.5)))
        #expect(!EffectiveSets.isHard(SetValues(kind: .warmUp, weightKg: 50, reps: 10)))
    }
}

@Suite("Odrađene vježbe")
struct DoneExercisesTests {

    @Test("Samo vježbe iz završenih treninga, bez ponavljanja i abecedno")
    func list() throws {
        let context = try makeContext()
        let engine = WorkoutEngine(context: context)
        let finished = try engine.startSession(name: "A", now: base)
        let squatSet = try engine.addExercise(squat, inputType: .weightReps, to: finished, now: base).orderedSets[0]
        squatSet.weightKg = 100
        squatSet.reps = 5
        try engine.completeSet(squatSet, defaultRestSeconds: 0, now: base)
        let benchSet = try engine.addExercise(bench, inputType: .weightReps, to: finished, now: base).orderedSets[0]
        benchSet.weightKg = 80
        benchSet.reps = 5
        try engine.completeSet(benchSet, defaultRestSeconds: 0, now: base)
        try engine.finishSession(finished, now: base + 3600)

        let active = try engine.startSession(name: "B", now: base + day)
        try engine.addExercise(ExerciseRef(catalogId: "row", name: "Veslanje"), inputType: .weightReps, to: active, now: base + day)

        let done = try DoneExercises.fetch(in: context)
        #expect(done.map(\.name) == ["Čučanj", "Potisak s klupe"])
        #expect(done.first?.ref?.key == squat.key)
    }
}
