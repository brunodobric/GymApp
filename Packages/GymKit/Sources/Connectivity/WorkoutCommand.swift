import Foundation
import Models

/// Izmjena koju uređaj koji zrcali trening šalje uređaju koji ga vodi (specifikacija: "jedan uređaj vodi
/// trening, a drugi prikazuje i može upisivati promjene"). Naredbe su na razini serije i vježbe, pa se
/// istovremene izmjene različitih serija ne poništavaju međusobno.
public enum WorkoutCommand: Codable, Sendable, Equatable {
    /// Nova ili izmijenjena serija (vrijednosti, vrsta, kvačica).
    case upsertSet(exerciseID: UUID, set: SetSnapshot)
    case deleteSet(setID: UUID)
    /// Nova vježba (sa serijama) ili izmjena postojeće na razini vježbe (redoslijed, superset, pauza,
    /// izbacivanje). Serije postojeće vježbe ovdje se ne diraju.
    case upsertExercise(ExerciseSnapshot)
    case deleteExercise(exerciseID: UUID)
    case setRestTimer(startedAt: Date?, endsAt: Date?)
    case setNotes(String)
    case finish(at: Date)
    case discard
    /// Sat je za trening koji vodi iPhone pokrenuo sesiju u Zdravlju (puls, kalorije): na kraju će trening
    /// u Zdravlje spremiti sat, pa iPhone to ne radi.
    case healthRecordingStarted
    /// Sat je zatvorio tu sesiju: UUID treninga spremljenog u Zdravlje (ako je spremljen), kalorije i puls.
    /// Stiže i nakon što je trening na iPhoneu već završen.
    case healthRecorded(workoutId: UUID?, activeEnergyKilocalories: Double?, averageHeartRate: Double?)

    /// Izvještaj sata o sesiji u Zdravlju. Ne mijenja serije ni stanje treninga, pa se primjenjuje
    /// i na završen trening (`SessionSnapshotStore.applyWatchHealth`).
    public var isHealthReport: Bool {
        switch self {
        case .healthRecordingStarted, .healthRecorded: true
        default: false
        }
    }
}

public enum SnapshotDiff {

    /// Naredbe koje iz `base` daju `edited`. Primijenjene redom (`SnapshotDiff.apply`) na `base`
    /// daju isti trening kao `edited` (osim vremena zadnje promjene).
    public static func commands(from base: SessionSnapshot, to edited: SessionSnapshot) -> [WorkoutCommand] {
        var result: [WorkoutCommand] = []
        let baseExercises = Dictionary(uniqueKeysWithValues: base.exercises.map { ($0.id, $0) })
        let editedIDs = Set(edited.exercises.map(\.id))

        for exercise in edited.orderedExercises {
            guard let old = baseExercises[exercise.id] else {
                result.append(.upsertExercise(exercise))
                continue
            }
            if old.withoutSets != exercise.withoutSets {
                result.append(.upsertExercise(exercise.withoutSets))
            }
            let oldSets = Dictionary(uniqueKeysWithValues: old.sets.map { ($0.id, $0) })
            for set in exercise.orderedSets where oldSets[set.id] != set {
                result.append(.upsertSet(exerciseID: exercise.id, set: set))
            }
            let newSetIDs = Set(exercise.sets.map(\.id))
            for set in old.orderedSets where !newSetIDs.contains(set.id) {
                result.append(.deleteSet(setID: set.id))
            }
        }
        for exercise in base.orderedExercises where !editedIDs.contains(exercise.id) {
            result.append(.deleteExercise(exerciseID: exercise.id))
        }
        if base.restTimerStartedAt != edited.restTimerStartedAt || base.restTimerEndsAt != edited.restTimerEndsAt {
            result.append(.setRestTimer(startedAt: edited.restTimerStartedAt, endsAt: edited.restTimerEndsAt))
        }
        if base.notes != edited.notes {
            result.append(.setNotes(edited.notes))
        }
        if base.state == .active {
            switch edited.state {
            case .finished: result.append(.finish(at: edited.endedAt ?? edited.updatedAt))
            case .discarded: result.append(.discard)
            case .active: break
            }
        }
        return result
    }

    /// Primjenjuje naredbe na snimku. Naredba za seriju ili vježbu koja više ne postoji se preskače.
    /// Završetak čisti trening kao `WorkoutEngine.finishSession` (vidi `SnapshotEngine.finish`).
    public static func apply(_ commands: [WorkoutCommand], to snapshot: SessionSnapshot, at now: Date) -> SessionSnapshot {
        var result = snapshot
        for command in commands {
            apply(command, to: &result)
        }
        result.updatedAt = max(result.updatedAt, now)
        return result
    }

    private static func apply(_ command: WorkoutCommand, to snapshot: inout SessionSnapshot) {
        switch command {
        case let .upsertSet(exerciseID, set):
            guard let index = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            if let setIndex = snapshot.exercises[index].sets.firstIndex(where: { $0.id == set.id }) {
                snapshot.exercises[index].sets[setIndex] = set
            } else {
                snapshot.exercises[index].sets.append(set)
            }
        case let .deleteSet(setID):
            for index in snapshot.exercises.indices {
                snapshot.exercises[index].sets.removeAll { $0.id == setID }
            }
        case let .upsertExercise(exercise):
            if let index = snapshot.exercises.firstIndex(where: { $0.id == exercise.id }) {
                var updated = exercise
                updated.sets = snapshot.exercises[index].sets
                snapshot.exercises[index] = updated
            } else {
                snapshot.exercises.append(exercise)
            }
        case let .deleteExercise(exerciseID):
            snapshot.exercises.removeAll { $0.id == exerciseID }
        case let .setRestTimer(startedAt, endsAt):
            snapshot.restTimerStartedAt = startedAt
            snapshot.restTimerEndsAt = endsAt
        case let .setNotes(notes):
            snapshot.notes = notes
        case let .finish(date):
            guard snapshot.state == .active else { return }
            var engine = SnapshotEngine(snapshot: snapshot)
            // Mirror je već provjerio da postoji završena serija; ako nije, trening ostaje otvoren.
            if (try? engine.finish(now: date)) != nil {
                snapshot = engine.snapshot
            }
        case .discard:
            snapshot.state = .discarded
        case .healthRecordingStarted:
            break
        case let .healthRecorded(workoutId, energy, heartRate):
            if let workoutId { snapshot.healthKitWorkoutId = workoutId }
            if let energy, energy > 0 { snapshot.activeEnergyKilocalories = energy }
            if let heartRate, heartRate > 0 { snapshot.averageHeartRate = heartRate }
        }
    }
}
