package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.training.CardioPart
import com.brunodobric.gymapp.training.SessionCardio
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.SetValues
import com.brunodobric.gymapp.training.values
import java.time.Instant

/**
 * Usporedba treninga s prošlim izvođenjem istog treninga (isti predložak). Tonaža ovdje ima smisla,
 * jer se isti trening uspoređuje sam sa sobom.
 */
data class SessionComparison(
    val previousDate: Instant,
    val hardSets: Int,
    val previousHardSets: Int,
    val volumeKg: Double,
    val previousVolumeKg: Double,
    val durationSeconds: Double?,
    val previousDurationSeconds: Double?,
    /** Kardio dio ovog i prošlog izvođenja ([SessionCardio.part]); null bez kardio vježbi. */
    val cardio: CardioPart? = null,
    val previousCardio: CardioPart? = null,
) {
    /** Relativna promjena tonaže (0,04 = +4 %). Null kad prošli put nije bilo tonaže. */
    val volumeChange: Double? get() = if (previousVolumeKg > 0) volumeKg / previousVolumeKg - 1 else null
}

/** Rezultat jedne vježbe u treningu: najbolja serija i procjena 1RM uz promjenu prema prošlom izvođenju. */
data class ExerciseResult(
    val key: String,
    val name: String,
    val inputType: ExerciseInputType,
    val bestSet: SetValues?,
    val oneRepMaxKg: Double?,
    val previousOneRepMaxKg: Double?,
    val hardSets: Int,
    /** Medijan odmora između serija (sekunde), iz vremena označavanja serija. */
    val restSeconds: Double?,
) {
    val id: String get() = key

    /** Relativna promjena procjene 1RM prema prošlom izvođenju. */
    val change: Double?
        get() {
            val now = oneRepMaxKg ?: return null
            val before = previousOneRepMaxKg ?: return null
            return if (before > 0) now / before - 1 else null
        }
}

object SessionMetrics {
    /** Odmor dulji od ovoga je stanka (npr. promjena sprave), ne odmor između serija. */
    const val MAXIMUM_REST: Double = 15.0 * 60

    /** Medijan razmaka između uzastopnih završenih serija. Null za manje od dvije serije. */
    fun medianRest(completions: List<Instant>): Double? {
        val sorted = completions.sorted()
        val gaps = sorted.zipWithNext { a, b -> secondsBetween(a, b) }.filter { it > 0 && it <= MAXIMUM_REST }
        return TrendAnalysis.median(gaps)
    }

    /**
     * Najbolja serija za prikaz: najveća pouzdana procjena 1RM, inače najveći volumen, ponavljanja,
     * trajanje ili udaljenost.
     */
    fun bestSet(sets: List<SetValues>, inputType: ExerciseInputType): SetValues? {
        val working = sets.filter { it.kind == SetKind.WORKING }
        val best = working.maxByOrNull { SetMetrics.strengthEstimate(it, inputType) ?: 0.0 }
        if (best != null && SetMetrics.strengthEstimate(best, inputType) != null) return best
        return when (inputType) {
            ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT ->
                working.maxByOrNull { SetMetrics.volume(it, inputType) }
            ExerciseInputType.BODYWEIGHT -> working.maxByOrNull { it.reps ?: 0 }
            ExerciseInputType.ASSISTED -> working.minByOrNull { it.extraWeightKg ?: 0.0 }
            ExerciseInputType.DURATION -> working.maxByOrNull { it.durationSeconds ?: 0 }
            ExerciseInputType.DURATION_DISTANCE -> working.maxByOrNull { it.distanceMeters ?: 0.0 }
        }
    }
}

/**
 * Usporedba s prethodnim završenim treningom istog predloška. Null bez predloška ili bez ranijeg treninga.
 * Kardio vježbe ([isCardio]) ne broje se u tvrde serije; njihovo vrijeme i udaljenost su u `cardio`.
 */
fun StatisticsEngine.comparison(session: Session, isCardio: (String) -> Boolean = { false }): SessionComparison? {
    val templateId = session.templateId ?: return null
    val previous = store.sessions
        .filter {
            it.templateId == templateId && it.state == SessionState.FINISHED &&
                it.startedAt < session.startedAt && it.id != session.id
        }
        .maxByOrNull { it.startedAt } ?: return null
    val now = totals(session, isCardio)
    val before = totals(previous, isCardio)
    return SessionComparison(
        previousDate = previous.startedAt,
        hardSets = now.first,
        previousHardSets = before.first,
        volumeKg = now.second,
        previousVolumeKg = before.second,
        durationSeconds = session.endedAt?.let { secondsBetween(session.startedAt, it) },
        previousDurationSeconds = previous.endedAt?.let { secondsBetween(previous.startedAt, it) },
        cardio = SessionCardio.part(session, isCardio),
        previousCardio = SessionCardio.part(previous, isCardio),
    )
}

private fun totals(session: Session, isCardio: (String) -> Boolean): Pair<Int, Double> {
    var hard = 0
    var volume = 0.0
    for (exercise in session.orderedExercises.filter { !it.isRemoved }) {
        val done = exercise.orderedSets.filter { it.isCompleted }.map { it.values }
        if (!isCardio(exercise.exerciseKey)) hard += done.count(SetMetrics::isHard)
        volume += done.sumOf { SetMetrics.volume(it, exercise.inputType) }
    }
    return hard to volume
}

/** Rezultat svake vježbe treninga s promjenom prema prošlom izvođenju te vježbe (prije ovog treninga). */
fun StatisticsEngine.exerciseResults(
    session: Session,
    formula: SetMetrics.OneRepMaxFormula = SetMetrics.OneRepMaxFormula.EPLEY,
): List<ExerciseResult> = session.orderedExercises.filter { !it.isRemoved }.mapNotNull { exercise ->
    val completed = exercise.orderedSets.filter { it.isCompleted }
    val done = completed.map { it.values }
    if (done.none { it.kind == SetKind.WORKING }) return@mapNotNull null
    val type = exercise.inputType
    val oneRepMax = done.mapNotNull { SetMetrics.strengthEstimate(it, type, formula) }.maxOrNull()
    val previous = previousPerformance(exercise.exerciseKey, session)
    val previousOneRepMax = previous?.orderedSets?.filter { it.isCompleted }?.map { it.values }
        ?.mapNotNull { SetMetrics.strengthEstimate(it, previous.inputType, formula) }?.maxOrNull()
    ExerciseResult(
        key = exercise.exerciseKey,
        name = exercise.exerciseName,
        inputType = type,
        bestSet = SessionMetrics.bestSet(done, type),
        oneRepMaxKg = oneRepMax,
        previousOneRepMaxKg = previousOneRepMax,
        hardSets = done.count(SetMetrics::isHard),
        restSeconds = SessionMetrics.medianRest(completed.mapNotNull { it.completedAt }),
    )
}

/** Zadnje izvođenje vježbe u završenom treningu prije [session]. */
private fun StatisticsEngine.previousPerformance(key: String, session: Session): SessionExercise? {
    if (key.isEmpty()) return null
    return store.sessionExercises
        .filter { it.exerciseKey == key && !it.isRemoved }
        .filter { exercise ->
            val owner = exercise.session ?: return@filter false
            owner.state == SessionState.FINISHED && owner.id != session.id && owner.startedAt < session.startedAt
        }
        .maxByOrNull { it.session?.startedAt ?: Instant.MIN }
}
