package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.training.RestDefaults
import com.brunodobric.gymapp.training.RestPolicy
import com.brunodobric.gymapp.training.RestTimer
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.SupersetSequence
import com.brunodobric.gymapp.training.WorkoutError
import com.brunodobric.gymapp.training.WorkoutFlow
import java.time.Instant
import java.util.UUID

/**
 * Operacije nad aktivnim treningom na satu (`SnapshotEngine` na iOS-u). Iste su kao `WorkoutEngine` na mobitelu,
 * ali rade nad snimkom ([SessionSnapshot]) umjesto nad bazom, pa sat ne treba bazu mobitela. Svaka promjena pomiče
 * `updatedAt`, što drugom uređaju govori da je snimka novija.
 */
class SnapshotEngine(snapshot: SessionSnapshot) {
    var snapshot: SessionSnapshot = snapshot
        private set

    // MARK: Serije

    /**
     * Označava seriju završenom i pokreće pauzu prema istim pravilima kao mobitel (`RestPolicy`); vježba bez
     * vlastite pauze dobiva zadanu prema vrsti ([RestDefaults]). Vraća pokrenuti timer ili null kad je pauza 0.
     * Baca [WorkoutError.SetIncomplete] za seriju bez potrebnih vrijednosti.
     */
    fun completeSet(
        setId: UUID,
        restDefaults: RestDefaults,
        isCompound: (ExerciseRef) -> Boolean? = { null },
        now: Instant = Instant.now(),
    ): RestTimer? {
        val exercise = snapshot.exerciseContaining(setId) ?: return null
        val set = exercise.sets.first { it.id == setId }
        if (!SetMetrics.isComplete(set.values, exercise.inputType)) throw WorkoutError.SetIncomplete
        val at = now.truncatedToMillis()
        updateSet(setId, at) { it.copy(completedAt = at) }

        val members = group(exercise.id)
        val position = members.indexOfFirst { it.id == exercise.id }.coerceAtLeast(0)
        val configured = exercise.restSeconds ?: members.lastOrNull()?.restSeconds
        val defaultSeconds = restDefaults.seconds(members.map { isCompound(it.exercise) })
        var seconds = RestPolicy.seconds(position, members.size, configured, defaultSeconds)
        if (set.kind == SetKind.WARM_UP) {
            val index = exercise.sets.indexOfFirst { it.id == setId }
            val next = exercise.sets.getOrNull(index + 1)
            seconds = RestPolicy.afterWarmUp(seconds, nextIsWarmUp = next?.kind == SetKind.WARM_UP)
        }
        val timer = if (seconds > 0) RestTimer(at, seconds) else null
        snapshot = snapshot.copy(restTimerStartedAt = timer?.startedAt, restTimerEndsAt = timer?.endsAt)
        touch(at)
        return timer
    }

    fun uncompleteSet(setId: UUID, now: Instant = Instant.now()) {
        updateSet(setId, now) { it.copy(completedAt = null) }
    }

    /** Mijenja vrijednosti serije (težina, ponavljanja…). */
    fun updateSet(setId: UUID, now: Instant = Instant.now(), change: (SetSnapshot) -> SetSnapshot) {
        val exercise = snapshot.exerciseContaining(setId) ?: return
        snapshot = snapshot.copy(
            exercises = snapshot.exercises.map { item ->
                if (item.id != exercise.id) item else item.copy(sets = item.sets.map { if (it.id == setId) change(it) else it })
            },
        )
        touch(now)
    }

    /** Dodaje seriju na kraj vježbe s vrijednostima zadnje serije iste vrste (bez RPE-a i kvačice). */
    fun addSet(exerciseId: UUID, kind: SetKind = SetKind.WORKING, now: Instant = Instant.now()): UUID? {
        val exercise = snapshot.exercise(exerciseId) ?: return null
        val existing = exercise.orderedSets
        val template = existing.lastOrNull { it.kind == kind }
        val set = SetSnapshot(
            orderIndex = (existing.maxOfOrNull { it.orderIndex } ?: -1) + 1,
            kind = kind,
            weightKg = template?.weightKg,
            reps = template?.reps,
            extraWeightKg = template?.extraWeightKg,
            durationSeconds = template?.durationSeconds,
            distanceMeters = template?.distanceMeters,
        )
        snapshot = snapshot.copy(exercises = snapshot.exercises.map { if (it.id == exerciseId) it.copy(sets = it.sets + set) else it })
        touch(now)
        return set.id
    }

    // MARK: Pauza

    val restTimer: RestTimer?
        get() {
            val start = snapshot.restTimerStartedAt ?: return null
            val end = snapshot.restTimerEndsAt ?: return null
            return RestTimer(start, end)
        }

    fun adjustRest(deltaSeconds: Int, now: Instant = Instant.now()) {
        val timer = restTimer ?: return
        snapshot = snapshot.copy(restTimerEndsAt = timer.adjusted(deltaSeconds, now.truncatedToMillis()).endsAt.truncatedToMillis())
        touch(now)
    }

    fun cancelRest(now: Instant = Instant.now()) {
        if (snapshot.restTimerStartedAt == null && snapshot.restTimerEndsAt == null) return
        snapshot = snapshot.copy(restTimerStartedAt = null, restTimerEndsAt = null)
        touch(now)
    }

    // MARK: Kraj

    /** Zatvara trening kao `WorkoutEngine.finishSession`: brišu se nezavršene serije, izbačene i prazne vježbe. */
    fun finish(now: Instant = Instant.now()) {
        val hasCompleted = snapshot.exercises.any { exercise -> !exercise.isRemoved && exercise.sets.any { it.isCompleted } }
        if (!hasCompleted) throw WorkoutError.NothingCompleted
        val exercises = snapshot.exercises
            .filter { !it.isRemoved }
            .map { exercise -> exercise.copy(sets = exercise.sets.filter { it.isCompleted }) }
            .filter { it.sets.isNotEmpty() }
        // Isto kao na mobitelu: udaljenost treninga je zbroj udaljenosti završenih serija.
        val distance = exercises.flatMap { it.sets }.mapNotNull { it.distanceMeters }.sum()
        val at = now.truncatedToMillis()
        snapshot = snapshot.copy(
            exercises = exercises,
            distanceMeters = if (distance > 0) distance else snapshot.distanceMeters,
            state = SessionState.FINISHED,
            endedAt = at,
            restTimerStartedAt = null,
            restTimerEndsAt = null,
        )
        touch(at)
    }

    fun discard(now: Instant = Instant.now()) {
        snapshot = snapshot.copy(state = SessionState.DISCARDED)
        touch(now)
    }

    /** Kalorije i prosječni puls nakon završetka mjerenja na satu. */
    fun recordHealth(activeEnergyKilocalories: Double?, averageHeartRate: Double?, now: Instant = Instant.now()) {
        snapshot = snapshot.copy(
            activeEnergyKilocalories = activeEnergyKilocalories?.takeIf { it > 0 },
            averageHeartRate = averageHeartRate?.takeIf { it > 0 },
        )
        touch(now)
    }

    // MARK: Tijek

    /** Vježbe u istom supersetu (ili sama vježba), po redoslijedu. */
    fun group(exerciseId: UUID): List<ExerciseSnapshot> {
        val exercise = snapshot.exercise(exerciseId) ?: return emptyList()
        val group = exercise.supersetGroupId ?: return listOf(exercise)
        return snapshot.visibleExercises.filter { it.supersetGroupId == group }
    }

    /**
     * Sljedeća serija za unos u vježbi: prva nezavršena, a u supersetu po naizmjeničnom redoslijedu (A1, B1, A2,
     * B2…). Može pripadati drugoj vježbi iz istog superseta.
     */
    fun nextSet(exerciseId: UUID): Pair<ExerciseSnapshot, SetSnapshot>? {
        val members = group(exerciseId)
        if (members.size <= 1) {
            val exercise = members.firstOrNull() ?: return null
            val set = exercise.orderedSets.firstOrNull { !it.isCompleted } ?: return null
            return exercise to set
        }
        val ordered = members.map { it.orderedSets }
        val next = SupersetSequence.nextIncomplete(ordered.map { it.size }) { ordered[it.exercise][it.set].isCompleted }
            ?: return null
        return members[next.exercise] to ordered[next.exercise][next.set]
    }

    /**
     * Kamo nakon završene serije: ista vježba dok ima nezavršenih serija (u supersetu cijela grupa), a zatim prva
     * nedovršena vježba. null znači da je sve završeno.
     */
    fun exerciseAfterCompleting(exerciseId: UUID): UUID? {
        if (nextSet(exerciseId) != null) return exerciseId
        val visible = snapshot.visibleExercises
        return WorkoutFlow.firstIncompleteExercise(visible.map { it.isFullyCompleted })?.let { visible[it].id }
    }

    /** Volumen završenih serija u kilogramima. */
    val totalVolumeKg: Double
        get() = snapshot.visibleExercises.sumOf { exercise ->
            exercise.sets.filter { it.isCompleted }.sumOf { SetMetrics.volume(it.values, exercise.inputType) }
        }

    private fun touch(now: Instant) {
        snapshot = snapshot.copy(updatedAt = maxOf(snapshot.updatedAt, now.truncatedToMillis()))
    }

    companion object {
        /**
         * Novi trening iz plana koji je poslao mobitel. Sve vježbe i serije dobivaju nove UUID-ove, a supersetovi nove
         * oznake grupa.
         */
        fun start(plan: PlannedWorkoutPayload, device: DeviceRole, id: UUID = UUID.randomUUID(), now: Instant = Instant.now()): SessionSnapshot {
            val groups = mutableMapOf<Int, UUID>()
            val exercises = plan.exercises.mapIndexed { index, planned ->
                ExerciseSnapshot(
                    orderIndex = index,
                    exercise = planned.exercise,
                    inputType = planned.inputType,
                    supersetGroupId = planned.supersetGroup?.let { groups.getOrPut(it) { UUID.randomUUID() } },
                    restSeconds = planned.restSeconds,
                    sets = planned.sets.mapIndexed { setIndex, values ->
                        SetSnapshot(
                            orderIndex = setIndex, kind = values.kind, weightKg = values.weightKg, reps = values.reps,
                            extraWeightKg = values.extraWeightKg, durationSeconds = values.durationSeconds,
                            distanceMeters = values.distanceMeters,
                        )
                    },
                    weightStep = planned.weightStep,
                    targetRepsMin = planned.targetRepsMin,
                    targetRepsMax = planned.targetRepsMax,
                    loadChangeKg = planned.loadChangeKg,
                    notes = planned.notes,
                )
            }
            val at = now.truncatedToMillis()
            return SessionSnapshot(
                id = id, name = plan.name, kind = plan.kind, templateId = plan.templateId, scheduleId = plan.scheduleId,
                startedAt = at, controllingDevice = device, updatedAt = at, exercises = exercises,
            )
        }
    }
}
