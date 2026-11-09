package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.model.WorkoutTemplate

/** Kako trening izgleda u povijesti: snaga, kardio ili snaga s kardio dijelom. Računa se iz vježbi. */
enum class SessionMix {
    STRENGTH,
    CARDIO,

    /** Trening snage s barem jednom odrađenom kardio vježbom. */
    MIXED,
    ;

    /** Vrste pod kojima se trening nalazi u filteru povijesti. Mješoviti trening je u obje. */
    val kinds: Set<WorkoutKind>
        get() = when (this) {
            STRENGTH -> setOf(WorkoutKind.STRENGTH)
            CARDIO -> setOf(WorkoutKind.CARDIO)
            MIXED -> setOf(WorkoutKind.STRENGTH, WorkoutKind.CARDIO)
        }
}

/** Kardio dio jednog treninga: zbroj odrađenih serija kardio vježbi. */
data class CardioPart(
    val seconds: Int,
    /** Ukupna udaljenost; null kad ni jedna serija nema udaljenost. */
    val meters: Double? = null,
)

/** Kardio vježbe unutar treninga snage. Pozivatelj daje `isCardio` po ključu vježbe. */
object SessionCardio {

    /** Odrađene vježbe: nisu izbačene i imaju barem jednu seriju s kvačicom. */
    private fun doneExercises(session: Session): List<SessionExercise> =
        session.orderedExercises.filter { exercise -> !exercise.isRemoved && exercise.sets.any { it.isCompleted } }

    /** Zbroj odrađenih kardio vježbi treninga; null kad ih nema. */
    fun part(session: Session, isCardio: (String) -> Boolean): CardioPart? {
        val cardio = doneExercises(session).filter { isCardio(it.exerciseKey) }
        if (cardio.isEmpty()) return null
        val sets = cardio.flatMap { it.orderedSets }.filter { it.isCompleted }
        val seconds = sets.sumOf { maxOf(0, it.durationSeconds ?: 0) }
        val distances = sets.mapNotNull { it.distanceMeters }.filter { it > 0 }
        return CardioPart(seconds, if (distances.isEmpty()) null else distances.sum())
    }

    /** Vrsta predloška iz njegovih vježbi. Kardio plan je uvijek kardio, prazan predložak je snaga. */
    fun mix(template: WorkoutTemplate, isCardio: (String) -> Boolean): SessionMix {
        if (template.kind != WorkoutKind.STRENGTH) return SessionMix.CARDIO
        val exercises = template.orderedExercises
        val cardio = exercises.count { isCardio(it.exercise.key) }
        return when (cardio) {
            0 -> SessionMix.STRENGTH
            exercises.size -> SessionMix.CARDIO
            else -> SessionMix.MIXED
        }
    }

    /** Vrsta za prikaz. Trening snage u kojem su odrađene samo kardio vježbe prikazuje se kao kardio. */
    fun mix(session: Session, isCardio: (String) -> Boolean): SessionMix {
        if (session.kind != WorkoutKind.STRENGTH) return SessionMix.CARDIO
        val done = doneExercises(session)
        val cardio = done.count { isCardio(it.exerciseKey) }
        return when (cardio) {
            0 -> SessionMix.STRENGTH
            done.size -> SessionMix.CARDIO
            else -> SessionMix.MIXED
        }
    }
}
