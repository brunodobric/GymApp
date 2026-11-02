import Catalog
import Foundation
import Models
import SwiftData

public enum WorkoutError: Error, Equatable {
    /// Već postoji trening u tijeku.
    case alreadyActive
    /// Serija nema sve potrebne vrijednosti za svoju vrstu unosa.
    case setIncomplete
    /// Trening nema nijednu završenu seriju.
    case nothingCompleted
    case needsTwoExercises
}

public struct WorkoutSummary: Equatable, Sendable {
    public struct ExerciseRecords: Equatable, Sendable {
        public let exerciseName: String
        public let records: [PersonalRecord]
    }

    public let durationSeconds: TimeInterval
    public let totalVolumeKg: Double
    public let completedSets: Int
    public let records: [ExerciseRecords]
}

/// Operacije nad aktivnim treningom. Svaka promjena odmah se sprema (specifikacija: oporavak prekinutog treninga),
/// pa gašenje aplikacije usred treninga ne gubi ništa.
public struct WorkoutEngine {
    public let context: ModelContext

    /// Broj radnih serija koje se stvaraju za vježbu bez povijesti.
    public static let defaultWorkingSets = 3

    public init(context: ModelContext) {
        self.context = context
    }

    private var queries: GymQueries { GymQueries(context: context) }

    // MARK: Trening

    @discardableResult
    public func startSession(
        name: String,
        kind: WorkoutKind = .strength,
        device: DeviceRole = .phone,
        templateId: UUID? = nil,
        scheduleId: UUID? = nil,
        now: Date = Date()
    ) throws -> Session {
        if try queries.activeSession() != nil { throw WorkoutError.alreadyActive }
        let session = Session(name: name, kind: kind, startedAt: now)
        session.controllingDevice = device
        session.templateId = templateId
        session.scheduleId = scheduleId
        session.lastActivityAt = now
        context.insert(session)
        try context.save()
        return session
    }

    /// Zatvara trening: briše nezavršene serije, prazne i izbačene vježbe. Trening bez ijedne završene serije
    /// ne može se spremiti (nudi se odbacivanje).
    public func finishSession(_ session: Session, notes: String? = nil, now: Date = Date()) throws {
        let hasCompleted = (session.exercises ?? []).contains { exercise in
            !exercise.isRemoved && (exercise.sets ?? []).contains { $0.isCompleted }
        }
        guard hasCompleted else { throw WorkoutError.nothingCompleted }

        for exercise in session.exercises ?? [] {
            if exercise.isRemoved {
                context.delete(exercise)
                continue
            }
            for set in exercise.sets ?? [] where !set.isCompleted {
                context.delete(set)
            }
            if (exercise.sets ?? []).allSatisfy({ !$0.isCompleted }) {
                context.delete(exercise)
            }
        }
        if let notes { session.notes = notes }
        session.state = .finished
        session.endedAt = now
        session.restTimerStartedAt = nil
        session.restTimerEndsAt = nil
        session.lastActivityAt = now
        try context.save()
    }

    /// Odbacivanje briše trening u cijelosti (i njegove vježbe i serije).
    public func discardSession(_ session: Session) throws {
        context.delete(session)
        try context.save()
    }

    /// Zatvara zaboravljeni trening na predloženi kraj (zadnja završena serija).
    public func closeStaleSession(_ session: Session) throws {
        let lastCompleted = lastCompletedSetAt(in: session)
        let assessment = RecoveryAssessment.assess(
            startedAt: session.startedAt, lastActivityAt: session.lastActivityAt,
            lastCompletedSetAt: lastCompleted, now: Date()
        )
        try finishSession(session, now: assessment.suggestedEnd)
    }

    public func lastCompletedSetAt(in session: Session) -> Date? {
        (session.exercises ?? []).flatMap { $0.sets ?? [] }.compactMap(\.completedAt).max()
    }

    // MARK: Vježbe

    /// Dodaje vježbu i stvara serije prema zadnjem izvođenju (isti broj warm-up i radnih serija
    /// s pretpunjenim vrijednostima), a bez povijesti tri prazne radne serije.
    @discardableResult
    public func addExercise(
        _ ref: ExerciseRef,
        inputType: ExerciseInputType,
        to session: Session,
        restSeconds: Int? = nil,
        now: Date = Date()
    ) throws -> SessionExercise {
        let order = ((session.exercises ?? []).map(\.orderIndex).max() ?? -1) + 1
        let exercise = SessionExercise(orderIndex: order, exercise: ref, inputType: inputType)
        exercise.restSeconds = restSeconds
        context.insert(exercise)
        exercise.session = session

        let previous = try previousSets(of: ref, before: session)
        let warmUps = previous.filter { $0.kind == .warmUp }.count
        let working = previous.filter { $0.kind == .working }.count
        for _ in 0..<warmUps { try appendSet(to: exercise, kind: .warmUp, previous: previous) }
        for _ in 0..<(working > 0 ? working : Self.defaultWorkingSets) {
            try appendSet(to: exercise, kind: .working, previous: previous)
        }
        try touch(session, now: now)
        return exercise
    }

    @discardableResult
    public func addSet(to exercise: SessionExercise, kind: SetKind = .working, now: Date = Date()) throws -> SetLog {
        let previous = try previousSets(of: exercise.exercise, before: exercise.session)
        let set = try appendSet(to: exercise, kind: kind, previous: previous)
        if let session = exercise.session { try touch(session, now: now) }
        return set
    }

    public func removeSet(_ set: SetLog, now: Date = Date()) throws {
        let session = set.exercise?.session
        context.delete(set)
        if let exercise = set.exercise {
            for (index, remaining) in exercise.orderedSets.filter({ $0.id != set.id }).enumerated() {
                remaining.orderIndex = index
            }
        }
        if let session { try touch(session, now: now) } else { try context.save() }
    }

    /// Izbacivanje se može poništiti do kraja treninga (`restoreExercise`).
    public func removeExercise(_ exercise: SessionExercise, now: Date = Date()) throws {
        exercise.isRemoved = true
        if let session = exercise.session { try touch(session, now: now) }
    }

    public func restoreExercise(_ exercise: SessionExercise, now: Date = Date()) throws {
        exercise.isRemoved = false
        if let session = exercise.session {
            exercise.orderIndex = ((session.exercises ?? []).map(\.orderIndex).max() ?? -1) + 1
            try touch(session, now: now)
        }
    }

    public func removedExercises(in session: Session) -> [SessionExercise] {
        session.orderedExercises.filter(\.isRemoved)
    }

    public func visibleExercises(in session: Session) -> [SessionExercise] {
        session.orderedExercises.filter { !$0.isRemoved }
    }

    /// Drag & drop: premješta vidljive vježbe, izbačene ostaju na kraju.
    public func moveExercises(in session: Session, from source: IndexSet, to destination: Int, now: Date = Date()) throws {
        var visible = visibleExercises(in: session)
        // Isto kao SwiftUI `move(fromOffsets:toOffset:)`, koji ovdje nije dostupan (paket ne uvozi SwiftUI).
        let moving = source.sorted().map { visible[$0] }
        let target = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { visible.remove(at: index) }
        visible.insert(contentsOf: moving, at: min(max(target, 0), visible.count))
        for (index, exercise) in (visible + removedExercises(in: session)).enumerated() {
            exercise.orderIndex = index
        }
        try touch(session, now: now)
    }

    // MARK: Supersetovi

    /// Spaja vježbe u superset i postavlja ih jednu do druge, na mjesto prve među njima.
    public func makeSuperset(_ exercises: [SessionExercise], in session: Session, now: Date = Date()) throws {
        guard exercises.count >= 2 else { throw WorkoutError.needsTwoExercises }
        let group = UUID()
        let selected = Set(exercises.map(\.id))
        let ordered = visibleExercises(in: session)
        guard let anchor = ordered.firstIndex(where: { selected.contains($0.id) }) else { return }
        let members = ordered.filter { selected.contains($0.id) }
        let others = ordered.filter { !selected.contains($0.id) }
        let insertAt = min(anchor, others.count)
        let result = Array(others[..<insertAt]) + members + Array(others[insertAt...])
        for member in members { member.supersetGroupId = group }
        for (index, exercise) in (result + removedExercises(in: session)).enumerated() {
            exercise.orderIndex = index
        }
        try touch(session, now: now)
    }

    public func removeFromSuperset(_ exercise: SessionExercise, now: Date = Date()) throws {
        let group = exercise.supersetGroupId
        exercise.supersetGroupId = nil
        if let session = exercise.session {
            // Superset s jednom vježbom nema smisla.
            let rest = visibleExercises(in: session).filter { $0.supersetGroupId == group && group != nil }
            if rest.count == 1 { rest[0].supersetGroupId = nil }
            try touch(session, now: now)
        }
    }

    /// Vježbe u istom supersetu (ili sama vježba), po redoslijedu.
    public func group(of exercise: SessionExercise) -> [SessionExercise] {
        guard let id = exercise.supersetGroupId, let session = exercise.session else { return [exercise] }
        return visibleExercises(in: session).filter { $0.supersetGroupId == id }
    }

    // MARK: Serije i rest timer

    /// Označava seriju završenom i vraća rest timer koji treba pokrenuti (nil kad je pauza 0).
    @discardableResult
    public func completeSet(_ set: SetLog, defaultRestSeconds: Int, now: Date = Date()) throws -> RestTimer? {
        guard let exercise = set.exercise, let session = exercise.session else { return nil }
        guard SetMetrics.isComplete(set.values, inputType: exercise.inputType) else { throw WorkoutError.setIncomplete }
        set.completedAt = now

        let members = group(of: exercise)
        let position = members.firstIndex { $0.id == exercise.id } ?? 0
        let configured = exercise.restSeconds ?? members.last?.restSeconds
        let seconds = RestPolicy.seconds(
            positionInGroup: position, groupSize: members.count, configured: configured, defaultSeconds: defaultRestSeconds
        )
        let timer = seconds > 0 ? RestTimer(startedAt: now, seconds: seconds) : nil
        session.restTimerStartedAt = timer?.startedAt
        session.restTimerEndsAt = timer?.endsAt
        try touch(session, now: now)
        return timer
    }

    public func uncompleteSet(_ set: SetLog, now: Date = Date()) throws {
        set.completedAt = nil
        if let session = set.exercise?.session { try touch(session, now: now) }
    }

    public func restTimer(of session: Session) -> RestTimer? {
        guard let start = session.restTimerStartedAt, let end = session.restTimerEndsAt else { return nil }
        return RestTimer(startedAt: start, endsAt: end)
    }

    @discardableResult
    public func adjustRest(of session: Session, bySeconds delta: Int, now: Date = Date()) throws -> RestTimer? {
        guard let timer = restTimer(of: session) else { return nil }
        let adjusted = timer.adjusted(bySeconds: delta, at: now)
        session.restTimerEndsAt = adjusted.endsAt
        try touch(session, now: now)
        return adjusted
    }

    public func cancelRest(of session: Session, now: Date = Date()) throws {
        session.restTimerStartedAt = nil
        session.restTimerEndsAt = nil
        try touch(session, now: now)
    }

    /// Sprema izmjenu (npr. težine ili ponavljanja) i bilježi aktivnost.
    public func touch(_ session: Session, now: Date = Date()) throws {
        session.lastActivityAt = now
        try context.save()
    }

    // MARK: Sažetak i rekordi

    /// Sažetak treninga s osobnim rekordima. Rekordi se uspoređuju samo s ranije završenim treninzima.
    public func summary(of session: Session, trackedKinds: Set<PRKind> = Set(PRKind.allCases)) throws -> WorkoutSummary {
        var volume = 0.0
        var completed = 0
        var records: [WorkoutSummary.ExerciseRecords] = []
        for exercise in visibleExercises(in: session) {
            let done = exercise.orderedSets.filter(\.isCompleted).map(\.values)
            completed += done.count
            volume += done.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }

            let history = try finishedHistory(of: exercise.exercise, before: session)
            let found = PersonalRecordDetector.records(
                current: done, history: history, inputType: exercise.inputType, kinds: trackedKinds
            )
            if !found.isEmpty {
                records.append(.init(exerciseName: exercise.exerciseName, records: found))
            }
        }
        let end = session.endedAt ?? Date()
        return WorkoutSummary(
            durationSeconds: max(0, end.timeIntervalSince(session.startedAt)),
            totalVolumeKg: volume, completedSets: completed, records: records
        )
    }

    // MARK: Pomoćno

    @discardableResult
    private func appendSet(to exercise: SessionExercise, kind: SetKind, previous: [SetValues]) throws -> SetLog {
        let existing = exercise.orderedSets
        let position = existing.filter { $0.kind == kind }.count
        let set = SetLog(orderIndex: existing.count, kind: kind)
        context.insert(set)
        set.exercise = exercise

        var defaults = SmartDefaults.defaults(forPosition: position, kind: kind, previous: previous)
        if defaults == nil, let last = existing.last(where: { $0.kind == kind }) {
            // Bez povijesti nova serija preuzima vrijednosti prethodne serije iste vrste u ovom treningu.
            defaults = SmartDefaults.defaults(forPosition: 0, kind: kind, previous: [last.values])
        }
        if let defaults {
            set.weightKg = defaults.weightKg
            set.reps = defaults.reps
            set.extraWeightKg = defaults.extraWeightKg
            set.durationSeconds = defaults.durationSeconds
            set.distanceMeters = defaults.distanceMeters
        }
        return set
    }

    /// Serije zadnjeg završenog izvođenja vježbe (izvor smart defaultsa).
    private func previousSets(of ref: ExerciseRef, before session: Session?) throws -> [SetValues] {
        let history = try finishedHistory(of: ref, before: session)
        return history.first ?? []
    }

    /// Završene serije iste vježbe u ranije završenim treninzima, od najnovijeg prema starijem.
    private func finishedHistory(of ref: ExerciseRef, before session: Session?) throws -> [[SetValues]] {
        let key = ref.key
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false }
        )
        let currentId = session?.id
        let cutoff = session?.startedAt ?? .distantFuture
        return try context.fetch(descriptor)
            .compactMap { exercise -> (Date, [SetValues])? in
                guard let owner = exercise.session, owner.state == .finished,
                      owner.id != currentId, owner.startedAt < cutoff else { return nil }
                let sets = exercise.orderedSets.filter(\.isCompleted).map(\.values)
                return sets.isEmpty ? nil : (owner.startedAt, sets)
            }
            .sorted { $0.0 > $1.0 }
            .map(\.1)
    }
}
