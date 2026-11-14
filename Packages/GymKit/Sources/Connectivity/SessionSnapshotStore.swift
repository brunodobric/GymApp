import Foundation
import Models
import SwiftData

extension SessionSnapshot {
    /// Snimka treninga iz baze na iPhoneu. `weightStep` daje korak težine vježbe za krunu na satu.
    public init(session: Session, weightStep: (ExerciseRef) -> Double? = { _ in nil }) {
        self.init(
            id: session.id,
            name: session.name,
            kind: session.kind,
            templateId: session.templateId,
            scheduleId: session.scheduleId,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            state: session.state,
            controllingDevice: session.controllingDevice,
            notes: session.notes,
            restTimerStartedAt: session.restTimerStartedAt,
            restTimerEndsAt: session.restTimerEndsAt,
            activeEnergyKilocalories: session.activeEnergyKilocalories,
            averageHeartRate: session.averageHeartRate,
            healthKitWorkoutId: session.healthKitWorkoutId,
            distanceMeters: session.distanceMeters,
            updatedAt: session.lastActivityAt,
            exercises: session.orderedExercises.map { exercise in
                var snapshot = ExerciseSnapshot(
                    id: exercise.id,
                    orderIndex: exercise.orderIndex,
                    exercise: exercise.exercise,
                    inputType: exercise.inputType,
                    supersetGroupId: exercise.supersetGroupId,
                    restSeconds: exercise.restSeconds,
                    isRemoved: exercise.isRemoved,
                    sets: exercise.orderedSets.map { set in
                        SetSnapshot(
                            id: set.id, orderIndex: set.orderIndex, kind: set.kind, weightKg: set.weightKg,
                            reps: set.reps, extraWeightKg: set.extraWeightKg, durationSeconds: set.durationSeconds,
                            distanceMeters: set.distanceMeters, rpe: set.rpe, completedAt: set.completedAt
                        )
                    },
                    weightStep: weightStep(exercise.exercise)
                )
                snapshot.targetRepsMin = exercise.targetRepsMin
                snapshot.targetRepsMax = exercise.targetRepsMax
                snapshot.loadChangeKg = exercise.loadChangeKg
                snapshot.notes = exercise.notes.isEmpty ? nil : exercise.notes
                return snapshot
            }
        )
    }
}

/// Upisuje snimku sa sata u bazu na iPhoneu. Zapis se traži po UUID-u treninga, vježbe i serije,
/// pa ista snimka primljena dvaput (ili stara snimka iz reda za slanje) ne stvara duplikate.
public struct SessionSnapshotStore {
    public let context: ModelContext
    /// Korak težine vježbe za snimku (`SessionSnapshot.init(session:weightStep:)`).
    public let weightStep: (ExerciseRef) -> Double?

    public init(context: ModelContext, weightStep: @escaping (ExerciseRef) -> Double? = { _ in nil }) {
        self.context = context
        self.weightStep = weightStep
    }

    /// Snimka treninga s kalorijama i pulsom iz lokalne baze podataka iz Zdravlja.
    public func snapshot(of session: Session) -> SessionSnapshot {
        var snapshot = SessionSnapshot(session: session, weightStep: weightStep)
        let local = try? HealthLocalStore(context: context).values(forSession: session.id)
        snapshot.activeEnergyKilocalories = local?.activeEnergyKilocalories ?? session.activeEnergyKilocalories
        snapshot.averageHeartRate = local?.averageHeartRate ?? session.averageHeartRate
        return snapshot
    }

    public enum Outcome: Equatable, Sendable {
        /// Trening je upisan. `previousState` je stanje prije upisa (nil za novi trening).
        case applied(previousState: SessionState?)
        /// Baza već ima noviju promjenu, snimka se preskače.
        case ignoredOlder
        /// Trening je odbačen. Ostaje u bazi označen kao odbačen dok ga `purgeDiscarded` ne obriše,
        /// kako ekran koji ga upravo prikazuje ne bi čitao obrisan zapis.
        case discarded
    }

    public func session(withID id: UUID) throws -> Session? {
        try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first
    }

    /// Upisuje snimku ako je novija od zapisa u bazi (ili `force` kad uređaj koji vodi trening
    /// upisuje vlastito stanje nakon primljenih naredbi).
    @discardableResult
    public func apply(_ snapshot: SessionSnapshot, force: Bool = false) throws -> Outcome {
        let existing = try session(withID: snapshot.id)
        if let existing, !force, !snapshot.isNewer(than: existing.lastActivityAt) {
            return .ignoredOlder
        }
        if snapshot.state == .discarded {
            if let existing {
                existing.state = .discarded
                existing.lastActivityAt = snapshot.updatedAt
                try context.save()
            }
            return .discarded
        }
        let previous = existing?.state
        let session: Session
        if let existing {
            session = existing
        } else {
            session = Session(name: snapshot.name, kind: snapshot.kind, startedAt: snapshot.startedAt)
            session.id = snapshot.id
            context.insert(session)
        }
        write(snapshot, into: session)
        try context.save()
        return .applied(previousState: previous)
    }

    /// Izvještaj sata o sesiji u Zdravlju za trening koji vodi iPhone (`WorkoutCommand.isHealthReport`).
    /// Vrijedi i za trening koji je na iPhoneu već završen. Ostale naredbe se ovdje preskaču.
    /// Vraća je li se trening promijenio.
    @discardableResult
    public func applyWatchHealth(_ commands: [WorkoutCommand], toSessionWithID id: UUID) throws -> Bool {
        let reports = commands.filter(\.isHealthReport)
        guard !reports.isEmpty, let session = try session(withID: id), session.controllingDevice == .phone,
              session.state != .discarded else { return false }
        // Svaki izvještaj (i završni, ako je prvi izgubljen) znači da trening u Zdravlje sprema sat.
        session.healthRecordedByWatch = true
        for case let .healthRecorded(workoutId, energy, heartRate) in reports {
            if session.healthKitWorkoutId == nil, let workoutId { session.healthKitWorkoutId = workoutId }
            try HealthLocalStore(context: context).setValues(
                forSession: id, activeEnergyKilocalories: energy, averageHeartRate: heartRate
            )
        }
        try context.save()
        return true
    }

    /// Briše odbačene treninge (vidi `Outcome.discarded`). Vraća broj obrisanih.
    @discardableResult
    public func purgeDiscarded() throws -> Int {
        let discarded = SessionState.discarded.rawValue
        let sessions = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.stateRaw == discarded }))
        for session in sessions { context.delete(session) }
        if !sessions.isEmpty { try context.save() }
        return sessions.count
    }

    private func write(_ snapshot: SessionSnapshot, into session: Session) {
        session.name = snapshot.name
        session.kind = snapshot.kind
        session.templateId = snapshot.templateId
        session.scheduleId = snapshot.scheduleId
        session.startedAt = snapshot.startedAt
        session.endedAt = snapshot.endedAt
        session.state = snapshot.state
        session.controllingDevice = snapshot.controllingDevice
        session.notes = snapshot.notes
        session.restTimerStartedAt = snapshot.restTimerStartedAt
        session.restTimerEndsAt = snapshot.restTimerEndsAt
        // Kalorije i puls sa sata su podaci iz Zdravlja: idu u lokalnu bazu, ne u trening koji se sinkronizira.
        // Ne brišu se ako ih snimka (još) nema.
        try? HealthLocalStore(context: context).setValues(
            forSession: session.id,
            activeEnergyKilocalories: snapshot.activeEnergyKilocalories,
            averageHeartRate: snapshot.averageHeartRate
        )
        if let workoutId = snapshot.healthKitWorkoutId { session.healthKitWorkoutId = workoutId }
        if let distance = snapshot.distanceMeters { session.distanceMeters = distance }
        session.lastActivityAt = snapshot.updatedAt

        let existingExercises = Dictionary((session.exercises ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let keptExercises = Set(snapshot.exercises.map(\.id))
        for exercise in session.exercises ?? [] where !keptExercises.contains(exercise.id) {
            context.delete(exercise)
        }
        for item in snapshot.exercises {
            let exercise: SessionExercise
            if let found = existingExercises[item.id] {
                exercise = found
            } else {
                exercise = SessionExercise(orderIndex: item.orderIndex, exercise: item.exercise, inputType: item.inputType)
                exercise.id = item.id
                context.insert(exercise)
                exercise.session = session
            }
            exercise.orderIndex = item.orderIndex
            if exercise.exercise != item.exercise { exercise.exercise = item.exercise }
            exercise.inputType = item.inputType
            exercise.supersetGroupId = item.supersetGroupId
            exercise.restSeconds = item.restSeconds
            exercise.isRemoved = item.isRemoved
            exercise.targetRepsMin = item.targetRepsMin
            exercise.targetRepsMax = item.targetRepsMax
            exercise.loadChangeKg = item.loadChangeKg
            exercise.notes = item.notes ?? ""
            write(item.sets, into: exercise)
        }
    }

    private func write(_ sets: [SetSnapshot], into exercise: SessionExercise) {
        let existing = Dictionary((exercise.sets ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = Set(sets.map(\.id))
        for set in exercise.sets ?? [] where !kept.contains(set.id) {
            context.delete(set)
        }
        for item in sets {
            let set: SetLog
            if let found = existing[item.id] {
                set = found
            } else {
                set = SetLog(orderIndex: item.orderIndex, kind: item.kind)
                set.id = item.id
                context.insert(set)
                set.exercise = exercise
            }
            set.orderIndex = item.orderIndex
            set.kind = item.kind
            set.weightKg = item.weightKg
            set.reps = item.reps
            set.extraWeightKg = item.extraWeightKg
            set.durationSeconds = item.durationSeconds
            set.distanceMeters = item.distanceMeters
            set.rpe = item.rpe
            set.completedAt = item.completedAt
        }
    }
}
