package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.InstantSerializer
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.UUIDSerializer
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Izmjena koju uređaj koji zrcali trening šalje uređaju koji ga vodi (`WorkoutCommand` na iOS-u; specifikacija:
 * "jedan uređaj vodi trening, a drugi prikazuje i može upisivati promjene"). Naredbe su na razini serije i vježbe,
 * pa se istovremene izmjene različitih serija ne poništavaju međusobno.
 */
@Serializable
sealed class WorkoutCommand {
    /** Nova ili izmijenjena serija (vrijednosti, vrsta, kvačica). */
    @Serializable
    @SerialName("upsertSet")
    data class UpsertSet(@Serializable(UUIDSerializer::class) val exerciseId: UUID, val set: SetSnapshot) : WorkoutCommand()

    @Serializable
    @SerialName("deleteSet")
    data class DeleteSet(@Serializable(UUIDSerializer::class) val setId: UUID) : WorkoutCommand()

    /**
     * Nova vježba (sa serijama) ili izmjena postojeće na razini vježbe (redoslijed, superset, pauza, izbacivanje).
     * Serije postojeće vježbe ovdje se ne diraju.
     */
    @Serializable
    @SerialName("upsertExercise")
    data class UpsertExercise(val exercise: ExerciseSnapshot) : WorkoutCommand()

    @Serializable
    @SerialName("deleteExercise")
    data class DeleteExercise(@Serializable(UUIDSerializer::class) val exerciseId: UUID) : WorkoutCommand()

    @Serializable
    @SerialName("setRestTimer")
    data class SetRestTimer(
        @Serializable(InstantSerializer::class) val startedAt: Instant?,
        @Serializable(InstantSerializer::class) val endsAt: Instant?,
    ) : WorkoutCommand()

    @Serializable
    @SerialName("setNotes")
    data class SetNotes(val notes: String) : WorkoutCommand()

    @Serializable
    @SerialName("finish")
    data class Finish(@Serializable(InstantSerializer::class) val at: Instant) : WorkoutCommand()

    @Serializable
    @SerialName("discard")
    data object Discard : WorkoutCommand()

    /**
     * Sat je za trening koji vodi mobitel pokrenuo mjerenje (puls, kalorije): na kraju će trening u Health Connect
     * spremiti mobitel s podacima sata, pa ga ne sprema bez njih.
     */
    @Serializable
    @SerialName("healthRecordingStarted")
    data object HealthRecordingStarted : WorkoutCommand()

    /** Sat je završio mjerenje: kalorije i prosječni puls. Stiže i nakon što je trening na mobitelu već završen. */
    @Serializable
    @SerialName("healthRecorded")
    data class HealthRecorded(
        val activeEnergyKilocalories: Double? = null,
        val averageHeartRate: Double? = null,
    ) : WorkoutCommand()

    /**
     * Izvještaj sata o mjerenju. Ne mijenja serije ni stanje treninga, pa se primjenjuje i na završen trening
     * ([SessionSnapshotStore.applyWatchHealth]).
     */
    val isHealthReport: Boolean get() = this is HealthRecordingStarted || this is HealthRecorded
}

/** Naredbe iz razlike dviju snimki i njihova primjena (`SnapshotDiff` na iOS-u). */
object SnapshotDiff {

    /**
     * Naredbe koje iz [base] daju [edited]. Primijenjene redom ([apply]) na [base] daju isti trening kao [edited]
     * (osim vremena zadnje promjene).
     */
    fun commands(base: SessionSnapshot, edited: SessionSnapshot): List<WorkoutCommand> {
        val result = mutableListOf<WorkoutCommand>()
        val baseExercises = base.exercises.associateBy { it.id }
        val editedIds = edited.exercises.map { it.id }.toSet()

        for (exercise in edited.orderedExercises) {
            val old = baseExercises[exercise.id]
            if (old == null) {
                result += WorkoutCommand.UpsertExercise(exercise)
                continue
            }
            if (old.withoutSets != exercise.withoutSets) result += WorkoutCommand.UpsertExercise(exercise.withoutSets)
            val oldSets = old.sets.associateBy { it.id }
            for (set in exercise.orderedSets) {
                if (oldSets[set.id] != set) result += WorkoutCommand.UpsertSet(exercise.id, set)
            }
            val newSetIds = exercise.sets.map { it.id }.toSet()
            for (set in old.orderedSets) {
                if (set.id !in newSetIds) result += WorkoutCommand.DeleteSet(set.id)
            }
        }
        for (exercise in base.orderedExercises) {
            if (exercise.id !in editedIds) result += WorkoutCommand.DeleteExercise(exercise.id)
        }
        if (base.restTimerStartedAt != edited.restTimerStartedAt || base.restTimerEndsAt != edited.restTimerEndsAt) {
            result += WorkoutCommand.SetRestTimer(edited.restTimerStartedAt, edited.restTimerEndsAt)
        }
        if (base.notes != edited.notes) result += WorkoutCommand.SetNotes(edited.notes)
        if (base.state == SessionState.ACTIVE) {
            when (edited.state) {
                SessionState.FINISHED -> result += WorkoutCommand.Finish(edited.endedAt ?: edited.updatedAt)
                SessionState.DISCARDED -> result += WorkoutCommand.Discard
                SessionState.ACTIVE -> Unit
            }
        }
        return result
    }

    /**
     * Primjenjuje naredbe na snimku. Naredba za seriju ili vježbu koja više ne postoji se preskače. Završetak čisti
     * trening kao `WorkoutEngine.finishSession` ([SnapshotEngine.finish]).
     */
    fun apply(commands: List<WorkoutCommand>, snapshot: SessionSnapshot, now: Instant): SessionSnapshot {
        var result = snapshot
        for (command in commands) result = apply(command, result)
        return result.copy(updatedAt = maxOf(result.updatedAt, now.truncatedToMillis()))
    }

    private fun apply(command: WorkoutCommand, snapshot: SessionSnapshot): SessionSnapshot = when (command) {
        is WorkoutCommand.UpsertSet -> snapshot.copy(
            exercises = snapshot.exercises.map { exercise ->
                if (exercise.id != command.exerciseId) {
                    exercise
                } else if (exercise.sets.any { it.id == command.set.id }) {
                    exercise.copy(sets = exercise.sets.map { if (it.id == command.set.id) command.set else it })
                } else {
                    exercise.copy(sets = exercise.sets + command.set)
                }
            },
        )
        is WorkoutCommand.DeleteSet -> snapshot.copy(
            exercises = snapshot.exercises.map { exercise -> exercise.copy(sets = exercise.sets.filter { it.id != command.setId }) },
        )
        is WorkoutCommand.UpsertExercise -> {
            val existing = snapshot.exercise(command.exercise.id)
            if (existing != null) {
                val updated = command.exercise.copy(sets = existing.sets)
                snapshot.copy(exercises = snapshot.exercises.map { if (it.id == updated.id) updated else it })
            } else {
                snapshot.copy(exercises = snapshot.exercises + command.exercise)
            }
        }
        is WorkoutCommand.DeleteExercise -> snapshot.copy(exercises = snapshot.exercises.filter { it.id != command.exerciseId })
        is WorkoutCommand.SetRestTimer -> snapshot.copy(restTimerStartedAt = command.startedAt, restTimerEndsAt = command.endsAt)
        is WorkoutCommand.SetNotes -> snapshot.copy(notes = command.notes)
        is WorkoutCommand.Finish -> {
            if (snapshot.state != SessionState.ACTIVE) {
                snapshot
            } else {
                // Uređaj koji zrcali već je provjerio da postoji završena serija; ako nije, trening ostaje otvoren.
                val engine = SnapshotEngine(snapshot)
                if (runCatching { engine.finish(command.at) }.isSuccess) engine.snapshot else snapshot
            }
        }
        WorkoutCommand.Discard -> snapshot.copy(state = SessionState.DISCARDED)
        WorkoutCommand.HealthRecordingStarted -> snapshot
        is WorkoutCommand.HealthRecorded -> snapshot.copy(
            activeEnergyKilocalories = command.activeEnergyKilocalories?.takeIf { it > 0 } ?: snapshot.activeEnergyKilocalories,
            averageHeartRate = command.averageHeartRate?.takeIf { it > 0 } ?: snapshot.averageHeartRate,
        )
    }
}

/** Protokol prenosi milisekunde: vrijeme se zaokružuje isto na oba uređaja, da usporedba novijeg bude točna. */
internal fun Instant.truncatedToMillis(): Instant = Instant.ofEpochMilli(toEpochMilli())
