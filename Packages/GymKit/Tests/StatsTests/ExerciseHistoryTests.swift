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

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private struct Work {
    let weight: Double
    let reps: Int
    var kind: SetKind = .working
    var completed = true
}

@discardableResult
private func addSession(
    _ context: ModelContext, name: String = "Trening", at date: Date, state: SessionState = .finished,
    lifts: [(ExerciseRef, [Work])], removed: Bool = false
) throws -> Session {
    let session = Session(name: name, startedAt: date)
    session.state = state
    context.insert(session)
    for (index, lift) in lifts.enumerated() {
        let exercise = SessionExercise(orderIndex: index, exercise: lift.0, inputType: .weightReps)
        exercise.isRemoved = removed
        context.insert(exercise)
        exercise.session = session
        for (setIndex, work) in lift.1.enumerated() {
            let set = SetLog(orderIndex: setIndex, kind: work.kind)
            set.weightKg = work.weight
            set.reps = work.reps
            set.completedAt = work.completed ? date.addingTimeInterval(600) : nil
            context.insert(set)
            set.exercise = exercise
        }
    }
    try context.save()
    return session
}

@Suite("Povijest vježbe")
struct ExerciseHistoryTests {

    @Test("Izvođenja od najnovijeg, samo završene radne serije iz završenih treninga")
    func performances() throws {
        let context = try makeContext()
        try addSession(context, name: "Push A", at: base, lifts: [(bench, [
            Work(weight: 40, reps: 10, kind: .warmUp), Work(weight: 80, reps: 8), Work(weight: 80, reps: 7, completed: false)
        ])])
        let later = try addSession(context, name: "Gornji dio", at: base.addingTimeInterval(3 * day), lifts: [
            (squat, [Work(weight: 120, reps: 5)]), (bench, [Work(weight: 82.5, reps: 6), Work(weight: 80, reps: 7)])
        ])
        // Ne broje se: aktivan trening, izbačena vježba, izvođenje samo sa zagrijavanjem.
        try addSession(context, at: base.addingTimeInterval(5 * day), state: .active, lifts: [(bench, [Work(weight: 90, reps: 5)])])
        try addSession(context, at: base.addingTimeInterval(6 * day), lifts: [(bench, [Work(weight: 90, reps: 5)])], removed: true)
        try addSession(context, at: base.addingTimeInterval(7 * day), lifts: [(bench, [Work(weight: 40, reps: 10, kind: .warmUp)])])

        let history = try StatisticsEngine(context: context).history(of: bench)
        #expect(history.count == 2)
        #expect(history.performances.map(\.sessionName) == ["Gornji dio", "Push A"])
        #expect(history.performances[0].sessionId == later.id)
        #expect(history.performances[0].sets.map(\.weightKg) == [82.5, 80])
        #expect(history.performances[1].sets.map(\.reps) == [8])
        #expect(try StatisticsEngine(context: context).history(of: ExerciseRef(catalogId: "row", name: "Veslanje")).isEmpty)
    }

    @Test("Rekord se označi tek nakon kalibracije i samo kad se rekordi prate")
    func records() throws {
        let context = try makeContext()
        for index in 0..<3 {
            try addSession(context, at: base.addingTimeInterval(Double(index) * 2 * day), lifts: [(bench, [Work(weight: 80, reps: 5)])])
        }
        try addSession(context, at: base.addingTimeInterval(6 * day), lifts: [(bench, [Work(weight: 90, reps: 5)])])

        let history = try StatisticsEngine(context: context).history(of: bench)
        #expect(history.performances.map(\.hasRecord) == [true, false, false, false])
        let untracked = try StatisticsEngine(context: context).history(of: bench, recordKinds: [])
        #expect(untracked.performances.allSatisfy { !$0.hasRecord })
    }

    @Test("Istaknute brojke ovise o vrsti unosa")
    func highlights() {
        func performance(_ type: ExerciseInputType, _ sets: [SetValues]) -> ExercisePerformance {
            ExercisePerformance(
                id: UUID(), sessionId: UUID(), sessionName: "", date: base, inputType: type, sets: sets, hasRecord: false
            )
        }
        let strength = ExerciseHistory(performances: [
            performance(.weightReps, [SetValues(weightKg: 100, reps: 5), SetValues(weightKg: 90, reps: 8)])
        ])
        guard case let .heaviest(heaviest) = strength.highlights.first, case let .oneRepMax(oneRepMax) = strength.highlights.last else {
            Issue.record("Očekivane najteža serija i 1RM")
            return
        }
        #expect(heaviest == 100)
        #expect(abs(oneRepMax - 116.6667) < 0.01)

        let bodyweight = ExerciseHistory(performances: [performance(.bodyweight, [SetValues(reps: 12), SetValues(reps: 15)])])
        #expect(bodyweight.highlights == [.mostReps(15)])

        let cardio = ExerciseHistory(performances: [
            performance(.durationDistance, [SetValues(durationSeconds: 1800, distanceMeters: 5000)])
        ])
        #expect(cardio.highlights == [.longestDistance(5000), .longestDuration(1800)])
        #expect(ExerciseHistory(performances: []).highlights.isEmpty)
    }

    @Test("Izvođenja po mjesecima")
    func byMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let dates = [base.addingTimeInterval(20 * day), base.addingTimeInterval(day), base, base.addingTimeInterval(-20 * day)]
        let history = ExerciseHistory(performances: dates.map {
            ExercisePerformance(id: UUID(), sessionId: UUID(), sessionName: "", date: $0, inputType: .weightReps, sets: [], hasRecord: false)
        })
        let months = history.byMonth(calendar: calendar)
        // 15. 1. 2027.: veljača, siječanj (dva), prosinac.
        #expect(months.map(\.performances.count) == [1, 2, 1])
        #expect(calendar.component(.month, from: months[0].start) == 2)
        #expect(calendar.component(.month, from: months[2].start) == 12)
    }

    @Test("Točka napretka: težina i ponavljanja iz iste serije")
    func progressBestSet() throws {
        let context = try makeContext()
        try addSession(context, at: base, lifts: [(bench, [
            Work(weight: 85, reps: 5), Work(weight: 85, reps: 4), Work(weight: 80, reps: 7)
        ])])
        let point = try #require(try StatisticsEngine(context: context).progress(of: bench).first)
        #expect(point.bestWeightKg == 85)
        #expect(point.bestReps == 5)
    }
}
