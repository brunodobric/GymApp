import Catalog
import Foundation
import Models
import SwiftData
import Training

/// Jedno izvođenje vježbe u završenom treningu, za povijest na detalju vježbe.
public struct ExercisePerformance: Identifiable, Equatable, Sendable {
    /// Id vježbe u treningu (`SessionExercise.id`): ista vježba može biti dvaput u istom treningu.
    public let id: UUID
    public let sessionId: UUID
    public let sessionName: String
    public let date: Date
    public let inputType: ExerciseInputType
    /// Završene radne serije redom, bez zagrijavanja.
    public let sets: [SetValues]
    /// Je li u ovom izvođenju postavljen rekord koji ide u sažetak treninga.
    public let hasRecord: Bool

    public init(
        id: UUID, sessionId: UUID, sessionName: String, date: Date, inputType: ExerciseInputType,
        sets: [SetValues], hasRecord: Bool
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.date = date
        self.inputType = inputType
        self.sets = sets
        self.hasRecord = hasRecord
    }
}

/// Istaknuta brojka iz povijesti vježbe, ovisno o vrsti unosa.
public enum ExerciseHistoryHighlight: Equatable, Sendable {
    /// Najteža serija (kg); uz vlastitu težinu to je dodatni teret.
    case heaviest(Double)
    /// Najbolja pouzdana procjena 1RM (kg).
    case oneRepMax(Double)
    case mostReps(Int)
    case longestDuration(Int)
    case longestDistance(Double)
}

/// Sva izvođenja jedne vježbe, od najnovijeg.
public struct ExerciseHistory: Equatable, Sendable {
    public let performances: [ExercisePerformance]

    public init(performances: [ExercisePerformance]) {
        self.performances = performances
    }

    public var isEmpty: Bool { performances.isEmpty }
    public var count: Int { performances.count }

    /// Najviše dvije brojke uz broj izvođenja. Vrsta unosa je ona iz zadnjeg izvođenja, a gledaju se samo
    /// izvođenja s istom vrstom (vlastitoj vježbi se vrsta unosa može promijeniti).
    public var highlights: [ExerciseHistoryHighlight] {
        guard let type = performances.first?.inputType else { return [] }
        let sets = performances.filter { $0.inputType == type }.flatMap(\.sets)
        var result: [ExerciseHistoryHighlight] = []
        switch type {
        case .weightReps, .weightedBodyweight:
            let heaviest = sets.compactMap { SetMetrics.load($0, inputType: type) }.max() ?? 0
            if heaviest > 0 { result.append(.heaviest(heaviest)) }
            if let oneRepMax = sets.compactMap({ SetMetrics.strengthEstimate($0, inputType: type) }).max() {
                result.append(.oneRepMax(oneRepMax))
            }
        case .bodyweight, .assisted:
            let reps = sets.compactMap(\.reps).max() ?? 0
            if reps > 0 { result.append(.mostReps(reps)) }
        case .duration:
            let seconds = sets.compactMap(\.durationSeconds).max() ?? 0
            if seconds > 0 { result.append(.longestDuration(seconds)) }
        case .durationDistance:
            let meters = sets.compactMap(\.distanceMeters).max() ?? 0
            if meters > 0 { result.append(.longestDistance(meters)) }
            let seconds = sets.compactMap(\.durationSeconds).max() ?? 0
            if seconds > 0 { result.append(.longestDuration(seconds)) }
        }
        return result
    }

    /// Izvođenja po mjesecima, od najnovijeg.
    public func byMonth(calendar: Calendar = .current) -> [ExerciseHistoryMonth] {
        var result: [ExerciseHistoryMonth] = []
        for performance in performances {
            let start = calendar.dateInterval(of: .month, for: performance.date)?.start ?? performance.date
            if let last = result.indices.last, result[last].start == start {
                result[last].performances.append(performance)
            } else {
                result.append(ExerciseHistoryMonth(start: start, performances: [performance]))
            }
        }
        return result
    }
}

/// Izvođenja jednog mjeseca. `start` je početak mjeseca.
public struct ExerciseHistoryMonth: Identifiable, Equatable, Sendable {
    public let start: Date
    public var performances: [ExercisePerformance]
    public var id: Date { start }
}

extension StatisticsEngine {
    /// Povijest vježbe iz završenih treninga. Izvođenja bez završene radne serije se ne broje.
    /// Rekordi se traže kao u `personalRecords`; prazan `recordKinds` znači bez oznake rekorda.
    public func history(of ref: ExerciseRef, recordKinds: Set<PRKind> = Set(PRKind.allCases)) throws -> ExerciseHistory {
        let key = ref.key
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false }
        )
        let done = try context.fetch(descriptor).compactMap { exercise -> (SessionExercise, Session)? in
            guard let session = exercise.session, session.state == .finished else { return nil }
            return (exercise, session)
        }
        .sorted { lhs, rhs in
            lhs.1.startedAt == rhs.1.startedAt ? lhs.0.orderIndex < rhs.0.orderIndex : lhs.1.startedAt < rhs.1.startedAt
        }

        var past = RecordHistory()
        var performances: [ExercisePerformance] = []
        for (exercise, session) in done {
            let completed = exercise.orderedSets.filter(\.isCompleted).map(\.values)
            let working = completed.filter { $0.kind == .working }
            guard !working.isEmpty else { continue }
            let records = recordKinds.isEmpty ? [] : PersonalRecordDetector.records(
                current: completed, history: past, inputType: exercise.inputType, kinds: recordKinds, date: session.startedAt
            )
            past.add(completed, inputType: exercise.inputType, date: session.startedAt)
            performances.append(ExercisePerformance(
                id: exercise.id, sessionId: session.id, sessionName: session.name, date: session.startedAt,
                inputType: exercise.inputType, sets: working, hasRecord: records.contains(where: \.showsInSummary)
            ))
        }
        return ExerciseHistory(performances: performances.reversed())
    }
}
