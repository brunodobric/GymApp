import Catalog
import Foundation
import Models
import SwiftData
import Testing
import Training
@testable import Stats

private let press = ExerciseRef(catalogId: "press", name: "Potisak s klupe")
private let treadmill = ExerciseRef(catalogId: "treadmill", name: "Traka za trčanje")
private let bike = ExerciseRef(catalogId: "bike", name: "Sobni bicikl")
/// Petak 15. 1. 2027., 08:00 UTC.
private let start = Date(timeIntervalSince1970: 1_800_000_000)

private let info: ExerciseInfoProvider = { key in
    switch key {
    case "c:press":
        ExerciseInfo(primary: [.chest], primaryRegions: ["chest"])
    case "c:treadmill", "c:bike":
        ExerciseInfo(primary: [.quadriceps], primaryRegions: ["quads"], isCardio: true)
    default:
        nil
    }
}

private let isCardio = ExerciseInfoBuilder.isCardio(info)

private struct Entry {
    let ref: ExerciseRef
    var inputType: ExerciseInputType = .weightReps
    var weight: Double?
    var reps: Int?
    var seconds: Int?
    var meters: Double?
    var completed = true
}

private func makeSession(
    _ context: ModelContext, kind: WorkoutKind = .strength, _ entries: [Entry]
) throws -> Session {
    let session = Session(name: "Trening", kind: kind, startedAt: start)
    session.state = .finished
    session.endedAt = start.addingTimeInterval(3600)
    context.insert(session)
    for (index, entry) in entries.enumerated() {
        let exercise = SessionExercise(orderIndex: index, exercise: entry.ref, inputType: entry.inputType)
        context.insert(exercise)
        exercise.session = session
        let set = SetLog(orderIndex: 0)
        set.weightKg = entry.weight
        set.reps = entry.reps
        set.durationSeconds = entry.seconds
        set.distanceMeters = entry.meters
        set.completedAt = entry.completed ? start.addingTimeInterval(600) : nil
        context.insert(set)
        set.exercise = exercise
    }
    try context.save()
    return session
}

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private let lift = Entry(ref: press, weight: 100, reps: 5)
private let run = Entry(ref: treadmill, inputType: .durationDistance, seconds: 900, meters: 2500)

@Suite("Kardio u treningu snage")
struct SessionCardioTests {

    @Test("Vrsta za prikaz: snaga, kardio i mješoviti trening")
    func mix() throws {
        let context = try makeContext()
        #expect(SessionCardio.mix(of: try makeSession(context, [lift]), isCardio: isCardio) == .strength)
        #expect(SessionCardio.mix(of: try makeSession(context, [lift, run]), isCardio: isCardio) == .mixed)
        // Samo kardio vježbe u predlošku snage: prikazuje se kao kardio.
        #expect(SessionCardio.mix(of: try makeSession(context, [run]), isCardio: isCardio) == .cardio)
        // Kardio trening iz plana ili Zdravlja ostaje kardio.
        #expect(SessionCardio.mix(of: try makeSession(context, kind: .cardio, []), isCardio: isCardio) == .cardio)
        // Kardio vježba bez odrađene serije ne mijenja vrstu.
        var skipped = run
        skipped.completed = false
        #expect(SessionCardio.mix(of: try makeSession(context, [lift, skipped]), isCardio: isCardio) == .strength)
    }

    @Test("Mješoviti trening je u filteru i pod snagom i pod kardiom")
    func filterKinds() throws {
        let context = try makeContext()
        let mixed = try makeSession(context, [lift, run])
        let strength = try makeSession(context, [lift])
        let kindsOf: (Session) -> Set<WorkoutKind> = { SessionCardio.mix(of: $0, isCardio: isCardio).kinds }
        let cardioOnly = HistoryFilter(kinds: [.cardio]).apply(to: [mixed, strength], kindsOf: kindsOf)
        #expect(cardioOnly.map(\.id) == [mixed.id])
        let strengthOnly = HistoryFilter(kinds: [.strength]).apply(to: [mixed, strength], kindsOf: kindsOf)
        #expect(Set(strengthOnly.map(\.id)) == [mixed.id, strength.id])
    }

    @Test("Kardio dio: zbroj vremena i udaljenosti odrađenih kardio serija")
    func part() throws {
        let context = try makeContext()
        let cycling = Entry(ref: bike, inputType: .duration, seconds: 600)
        let session = try makeSession(context, [cycling, lift, run])
        #expect(SessionCardio.part(of: session, isCardio: isCardio) == CardioPart(seconds: 1500, meters: 2500))
        #expect(SessionCardio.part(of: try makeSession(context, [cycling]), isCardio: isCardio) == CardioPart(seconds: 600))
        #expect(SessionCardio.part(of: try makeSession(context, [lift]), isCardio: isCardio) == nil)
    }

    @Test("Kardio vježbe se ne broje u serije po mišiću")
    func notCountedAsSets() throws {
        let context = try makeContext()
        let session = try makeSession(context, [lift, run])
        let regions = SessionRegions.sets(in: session, info: info)
        #expect(regions.map(\.region) == ["chest"])

        let engine = StatisticsEngine(context: context)
        let week = try engine.volumeBuckets(size: .week, count: 1, endingAt: start, info: info)
        #expect(week.last?.totalSets == 1)
        #expect(week.last?.loads["quads"] == nil)
        let heatmap = try engine.heatmap(from: start.addingTimeInterval(-86_400), until: start.addingTimeInterval(86_400), info: info)
        #expect(heatmap["quads"] == nil)
        #expect(heatmap["chest"]?.sets == 1)
    }

    @Test("Sažetak treninga: kardio nije tvrda serija, a ima svoj dio")
    func summary() throws {
        let context = try makeContext()
        let session = try makeSession(context, [lift, run])
        let summary = try WorkoutEngine(context: context).summary(of: session, trackedKinds: [], isCardio: isCardio)
        #expect(summary.completedSets == 2)
        #expect(summary.hardSets == 1)
        #expect(summary.cardio == CardioPart(seconds: 900, meters: 2500))
    }

    @Test("Usporedba s prošlim treningom: kardio nije serija, a vrijeme i udaljenost se uspoređuju")
    func comparison() throws {
        let context = try makeContext()
        let template = UUID()
        let previous = try makeSession(context, [Entry(ref: treadmill, inputType: .durationDistance, seconds: 1200, meters: 3000)])
        previous.templateId = template
        previous.startedAt = start.addingTimeInterval(-7 * 86_400)
        previous.endedAt = previous.startedAt.addingTimeInterval(1800)
        let current = try makeSession(context, [run])
        current.templateId = template
        try context.save()

        let result = try #require(try StatisticsEngine(context: context).comparison(of: current, isCardio: isCardio))
        #expect(result.hardSets == 0 && result.previousHardSets == 0)
        #expect(result.cardio == CardioPart(seconds: 900, meters: 2500))
        #expect(result.previousCardio == CardioPart(seconds: 1200, meters: 3000))
    }

    @Test("Kardio dio postoji i za trening sa samo kardio vježbama")
    func cardioOnlyPart() throws {
        let context = try makeContext()
        let session = try makeSession(context, [run])
        let summary = try WorkoutEngine(context: context).summary(of: session, trackedKinds: [], isCardio: isCardio)
        #expect(summary.hardSets == 0 && summary.totalVolumeKg == 0)
        #expect(summary.cardio == CardioPart(seconds: 900, meters: 2500))
    }

    @Test("Vrsta predloška iz vježbi; kardio plan za sat ostaje kardio")
    func templateMix() throws {
        let context = try makeContext()
        func template(_ refs: [ExerciseRef], kind: WorkoutKind = .strength) throws -> WorkoutTemplate {
            let template = WorkoutTemplate(name: "Trening", kind: kind)
            context.insert(template)
            for (index, ref) in refs.enumerated() {
                let exercise = TemplateExercise(orderIndex: index, exercise: ref)
                context.insert(exercise)
                exercise.template = template
            }
            try context.save()
            return template
        }
        #expect(SessionCardio.mix(of: try template([press]), isCardio: isCardio) == .strength)
        #expect(SessionCardio.mix(of: try template([press, bike]), isCardio: isCardio) == .mixed)
        #expect(SessionCardio.mix(of: try template([treadmill, bike]), isCardio: isCardio) == .cardio)
        #expect(SessionCardio.mix(of: try template([]), isCardio: isCardio) == .strength)
        #expect(SessionCardio.mix(of: try template([], kind: .cardio), isCardio: isCardio) == .cardio)
    }

    @Test("Vlastita vježba u kategoriji kardio je kardio")
    func customCardio() throws {
        let context = try makeContext()
        let custom = CustomExercise(name: "Veslanje u parku")
        custom.category = .cardio
        context.insert(custom)
        let provider = ExerciseInfoBuilder.provider(catalog: nil, custom: [custom])
        #expect(provider("u:\(custom.id.uuidString)")?.isCardio == true)
    }
}
