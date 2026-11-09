package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import java.util.Locale

/** Vježba iz odrađenih treninga, za odabir grafa napretka i usporedbe. */
data class DoneExercise(val key: String, val name: String) {
    val id: String get() = key
    val ref: ExerciseRef? get() = ExerciseRef.fromKey(key, name)
}

object DoneExercises {
    /** Različite vježbe iz završenih treninga, abecedno. Izbačene vježbe se ne broje. */
    fun list(exercises: List<SessionExercise>, locale: Locale = Locale.getDefault()): List<DoneExercise> {
        val seen = mutableSetOf<String>()
        val result = mutableListOf<DoneExercise>()
        for (exercise in exercises) {
            if (exercise.isRemoved || exercise.session?.state != SessionState.FINISHED || exercise.exerciseKey.isEmpty()) continue
            if (seen.add(exercise.exerciseKey)) result += DoneExercise(exercise.exerciseKey, exercise.exerciseName)
        }
        val order = caseInsensitiveOrder(locale)
        return result.sortedWith { a, b -> order.compare(a.name, b.name) }
    }

    /** Vježbe iz cijele povijesti. */
    fun fetch(store: GymStore, locale: Locale = Locale.getDefault()): List<DoneExercise> =
        list(store.sessionExercises.filter { !it.isRemoved }, locale)
}
