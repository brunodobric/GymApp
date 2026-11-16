package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetLog
import java.util.UUID

/** Snimka treninga iz baze na mobitelu. [weightStep] daje korak težine vježbe za okretni okvir na satu. */
fun Session.snapshot(weightStep: (ExerciseRef) -> Double? = { null }): SessionSnapshot = SessionSnapshot(
    id = id,
    name = name,
    kind = kind,
    templateId = templateId,
    scheduleId = scheduleId,
    startedAt = startedAt.truncatedToMillis(),
    endedAt = endedAt?.truncatedToMillis(),
    state = state,
    controllingDevice = controllingDevice,
    notes = notes,
    restTimerStartedAt = restTimerStartedAt?.truncatedToMillis(),
    restTimerEndsAt = restTimerEndsAt?.truncatedToMillis(),
    activeEnergyKilocalories = activeEnergyKilocalories,
    averageHeartRate = averageHeartRate,
    healthWorkoutId = healthKitWorkoutId,
    distanceMeters = distanceMeters,
    updatedAt = lastActivityAt.truncatedToMillis(),
    exercises = orderedExercises.map { exercise ->
        ExerciseSnapshot(
            id = exercise.id,
            orderIndex = exercise.orderIndex,
            exercise = exercise.exercise,
            inputType = exercise.inputType,
            supersetGroupId = exercise.supersetGroupId,
            restSeconds = exercise.restSeconds,
            isRemoved = exercise.isRemoved,
            sets = exercise.orderedSets.map { set ->
                SetSnapshot(
                    id = set.id, orderIndex = set.orderIndex, kind = set.kind, weightKg = set.weightKg, reps = set.reps,
                    extraWeightKg = set.extraWeightKg, durationSeconds = set.durationSeconds,
                    distanceMeters = set.distanceMeters, rpe = set.rpe, completedAt = set.completedAt?.truncatedToMillis(),
                )
            },
            weightStep = weightStep(exercise.exercise),
            targetRepsMin = exercise.targetRepsMin,
            targetRepsMax = exercise.targetRepsMax,
            loadChangeKg = exercise.loadChangeKg,
            notes = exercise.notes.ifEmpty { null },
        )
    },
)

/**
 * Upisuje snimku sa sata u bazu na mobitelu (`SessionSnapshotStore` na iOS-u). Zapis se traži po UUID-u treninga,
 * vježbe i serije, pa ista snimka primljena dvaput (ili stara snimka iz reda za slanje) ne stvara duplikate.
 * Sprema bazu nakon svake promjene.
 */
class SessionSnapshotStore(private val store: GymStore) {

    sealed class Outcome {
        /** Trening je upisan. [previousState] je stanje prije upisa (null za novi trening). */
        data class Applied(val previousState: SessionState?) : Outcome()

        /** Baza već ima noviju promjenu, snimka se preskače. */
        data object IgnoredOlder : Outcome()

        /**
         * Trening je odbačen. Ostaje u bazi označen kao odbačen dok ga [purgeDiscarded] ne obriše, da ekran koji ga
         * upravo prikazuje ne čita obrisan zapis.
         */
        data object Discarded : Outcome()
    }

    fun session(id: UUID): Session? = store.sessions.firstOrNull { it.id == id }

    /**
     * Upisuje snimku ako je novija od zapisa u bazi (ili [force] kad uređaj koji vodi trening upisuje vlastito stanje
     * nakon primljenih naredbi).
     */
    fun apply(snapshot: SessionSnapshot, force: Boolean = false): Outcome {
        val existing = session(snapshot.id)
        if (existing != null && !force && !snapshot.isNewer(existing.lastActivityAt.truncatedToMillis())) return Outcome.IgnoredOlder
        if (snapshot.state == SessionState.DISCARDED) {
            if (existing != null) {
                existing.state = SessionState.DISCARDED
                existing.lastActivityAt = snapshot.updatedAt
                store.save()
            }
            return Outcome.Discarded
        }
        val previous = existing?.state
        val session = existing ?: store.insert(Session(snapshot.name, snapshot.kind, snapshot.startedAt).also { it.id = snapshot.id })
        write(snapshot, session)
        store.save()
        return Outcome.Applied(previous)
    }

    /**
     * Izvještaj sata o mjerenju za trening koji vodi mobitel ([WorkoutCommand.isHealthReport]). Vrijedi i za trening
     * koji je na mobitelu već završen. Ostale naredbe se ovdje preskaču. Vraća je li se trening promijenio.
     */
    fun applyWatchHealth(commands: List<WorkoutCommand>, sessionId: UUID): Boolean {
        val reports = commands.filter { it.isHealthReport }
        if (reports.isEmpty()) return false
        val session = session(sessionId) ?: return false
        if (session.controllingDevice != DeviceRole.PHONE || session.state == SessionState.DISCARDED) return false
        // Svaki izvještaj (i završni, ako je prvi izgubljen) znači da puls i kalorije za trening mjeri sat.
        session.healthRecordedByWatch = true
        for (report in reports.filterIsInstance<WorkoutCommand.HealthRecorded>()) {
            report.activeEnergyKilocalories?.takeIf { it > 0 }?.let { session.activeEnergyKilocalories = it }
            report.averageHeartRate?.takeIf { it > 0 }?.let { session.averageHeartRate = it }
        }
        store.save()
        return true
    }

    /** Briše odbačene treninge (vidi [Outcome.Discarded]). Vraća broj obrisanih. */
    fun purgeDiscarded(): Int {
        val discarded = store.sessions.filter { it.state == SessionState.DISCARDED }
        discarded.forEach(store::delete)
        if (discarded.isNotEmpty()) store.save()
        return discarded.size
    }

    private fun write(snapshot: SessionSnapshot, session: Session) {
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
        // Kalorije i puls sa sata ne brišu se ako ih snimka (još) nema.
        snapshot.activeEnergyKilocalories?.let { session.activeEnergyKilocalories = it }
        snapshot.averageHeartRate?.let { session.averageHeartRate = it }
        snapshot.healthWorkoutId?.let { session.healthKitWorkoutId = it }
        snapshot.distanceMeters?.let { session.distanceMeters = it }
        session.lastActivityAt = snapshot.updatedAt

        val kept = snapshot.exercises.map { it.id }.toSet()
        session.exercises.filter { it.id !in kept }.forEach(store::delete)
        val existing = session.exercises.associateBy { it.id }
        for (item in snapshot.exercises) {
            val exercise = existing[item.id]
                ?: session.add(SessionExercise(item.orderIndex, item.exercise, item.inputType).also { it.id = item.id })
            exercise.orderIndex = item.orderIndex
            if (exercise.exercise != item.exercise) exercise.exercise = item.exercise
            exercise.inputType = item.inputType
            exercise.supersetGroupId = item.supersetGroupId
            exercise.restSeconds = item.restSeconds
            exercise.isRemoved = item.isRemoved
            exercise.targetRepsMin = item.targetRepsMin
            exercise.targetRepsMax = item.targetRepsMax
            exercise.loadChangeKg = item.loadChangeKg
            exercise.notes = item.notes.orEmpty()
            write(item.sets, exercise)
        }
    }

    private fun write(sets: List<SetSnapshot>, exercise: SessionExercise) {
        val kept = sets.map { it.id }.toSet()
        exercise.sets.filter { it.id !in kept }.forEach(store::delete)
        val existing = exercise.sets.associateBy { it.id }
        for (item in sets) {
            val set = existing[item.id] ?: exercise.add(SetLog(item.orderIndex, item.kind).also { it.id = item.id })
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
