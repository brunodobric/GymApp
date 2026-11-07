import Catalog
import Foundation
import Models
import SwiftData
import Training

/// Usporedba treninga s prošlim izvođenjem istog treninga (isti predložak). Tonaža ovdje ima smisla,
/// jer se isti trening uspoređuje sam sa sobom.
public struct SessionComparison: Equatable, Sendable {
    public let previousDate: Date
    public let hardSets: Int
    public let previousHardSets: Int
    public let volumeKg: Double
    public let previousVolumeKg: Double
    public let durationSeconds: TimeInterval?
    public let previousDurationSeconds: TimeInterval?

    /// Relativna promjena tonaže (0,04 = +4 %). Nil kad prošli put nije bilo tonaže.
    public var volumeChange: Double? {
        previousVolumeKg > 0 ? volumeKg / previousVolumeKg - 1 : nil
    }
}

/// Rezultat jedne vježbe u treningu: najbolja serija i procjena 1RM uz promjenu prema prošlom izvođenju.
public struct ExerciseResult: Equatable, Sendable, Identifiable {
    public let key: String
    public let name: String
    public let inputType: ExerciseInputType
    public let bestSet: SetValues?
    public let oneRepMaxKg: Double?
    public let previousOneRepMaxKg: Double?
    public let hardSets: Int
    /// Medijan odmora između serija (sekunde), iz vremena označavanja serija.
    public let restSeconds: TimeInterval?

    public var id: String { key }

    /// Relativna promjena procjene 1RM prema prošlom izvođenju.
    public var change: Double? {
        guard let oneRepMaxKg, let previousOneRepMaxKg, previousOneRepMaxKg > 0 else { return nil }
        return oneRepMaxKg / previousOneRepMaxKg - 1
    }
}

public enum SessionMetrics {
    /// Odmor dulji od ovoga je stanka (npr. promjena sprave), ne odmor između serija.
    public static let maximumRest: TimeInterval = 15 * 60

    /// Medijan razmaka između uzastopnih završenih serija. Nil za manje od dvije serije.
    public static func medianRest(_ completions: [Date]) -> TimeInterval? {
        let sorted = completions.sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) }.filter { $0 > 0 && $0 <= maximumRest }
        return TrendAnalysis.median(gaps)
    }

    /// Najbolja serija za prikaz: najveća pouzdana procjena 1RM, inače najveći volumen, ponavljanja,
    /// trajanje ili udaljenost.
    public static func bestSet(_ sets: [SetValues], inputType: ExerciseInputType) -> SetValues? {
        let working = sets.filter { $0.kind == .working }
        if let best = working.max(by: {
            (SetMetrics.strengthEstimate($0, inputType: inputType) ?? 0) < (SetMetrics.strengthEstimate($1, inputType: inputType) ?? 0)
        }), SetMetrics.strengthEstimate(best, inputType: inputType) != nil {
            return best
        }
        switch inputType {
        case .weightReps, .weightedBodyweight:
            return working.max { SetMetrics.volume($0, inputType: inputType) < SetMetrics.volume($1, inputType: inputType) }
        case .bodyweight:
            return working.max { ($0.reps ?? 0) < ($1.reps ?? 0) }
        case .assisted:
            return working.min { ($0.extraWeightKg ?? 0) < ($1.extraWeightKg ?? 0) }
        case .duration:
            return working.max { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }
        case .durationDistance:
            return working.max { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
        }
    }
}

extension StatisticsEngine {

    /// Usporedba s prethodnim završenim treningom istog predloška. Nil bez predloška ili bez ranijeg treninga.
    public func comparison(of session: Session) throws -> SessionComparison? {
        guard session.templateId != nil else { return nil }
        let templateId: UUID? = session.templateId
        let finished = SessionState.finished.rawValue
        let started = session.startedAt
        let currentId = session.id
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate {
                $0.templateId == templateId && $0.stateRaw == finished && $0.startedAt < started && $0.id != currentId
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let previous = try context.fetch(descriptor).first else { return nil }
        let now = totals(of: session)
        let before = totals(of: previous)
        return SessionComparison(
            previousDate: previous.startedAt, hardSets: now.hardSets, previousHardSets: before.hardSets,
            volumeKg: now.volume, previousVolumeKg: before.volume,
            durationSeconds: session.endedAt.map { $0.timeIntervalSince(session.startedAt) },
            previousDurationSeconds: previous.endedAt.map { $0.timeIntervalSince(previous.startedAt) }
        )
    }

    private func totals(of session: Session) -> (hardSets: Int, volume: Double) {
        var hard = 0
        var volume = 0.0
        for exercise in session.orderedExercises where !exercise.isRemoved {
            let done = exercise.orderedSets.filter(\.isCompleted).map(\.values)
            hard += done.filter(SetMetrics.isHard).count
            volume += done.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }
        }
        return (hard, volume)
    }

    /// Rezultat svake vježbe treninga s promjenom prema prošlom izvođenju te vježbe (prije ovog treninga).
    public func exerciseResults(
        of session: Session, formula: SetMetrics.OneRepMaxFormula = .epley
    ) throws -> [ExerciseResult] {
        try session.orderedExercises.filter { !$0.isRemoved }.compactMap { exercise -> ExerciseResult? in
            let completed = exercise.orderedSets.filter(\.isCompleted)
            let done = completed.map(\.values)
            guard done.contains(where: { $0.kind == .working }) else { return nil }
            let type = exercise.inputType
            let oneRepMax = done.compactMap { SetMetrics.strengthEstimate($0, inputType: type, formula: formula) }.max()
            let previous = try previousPerformance(of: exercise.exerciseKey, before: session)
            let previousOneRepMax = previous?.orderedSets.filter(\.isCompleted).map(\.values)
                .compactMap { SetMetrics.strengthEstimate($0, inputType: previous?.inputType ?? type, formula: formula) }.max()
            return ExerciseResult(
                key: exercise.exerciseKey, name: exercise.exerciseName, inputType: type,
                bestSet: SessionMetrics.bestSet(done, inputType: type), oneRepMaxKg: oneRepMax,
                previousOneRepMaxKg: previousOneRepMax, hardSets: done.filter(SetMetrics.isHard).count,
                restSeconds: SessionMetrics.medianRest(completed.compactMap(\.completedAt))
            )
        }
    }

    /// Zadnje izvođenje vježbe u završenom treningu prije `session`.
    private func previousPerformance(of key: String, before session: Session) throws -> SessionExercise? {
        guard !key.isEmpty else { return nil }
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false }
        )
        return try context.fetch(descriptor)
            .filter { exercise in
                guard let owner = exercise.session else { return false }
                return owner.state == .finished && owner.id != session.id && owner.startedAt < session.startedAt
            }
            .max { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }
}
