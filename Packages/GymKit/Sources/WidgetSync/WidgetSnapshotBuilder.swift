import Connectivity
import Foundation
import Models
import Stats
import SwiftData
import Training
import WidgetData

/// Slaže snimku za widgete (`WidgetSnapshot`) iz baze: trening u tijeku, sljedeći trening, tekući tjedan,
/// tjelesnu težinu, zadnji trening i najnoviji rekord. Isti podaci kao kartice na Početnoj.
///
/// Što ovisi o katalogu i jeziku daje aplikacija: je li vježba kardio ili višezglobna i tekst rekorda.
public struct WidgetSnapshotBuilder {
    public let context: ModelContext
    public var isCardio: (String) -> Bool
    public var isCompound: (String) -> Bool?
    /// Vrijednost rekorda za prikaz, npr. "120 kg × 5".
    public var recordText: (PersonalRecord) -> String

    /// Koliko se zadnjih treninga gleda za najnoviji rekord (sažetak treninga računa rekorde iz povijesti).
    public static let recordLookback = 5

    public init(
        context: ModelContext, isCardio: @escaping (String) -> Bool = { _ in false },
        isCompound: @escaping (String) -> Bool? = { _ in nil },
        recordText: @escaping (PersonalRecord) -> String
    ) {
        self.context = context
        self.isCardio = isCardio
        self.isCompound = isCompound
        self.recordText = recordText
    }

    public func make(now: Date = Date(), calendar: Calendar = .current) throws -> WidgetSnapshot {
        let settings = try GymQueries(context: context).settings()
        var snapshot = WidgetSnapshot(generatedAt: now, accent: settings.accent.rawValue, weightUnit: settings.weightUnit)
        if let active = try GymQueries(context: context).activeSession() {
            snapshot.activeWorkout = .init(name: active.name, startedAt: active.startedAt)
        }
        snapshot.nextWorkout = try WatchContextBuilder(context: context).nextWorkout().map(Self.nextWorkout)
        let progress = try StatisticsEngine(context: context)
            .weekProgress(now: now, goal: settings.trainingDaysPerWeek, calendar: calendar, isCardio: isCardio)
        snapshot.week = Self.week(progress)
        snapshot.bodyWeight = try bodyWeight()
        try addRecentSessions(to: &snapshot, settings: settings)
        return snapshot
    }

    // MARK: Dijelovi

    static func nextWorkout(_ payload: PlannedWorkoutPayload) -> WidgetSnapshot.NextWorkout {
        let exercises = payload.exercises.prefix(WidgetSnapshot.NextWorkout.maxExercises).map { exercise in
            let working = exercise.sets.filter { $0.kind == .working }
            let first = working.first
            return WidgetSnapshot.PlannedExercise(
                name: exercise.exercise.name, workingSets: working.count, reps: first?.reps,
                weightKg: first?.weightKg ?? first?.extraWeightKg, durationSeconds: first?.durationSeconds
            )
        }
        return WidgetSnapshot.NextWorkout(
            name: payload.name, scheduleName: payload.scheduleName, exerciseCount: payload.exercises.count, exercises: Array(exercises)
        )
    }

    static func week(_ progress: WeekProgress) -> WidgetSnapshot.Week {
        WidgetSnapshot.Week(
            start: progress.start,
            days: progress.days.map { WidgetSnapshot.Week.Day(date: $0.date, strength: $0.strength, cardio: $0.cardio) },
            sessions: progress.sessions, goal: progress.goal, streakWeeks: progress.streakWeeks,
            hardSets: progress.hardSets, cardioSeconds: progress.cardioSeconds, totalSeconds: Int(progress.totalSeconds)
        )
    }

    static func mix(_ mix: SessionMix) -> WidgetSnapshot.Mix {
        switch mix {
        case .strength: .strength
        case .cardio: .cardio
        case .mixed: .mixed
        }
    }

    private func bodyWeight() throws -> WidgetSnapshot.BodyWeight? {
        let tracking = BodyTracking(context: context)
        let all = try tracking.measurements(of: .weight)
        guard let latest = all.last else { return nil }
        return WidgetSnapshot.BodyWeight(
            latestKg: latest.value, date: latest.date, changeKg: try tracking.recentChange(of: .weight),
            points: all.suffix(WidgetSnapshot.BodyWeight.maxPoints).map(\.value)
        )
    }

    /// Zadnji trening (i iz Zdravlja) i najnoviji rekord iz zadnjih vlastitih treninga.
    private func addRecentSessions(to snapshot: inout WidgetSnapshot, settings: UserSettings) throws {
        let finished = SessionState.finished.rawValue
        var ownDescriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == finished },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        ownDescriptor.fetchLimit = Self.recordLookback
        let own = try context.fetch(ownDescriptor).filter { !$0.isImportedFromWorkoutsApp }
        var healthDescriptor = FetchDescriptor<HealthWorkout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        healthDescriptor.fetchLimit = 1
        let health = try context.fetch(healthDescriptor)

        let engine = WorkoutEngine(context: context)
        let trackedKinds = PRKind.tracked(by: settings)
        var summaries: [UUID: WorkoutSummary] = [:]
        func summary(of session: Session) -> WorkoutSummary? {
            if let cached = summaries[session.id] { return cached }
            let result = try? engine.summary(
                of: session, trackedKinds: trackedKinds, excludedExercises: settings.prExcludedExerciseKeys,
                isCompound: isCompound, isCardio: isCardio
            )
            summaries[session.id] = result
            return result
        }

        if let last = Session.merged(Array(own.prefix(1)), health: health).first {
            let lastSummary = last.isImportedFromWorkoutsApp ? nil : summary(of: last)
            snapshot.lastWorkout = WidgetSnapshot.LastWorkout(
                name: last.name, startedAt: last.startedAt,
                durationSeconds: last.endedAt.map { Int(max(0, $0.timeIntervalSince(last.startedAt))) },
                mix: Self.mix(SessionCardio.mix(of: last, isCardio: isCardio)),
                hardSets: lastSummary?.hardSets ?? 0,
                highlights: (lastSummary?.highlights ?? []).map { .init(exercise: $0.exerciseName, value: recordText($0.record)) }
            )
        }
        for session in own {
            guard let highlight = summary(of: session)?.highlights.first else { continue }
            snapshot.latestRecord = WidgetSnapshot.Record(
                exercise: highlight.exerciseName, value: recordText(highlight.record), date: session.startedAt
            )
            break
        }
    }
}
