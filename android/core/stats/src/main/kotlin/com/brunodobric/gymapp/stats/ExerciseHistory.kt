package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.PersonalRecordDetector
import com.brunodobric.gymapp.training.RecordHistory
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.SetValues
import com.brunodobric.gymapp.training.values
import java.time.Instant
import java.util.UUID

/** Jedno izvođenje vježbe u završenom treningu, za povijest na detalju vježbe. */
data class ExercisePerformance(
    /** Id vježbe u treningu (`SessionExercise.id`): ista vježba može biti dvaput u istom treningu. */
    val id: UUID,
    val sessionId: UUID,
    val sessionName: String,
    val date: Instant,
    val inputType: ExerciseInputType,
    /** Završene radne serije redom, bez zagrijavanja. */
    val sets: List<SetValues>,
    /** Je li u ovom izvođenju postavljen rekord koji ide u sažetak treninga. */
    val hasRecord: Boolean,
)

/** Istaknuta brojka iz povijesti vježbe, ovisno o vrsti unosa. */
sealed interface ExerciseHistoryHighlight {
    /** Najteža serija (kg); uz vlastitu težinu to je dodatni teret. */
    data class Heaviest(val kg: Double) : ExerciseHistoryHighlight

    /** Najbolja pouzdana procjena 1RM (kg). */
    data class OneRepMax(val kg: Double) : ExerciseHistoryHighlight
    data class MostReps(val reps: Int) : ExerciseHistoryHighlight
    data class LongestDuration(val seconds: Int) : ExerciseHistoryHighlight
    data class LongestDistance(val meters: Double) : ExerciseHistoryHighlight
}

/** Sva izvođenja jedne vježbe, od najnovijeg. */
data class ExerciseHistory(val performances: List<ExercisePerformance>) {
    val isEmpty: Boolean get() = performances.isEmpty()
    val count: Int get() = performances.size

    /**
     * Najviše dvije brojke uz broj izvođenja. Vrsta unosa je ona iz zadnjeg izvođenja, a gledaju se samo
     * izvođenja s istom vrstom (vlastitoj vježbi se vrsta unosa može promijeniti).
     */
    val highlights: List<ExerciseHistoryHighlight>
        get() {
            val type = performances.firstOrNull()?.inputType ?: return emptyList()
            val sets = performances.filter { it.inputType == type }.flatMap { it.sets }
            val result = mutableListOf<ExerciseHistoryHighlight>()
            fun longestDuration() {
                val seconds = sets.mapNotNull { it.durationSeconds }.maxOrNull() ?: 0
                if (seconds > 0) result += ExerciseHistoryHighlight.LongestDuration(seconds)
            }
            when (type) {
                ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT -> {
                    val heaviest = sets.mapNotNull { SetMetrics.load(it, type) }.maxOrNull() ?: 0.0
                    if (heaviest > 0) result += ExerciseHistoryHighlight.Heaviest(heaviest)
                    sets.mapNotNull { SetMetrics.strengthEstimate(it, type) }.maxOrNull()
                        ?.let { result += ExerciseHistoryHighlight.OneRepMax(it) }
                }
                ExerciseInputType.BODYWEIGHT, ExerciseInputType.ASSISTED -> {
                    val reps = sets.mapNotNull { it.reps }.maxOrNull() ?: 0
                    if (reps > 0) result += ExerciseHistoryHighlight.MostReps(reps)
                }
                ExerciseInputType.DURATION -> longestDuration()
                ExerciseInputType.DURATION_DISTANCE -> {
                    val meters = sets.mapNotNull { it.distanceMeters }.maxOrNull() ?: 0.0
                    if (meters > 0) result += ExerciseHistoryHighlight.LongestDistance(meters)
                    longestDuration()
                }
            }
            return result
        }

    /** Izvođenja po mjesecima, od najnovijeg. */
    fun byMonth(calendar: StatsCalendar = StatsCalendar.system()): List<ExerciseHistoryMonth> {
        val result = mutableListOf<ExerciseHistoryMonth>()
        for (performance in performances) {
            val start = calendar.monthInterval(performance.date).start
            val last = result.lastOrNull()
            if (last != null && last.start == start) {
                last.performances += performance
            } else {
                result += ExerciseHistoryMonth(start, mutableListOf(performance))
            }
        }
        return result
    }
}

/** Izvođenja jednog mjeseca. [start] je početak mjeseca. */
data class ExerciseHistoryMonth(val start: Instant, val performances: MutableList<ExercisePerformance>) {
    val id: Instant get() = start
}

/**
 * Povijest vježbe iz završenih treninga. Izvođenja bez završene radne serije se ne broje.
 * Rekordi se traže kao u `personalRecords`; prazan [recordKinds] znači bez oznake rekorda.
 */
fun StatisticsEngine.history(ref: ExerciseRef, recordKinds: Set<PRKind> = PRKind.entries.toSet()): ExerciseHistory {
    val key = ref.key
    val done = store.sessionExercises
        .filter { it.exerciseKey == key && !it.isRemoved }
        .mapNotNull { exercise ->
            val session = exercise.session?.takeIf { it.state == SessionState.FINISHED } ?: return@mapNotNull null
            exercise to session
        }
        .sortedWith(compareBy({ it.second.startedAt }, { it.first.orderIndex }))

    val past = RecordHistory()
    val performances = mutableListOf<ExercisePerformance>()
    for ((exercise, session) in done) {
        val completed = exercise.orderedSets.filter { it.isCompleted }.map { it.values }
        val working = completed.filter { it.kind == SetKind.WORKING }
        if (working.isEmpty()) continue
        val records = if (recordKinds.isEmpty()) emptyList() else PersonalRecordDetector.records(
            completed, past, exercise.inputType, recordKinds, session.startedAt,
        )
        past.add(completed, exercise.inputType, session.startedAt)
        performances += ExercisePerformance(
            id = exercise.id,
            sessionId = session.id,
            sessionName = session.name,
            date = session.startedAt,
            inputType = exercise.inputType,
            sets = working,
            hasRecord = records.any { it.showsInSummary },
        )
    }
    return ExerciseHistory(performances.reversed())
}
