import Catalog
import Foundation
import Models
import Planning
import Stats
import SwiftData
import Testing
import Training
import WidgetData
@testable import WidgetSync

/// Petak 15. 1. 2027., 08:00 UTC.
private let base = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400
private let bench = ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
private let row = ExerciseRef(catalogId: "row", name: "Veslanje")

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private func builder(_ context: ModelContext) -> WidgetSnapshotBuilder {
    WidgetSnapshotBuilder(context: context, recordText: { "\($0.value)" })
}

/// Završen trening snage s jednom vježbom.
@discardableResult
private func addSession(_ context: ModelContext, name: String, at date: Date, weight: Double = 100) throws -> Session {
    let session = Session(name: name, kind: .strength, startedAt: date)
    session.state = .finished
    session.endedAt = date.addingTimeInterval(3_600)
    context.insert(session)
    let exercise = SessionExercise(orderIndex: 0, exercise: bench, inputType: .weightReps)
    context.insert(exercise)
    exercise.session = session
    let set = SetLog(orderIndex: 0, kind: .working)
    set.weightKg = weight
    set.reps = 5
    set.completedAt = date.addingTimeInterval(600)
    context.insert(set)
    set.exercise = exercise
    try context.save()
    return session
}

@Suite("Snimka za widgete iz baze")
struct WidgetSnapshotBuilderTests {
    @Test("Prazna baza: bez treninga, težine i rekorda, a tjedan postoji")
    func empty() throws {
        let context = try makeContext()
        let snapshot = try builder(context).make(now: base, calendar: calendar)
        #expect(snapshot.activeWorkout == nil)
        #expect(snapshot.nextWorkout == nil)
        #expect(snapshot.bodyWeight == nil)
        #expect(snapshot.lastWorkout == nil)
        #expect(snapshot.latestRecord == nil)
        #expect(snapshot.week?.sessions == 0)
        #expect(snapshot.week?.days.count == 7)
        #expect(snapshot.accent == AccentChoice.blue.rawValue)
        #expect(snapshot.weightUnit == .kilograms)
    }

    @Test("Sljedeći trening rasporeda s nazivom rasporeda i vježbama")
    func nextWorkout() throws {
        let context = try makeContext()
        let templates = TemplateEngine(context: context)
        let template = try templates.createTemplate(name: "Push")
        try templates.addExercise(bench, inputType: .weightReps, to: template)
        try templates.addExercise(row, inputType: .weightReps, to: template)
        let schedules = ScheduleEngine(context: context)
        let schedule = try schedules.createSchedule(name: "PPL")
        try schedules.addWorkout(template, to: schedule)

        let next = try #require(try builder(context).make(now: base, calendar: calendar).nextWorkout)
        #expect(next.name == "Push")
        #expect(next.scheduleName == "PPL")
        #expect(next.exerciseCount == 2)
        #expect(next.exercises.map(\.name) == [bench.name, row.name])
        let planned = next.exercises.allSatisfy { $0.workingSets > 0 }
        #expect(planned)
    }

    @Test("Tjedan broji treninge prema cilju iz postavki")
    func week() throws {
        let context = try makeContext()
        let settings = try GymQueries(context: context).settings()
        settings.trainingDaysPerWeek = 3
        try context.save()
        try addSession(context, name: "Legs", at: base.addingTimeInterval(-3_600 * 2))
        try addSession(context, name: "Stari", at: base.addingTimeInterval(-14 * day))

        let week = try #require(try builder(context).make(now: base, calendar: calendar).week)
        #expect(week.sessions == 1)
        #expect(week.goal == 3)
        #expect(week.days.filter(\.isTrained).count == 1)
        #expect(week.hardSets == 1)
    }

    @Test("Zadnji trening i najnoviji rekord")
    func lastWorkoutAndRecord() throws {
        let context = try makeContext()
        // Rekordi traže nekoliko treninga povijesti (kalibracija), pa se težina postupno diže.
        for index in 0..<5 {
            try addSession(context, name: "Trening \(index)", at: base.addingTimeInterval(Double(index - 10) * day), weight: 100 + Double(index) * 5)
        }
        let snapshot = try builder(context).make(now: base, calendar: calendar)
        let last = try #require(snapshot.lastWorkout)
        #expect(last.name == "Trening 4")
        #expect(last.durationSeconds == 3_600)
        #expect(last.mix == .strength)
        if let record = snapshot.latestRecord {
            #expect(record.exercise == bench.name)
            #expect(record.date <= base)
        }
    }

    @Test("Težina: zadnja vrijednost, promjena i točke od najstarije")
    func bodyWeight() throws {
        let context = try makeContext()
        let tracking = BodyTracking(context: context)
        try tracking.add(.weight, value: 83, date: base.addingTimeInterval(-40 * day))
        try tracking.add(.weight, value: 82.4, date: base)

        let weight = try #require(try builder(context).make(now: base, calendar: calendar).bodyWeight)
        #expect(weight.latestKg == 82.4)
        #expect(weight.points == [83, 82.4])
        #expect(abs((weight.changeKg ?? 0) + 0.6) < 0.000_1)
    }

    @Test("Trening u tijeku je u snimci")
    func active() throws {
        let context = try makeContext()
        try WorkoutEngine(context: context).startSession(name: "Pull")
        let snapshot = try builder(context).make(now: base, calendar: calendar)
        #expect(snapshot.activeWorkout?.name == "Pull")
    }
}
