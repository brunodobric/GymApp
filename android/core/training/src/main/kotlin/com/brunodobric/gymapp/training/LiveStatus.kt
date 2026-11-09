package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SetLog
import java.time.Instant
import java.util.UUID

/**
 * Stanje aktivnog treninga za obavijest u tijeku (Live Activity na iOS-u) i obavijest o kraju odmora:
 * trenutna i sljedeća vježba, broj serija, serija koju gumb potvrđuje i rest timer.
 */
data class LiveWorkoutStatus(
    /** Vježba sljedeće serije. Null kad su sve serije završene. */
    val currentExerciseName: String?,
    /** Prva druga vježba koja dolazi nakon trenutne (u supersetu je to partner). */
    val nextExerciseName: String?,
    /** Redni broj sljedeće serije u njezinoj vježbi (od 1) i broj serija te vježbe. */
    val setNumber: Int,
    val setCount: Int,
    /** Serija koju potvrđuje gumb u obavijesti. */
    val nextSetId: UUID?,
    /** Serija ima sve vrijednosti, pa se može potvrditi bez otvaranja aplikacije. */
    val canConfirmNextSet: Boolean,
    val completedSets: Int,
    val totalSets: Int,
    val rest: RestTimer?,
) {
    val isAllCompleted: Boolean get() = totalSets > 0 && completedSets == totalSets
}

/**
 * Nezavršene serije redom kojim ih korisnik radi. Prvo dolazi skupina (vježba ili superset) zadnje završene
 * serije, ako u njoj još ima posla, zatim ostale skupine po redoslijedu. U supersetu serije idu naizmjence.
 */
fun WorkoutEngine.remainingSets(session: Session): List<SetLog> {
    val exercises = visibleExercises(session)
    val groups = mutableListOf<List<SessionExercise>>()
    val seen = mutableSetOf<UUID>()
    for (exercise in exercises) {
        if (exercise.id in seen) continue
        val members = group(exercise)
        members.forEach { seen += it.id }
        groups += members
    }

    val lastCompleted = exercises.flatMap { it.orderedSets }.filter { it.isCompleted }
        .maxByOrNull { it.completedAt ?: Instant.MIN }
    val lastExerciseId = lastCompleted?.exercise?.id
    val index = groups.indexOfFirst { members -> members.any { it.id == lastExerciseId } }
    if (lastExerciseId != null && index >= 0) {
        val current = groups.removeAt(index)
        val hasWork = current.any { exercise -> exercise.orderedSets.any { !it.isCompleted } }
        groups.add(if (hasWork) 0 else index, current)
    }

    return groups.flatMap { members ->
        SupersetSequence.order(members.map { it.orderedSets.size })
            .map { members[it.exercise].orderedSets[it.set] }
            .filter { !it.isCompleted }
    }
}

/** Sljedeća serija za potvrdu, ili null kad je sve gotovo. */
fun WorkoutEngine.nextSet(session: Session): SetLog? = remainingSets(session).firstOrNull()

fun WorkoutEngine.liveStatus(session: Session): LiveWorkoutStatus {
    val remaining = remainingSets(session)
    val allSets = visibleExercises(session).flatMap { it.orderedSets }
    val next = remaining.firstOrNull()
    val exercise = next?.exercise
    val nextExercise = remaining.firstOrNull { it.exercise?.id != exercise?.id }?.exercise
    val setIndex = exercise?.orderedSets?.indexOfFirst { it.id == next.id }?.takeIf { it >= 0 }
    val canConfirm = next != null && exercise != null && SetMetrics.isComplete(next.values, exercise.inputType)

    return LiveWorkoutStatus(
        currentExerciseName = exercise?.exerciseName,
        nextExerciseName = nextExercise?.exerciseName,
        setNumber = setIndex?.plus(1) ?: 0,
        setCount = exercise?.orderedSets?.size ?: 0,
        nextSetId = next?.id,
        canConfirmNextSet = canConfirm,
        completedSets = allSets.count { it.isCompleted },
        totalSets = allSets.size,
        rest = restTimer(session),
    )
}

/**
 * Kad telefon zakazuje lokalnu obavijest o kraju odmora. Samo za trening koji vodi telefon; svaka promjena
 * timera (+10 / −10, preskakanje) zakazuje obavijest iznova za novi trenutak.
 */
object RestNotificationPolicy {
    /** Ispod ovoga obavijest nema smisla: odmor je praktički gotov. */
    const val MINIMUM_LEAD_SECONDS = 1.0

    fun fireDate(
        restEndsAt: Instant?,
        controllingDevice: DeviceRole,
        notificationsEnabled: Boolean,
        isSessionActive: Boolean,
        watchAlertsRest: Boolean = false,
        now: Instant,
    ): Instant? {
        if (!notificationsEnabled || !isSessionActive || controllingDevice != DeviceRole.PHONE || watchAlertsRest) return null
        if (restEndsAt == null || secondsBetween(now, restEndsAt) <= MINIMUM_LEAD_SECONDS) return null
        return restEndsAt
    }
}
