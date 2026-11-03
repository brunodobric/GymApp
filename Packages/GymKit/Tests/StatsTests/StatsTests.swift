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
        #expect(weeks[0].loads[.chest] == MuscleLoad(volumeKg: 450, sets: 1))
        #expect(weeks[1].loads[.chest] == MuscleLoad(volumeKg: 900, sets: 2))
        #expect(weeks[1].loads[.quadriceps] == MuscleLoad(volumeKg: 600, sets: 1))
        #expect(weeks[1].totalVolumeKg == 1500)
        // Sekundarni mišići ne ulaze u volumen.
        #expect(weeks[1].loads[.triceps] == nil)

        let months = try engine.volumeBuckets(size: .month, count: 3, endingAt: base, calendar: calendar, info: infoProvider)
        #expect(months.count == 3)
        #expect(months[2].loads[.chest]?.sets == 3)
        #expect(months[0].loads[.chest]?.sets == 1)
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

    @Test("Heatmap: primarne regije puni volumen, sekundarne pola, intenzitet prema najopterećenijoj")
    func heatmap() throws {
        let context = try makeContext()
        try addSession(context, at: base, lifts: [Lift(ref: bench, sets: [Work(weight: 100, reps: 5)])])
        try addSession(context, at: base.addingTimeInterval(day), lifts: [
            Lift(ref: bench, sets: [Work(weight: 100, reps: 5)]),
            Lift(ref: squat, sets: [Work(weight: 100, reps: 5)]),
        ])

        let result = try StatisticsEngine(context: context).heatmap(
            from: base.addingTimeInterval(-day), until: base.addingTimeInterval(3 * day), info: infoProvider
        )
        #expect(result["chest"] == RegionLoad(sessions: 2, volumeKg: 1000, intensity: 1))
        #expect(result["triceps"]?.volumeKg == 500)
        #expect(result["quads"]?.sessions == 1 && result["quads"]?.intensity == 0.5)
        #expect(result["glutes"]?.volumeKg == 250)
        #expect(result["lats"] == nil)
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
        // Gornja granica je namjerno široka da CI ne bude nestabilan; cilj na uređaju je ispod 0,5 s.
        #expect(elapsed < 3, "Statistika je trajala \(elapsed) s")
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

    @Test func everyMuscleHasKnownRegion() {
        for muscle in Muscle.allCases {
            #expect(BodyRegion.all.contains(BodyRegion.region(for: muscle)))
        }
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
