import Catalog
import Foundation
import Models
import Training

/// Operacije nad aktivnim treningom na satu. Iste su kao `WorkoutEngine` na iPhoneu, ali rade nad
/// snimkom (`SessionSnapshot`) umjesto nad bazom, pa sat ne treba SwiftData.
/// Svaka promjena pomiče `updatedAt`, što drugom uređaju govori da je snimka novija.
public struct SnapshotEngine: Sendable {
    public private(set) var snapshot: SessionSnapshot

    public init(snapshot: SessionSnapshot) {
        self.snapshot = snapshot
    }

    // MARK: Početak

    /// Novi trening iz plana koji je poslao iPhone. Sve vježbe i serije dobivaju nove UUID-ove,
    /// a supersetovi nove oznake grupa.
    public static func start(
        _ plan: PlannedWorkoutPayload, device: DeviceRole, id: UUID = UUID(), now: Date = Date()
    ) -> SessionSnapshot {
        var groups: [Int: UUID] = [:]
        let exercises = plan.exercises.enumerated().map { index, planned -> ExerciseSnapshot in
            let group = planned.supersetGroup.map { key in
                if let existing = groups[key] { return existing }
                let created = UUID()
                groups[key] = created
                return created
            }
            let sets = planned.sets.enumerated().map { setIndex, values in
                SetSnapshot(
                    orderIndex: setIndex, kind: values.kind, weightKg: values.weightKg, reps: values.reps,
                    extraWeightKg: values.extraWeightKg, durationSeconds: values.durationSeconds,
                    distanceMeters: values.distanceMeters
                )
            }
            return ExerciseSnapshot(
                orderIndex: index, exercise: planned.exercise, inputType: planned.inputType,
                supersetGroupId: group, restSeconds: planned.restSeconds, sets: sets
            )
        }
        return SessionSnapshot(
            id: id, name: plan.name, kind: plan.kind, templateId: plan.templateId, scheduleId: plan.scheduleId,
            startedAt: now, controllingDevice: device, updatedAt: now, exercises: exercises
        )
    }

    // MARK: Serije

    /// Označava seriju završenom i pokreće pauzu prema istim pravilima kao iPhone (`RestPolicy`).
    /// Vraća pokrenuti timer ili nil kad je pauza 0.
    @discardableResult
    public mutating func completeSet(_ setID: UUID, defaultRestSeconds: Int, now: Date = Date()) throws -> RestTimer? {
        guard let exercise = snapshot.exercise(containingSet: setID),
              let set = exercise.sets.first(where: { $0.id == setID }) else { return nil }
        guard SetMetrics.isComplete(set.values, inputType: exercise.inputType) else { throw WorkoutError.setIncomplete }
        updateSet(setID, now: now) { $0.completedAt = now }

        let members = group(of: exercise.id)
        let position = members.firstIndex { $0.id == exercise.id } ?? 0
        let configured = exercise.restSeconds ?? members.last?.restSeconds
        let seconds = RestPolicy.seconds(
            positionInGroup: position, groupSize: members.count, configured: configured, defaultSeconds: defaultRestSeconds
        )
        let timer = seconds > 0 ? RestTimer(startedAt: now, seconds: seconds) : nil
        snapshot.restTimerStartedAt = timer?.startedAt
        snapshot.restTimerEndsAt = timer?.endsAt
        touch(now)
        return timer
    }

    public mutating func uncompleteSet(_ setID: UUID, now: Date = Date()) {
        updateSet(setID, now: now) { $0.completedAt = nil }
    }

    /// Mijenja vrijednosti serije (težina, ponavljanja...).
    public mutating func updateSet(_ setID: UUID, now: Date = Date(), _ change: (inout SetSnapshot) -> Void) {
        for exerciseIndex in snapshot.exercises.indices {
            if let setIndex = snapshot.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) {
                change(&snapshot.exercises[exerciseIndex].sets[setIndex])
                touch(now)
                return
            }
        }
    }

    /// Dodaje seriju na kraj vježbe s vrijednostima zadnje serije iste vrste (bez RPE-a i kvačice).
    @discardableResult
    public mutating func addSet(to exerciseID: UUID, kind: SetKind = .working, now: Date = Date()) -> UUID? {
        guard let index = snapshot.exercises.firstIndex(where: { $0.id == exerciseID }) else { return nil }
        let existing = snapshot.exercises[index].orderedSets
        let template = existing.last { $0.kind == kind }
        let set = SetSnapshot(
            orderIndex: (existing.map(\.orderIndex).max() ?? -1) + 1, kind: kind,
            weightKg: template?.weightKg, reps: template?.reps, extraWeightKg: template?.extraWeightKg,
            durationSeconds: template?.durationSeconds, distanceMeters: template?.distanceMeters
        )
        snapshot.exercises[index].sets.append(set)
        touch(now)
        return set.id
    }

    // MARK: Pauza

    public var restTimer: RestTimer? {
        guard let start = snapshot.restTimerStartedAt, let end = snapshot.restTimerEndsAt else { return nil }
        return RestTimer(startedAt: start, endsAt: end)
    }

    public mutating func adjustRest(bySeconds delta: Int, now: Date = Date()) {
        guard let timer = restTimer else { return }
        snapshot.restTimerEndsAt = timer.adjusted(bySeconds: delta, at: now).endsAt
        touch(now)
    }

    public mutating func cancelRest(now: Date = Date()) {
        guard snapshot.restTimerStartedAt != nil || snapshot.restTimerEndsAt != nil else { return }
        snapshot.restTimerStartedAt = nil
        snapshot.restTimerEndsAt = nil
        touch(now)
    }

    // MARK: Kraj

    /// Zatvara trening kao `WorkoutEngine.finishSession`: brišu se nezavršene serije, izbačene i prazne vježbe.
    public mutating func finish(now: Date = Date()) throws {
        let hasCompleted = snapshot.exercises.contains { !$0.isRemoved && $0.sets.contains(where: \.isCompleted) }
        guard hasCompleted else { throw WorkoutError.nothingCompleted }
        snapshot.exercises = snapshot.exercises
            .filter { !$0.isRemoved }
            .map { exercise in
                var copy = exercise
                copy.sets = exercise.sets.filter(\.isCompleted)
                return copy
            }
            .filter { !$0.sets.isEmpty }
        // Isto kao na iPhoneu: udaljenost treninga je zbroj udaljenosti završenih serija.
        let distance = snapshot.exercises.flatMap(\.sets).compactMap(\.distanceMeters).reduce(0, +)
        if distance > 0 { snapshot.distanceMeters = distance }
        snapshot.state = .finished
        snapshot.endedAt = now
        snapshot.restTimerStartedAt = nil
        snapshot.restTimerEndsAt = nil
        touch(now)
    }

    public mutating func discard(now: Date = Date()) {
        snapshot.state = .discarded
        touch(now)
    }

    /// Podaci iz HealthKita nakon završetka sesije na satu.
    public mutating func recordHealth(workoutId: UUID?, activeEnergyKilocalories: Double?, averageHeartRate: Double?, now: Date = Date()) {
        snapshot.healthKitWorkoutId = workoutId
        snapshot.activeEnergyKilocalories = activeEnergyKilocalories.flatMap { $0 > 0 ? $0 : nil }
        snapshot.averageHeartRate = averageHeartRate.flatMap { $0 > 0 ? $0 : nil }
        touch(now)
    }

    // MARK: Tijek

    /// Vježbe u istom supersetu (ili sama vježba), po redoslijedu.
    public func group(of exerciseID: UUID) -> [ExerciseSnapshot] {
        guard let exercise = snapshot.exercise(withID: exerciseID) else { return [] }
        guard let group = exercise.supersetGroupId else { return [exercise] }
        return snapshot.visibleExercises.filter { $0.supersetGroupId == group }
    }

    /// Sljedeća serija za unos u vježbi: prva nezavršena, a u supersetu po naizmjeničnom redoslijedu
    /// (A1, B1, A2, B2...). Može pripadati drugoj vježbi iz istog superseta.
    public func nextSet(forExercise exerciseID: UUID) -> (exercise: ExerciseSnapshot, set: SetSnapshot)? {
        let members = group(of: exerciseID)
        guard members.count > 1 else {
            guard let exercise = members.first, let set = exercise.orderedSets.first(where: { !$0.isCompleted }) else { return nil }
            return (exercise, set)
        }
        let ordered = members.map(\.orderedSets)
        let next = SupersetSequence.nextIncomplete(setCounts: ordered.map(\.count)) { position in
            ordered[position.exercise][position.set].isCompleted
        }
        return next.map { (members[$0.exercise], ordered[$0.exercise][$0.set]) }
    }

    /// Kamo nakon završene serije: ista vježba dok ima nezavršenih serija (u supersetu cijela grupa),
    /// a zatim prva nekompletirana vježba. nil znači da je sve završeno.
    public func exerciseAfterCompleting(in exerciseID: UUID) -> UUID? {
        if nextSet(forExercise: exerciseID) != nil { return exerciseID }
        let visible = snapshot.visibleExercises
        return WorkoutFlow.firstIncompleteExercise(isFullyCompleted: visible.map(\.isFullyCompleted)).map { visible[$0].id }
    }

    /// Volumen završenih radnih serija u kilogramima.
    public var totalVolumeKg: Double {
        snapshot.visibleExercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isCompleted).reduce(0) { $0 + SetMetrics.volume($1.values, inputType: exercise.inputType) }
        }
    }

    private mutating func touch(_ now: Date) {
        snapshot.updatedAt = max(snapshot.updatedAt, now)
    }
}

extension SetSnapshot {
    /// Vrijednosti za pravila iz `Training` (potpunost serije, volumen).
    public var values: SetValues {
        SetValues(
            kind: kind, weightKg: weightKg, reps: reps, extraWeightKg: extraWeightKg,
            durationSeconds: durationSeconds, distanceMeters: distanceMeters, rpe: rpe
        )
    }
}
