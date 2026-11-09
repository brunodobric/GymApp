package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.WorkoutKind
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneOffset

internal val bench = ExerciseRef.catalog("bench", "Potisak s klupe")
internal val squat = ExerciseRef.catalog("squat", "Čučanj")

/** Petak 15. 1. 2027., 08:00 UTC. */
internal val base: Instant = Instant.ofEpochSecond(1_800_000_000)
internal const val DAY = 86_400L

/** UTC, tjedan od ponedjeljka (kao `calendar` u testovima GymKita). */
internal val utcMonday = StatsCalendar(ZoneOffset.UTC, DayOfWeek.MONDAY)

internal fun newStore() = GymStore(InMemoryPersistence())

internal fun Instant.plusDays(days: Double): Instant = plusMillis(Math.round(days * DAY * 1000))

internal data class Work(val weight: Double, val reps: Int, val kind: SetKind = SetKind.WORKING, val rpe: Double? = null)

internal data class Lift(val ref: ExerciseRef, val sets: List<Work>)

/** Dodaje završen trening izravno u graf (bez WorkoutEnginea), s jednim spremanjem na kraju. */
internal fun GymStore.addSession(
    at: Instant,
    kind: WorkoutKind = WorkoutKind.STRENGTH,
    lifts: List<Lift>,
    save: Boolean = true,
): Session {
    val session = insert(Session("Trening", kind, at))
    session.state = SessionState.FINISHED
    session.endedAt = at.plusSeconds(3600)
    lifts.forEachIndexed { index, lift ->
        val exercise = session.add(SessionExercise(index, lift.ref, ExerciseInputType.WEIGHT_REPS))
        lift.sets.forEachIndexed { setIndex, work ->
            val set = exercise.add(SetLog(setIndex, work.kind))
            set.weightKg = work.weight
            set.reps = work.reps
            set.rpe = work.rpe
            set.completedAt = at.plusSeconds(600)
        }
    }
    if (save) save()
    return session
}

internal val infoProvider: ExerciseInfoProvider = { key ->
    when (key) {
        "c:bench" -> ExerciseInfo(listOf(Muscle.CHEST), listOf(Muscle.TRICEPS), listOf("chest"), listOf("triceps"))
        "c:squat" -> ExerciseInfo(listOf(Muscle.QUADRICEPS), listOf(Muscle.GLUTES), listOf("quads"), listOf("glutes"))
        else -> null
    }
}
