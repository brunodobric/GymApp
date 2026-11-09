package com.brunodobric.gymapp.model

import java.time.Instant

internal val bench = ExerciseRef.catalog("bench-press", "Bench press")
internal val squat = ExerciseRef.catalog("squat", "Squat")

/** Stvara trening s jednom vježbom i zadanim serijama (težina, ponavljanja). */
internal fun GymStore.makeSession(
    exercise: ExerciseRef,
    startedAt: Instant,
    state: SessionState = SessionState.FINISHED,
    sets: List<Pair<Double, Int>> = listOf(80.0 to 8),
    removed: Boolean = false,
): Session {
    val session = insert(Session("Trening", startedAt = startedAt))
    session.state = state
    val sessionExercise = session.add(SessionExercise(0, exercise))
    sessionExercise.isRemoved = removed
    sets.forEachIndexed { index, (weight, reps) ->
        val log = sessionExercise.add(SetLog(index))
        log.weightKg = weight
        log.reps = reps
    }
    return session
}

internal fun at(seconds: Long): Instant = Instant.ofEpochSecond(seconds)
