package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.training.PersonalRecordDetector
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.values
import java.time.Instant
import java.util.Locale
import kotlin.math.floor

/** Trend jedne vježbe s podacima za prikaz i prijedloge. */
data class ExerciseTrendEntry(
    val key: String,
    val name: String,
    val measure: TrendMeasure,
    val trend: ExerciseTrend,
    val primaryRegions: List<String>,
)

/** Najteža serija s barem toliko ponavljanja (tablica rekorda po ponavljanjima). */
data class RepMaxEntry(val reps: Int, val weightKg: Double, val date: Instant)

/** Raspodjela radnih serija po ponavljanjima u rezervi (RIR 0, 1, 2, 3, 4 i više). */
data class EffortDistribution(
    /** Pet brojeva: RIR 0, 1, 2, 3, 4+. */
    val counts: MutableList<Int> = MutableList(5) { 0 },
    /** Radne serije bez upisanog RPE-a. */
    var unrated: Int = 0,
) {
    val rated: Int get() = counts.sum()
}

/** Raspodjela radnih serija po težini u odnosu na najbolju procjenu 1RM vježbe. */
data class IntensityDistribution(val counts: MutableList<Int> = MutableList(4) { 0 }) {
    val total: Int get() = counts.sum()

    companion object {
        /** Granice zona (udio 1RM): ispod 60 %, 60 do 75 %, 75 do 85 %, iznad 85 %. */
        val bounds = listOf(0.60, 0.75, 0.85)

        fun zone(share: Double): Int = bounds.indexOfFirst { share < it }.takeIf { it >= 0 } ?: bounds.size
    }
}

// MARK: Trend i status vježbi

/** Trend svake vježbe rađene u zadnjih `weeks` tjedana do `now`, abecedno. */
fun StatisticsEngine.exerciseTrends(
    weeks: Int = TrendAnalysis.WINDOW_WEEKS,
    now: Instant = Instant.now(),
    info: ExerciseInfoProvider,
    formula: SetMetrics.OneRepMaxFormula = SetMetrics.OneRepMaxFormula.EPLEY,
    locale: Locale = Locale.getDefault(),
): List<ExerciseTrendEntry> {
    val from = now.minusSeconds(weeks * 7L * 24 * 3600)
    val points = LinkedHashMap<String, MutableList<ExercisePoint>>()
    val names = mutableMapOf<String, String>()
    for (session in store.finishedSessions(from, now.plusSeconds(1))) {
        for (exercise in session.orderedExercises) {
            if (exercise.isRemoved || exercise.exerciseKey.isEmpty()) continue
            val point = StatisticsEngine.point(exercise, session.startedAt, formula) ?: continue
            points.getOrPut(exercise.exerciseKey) { mutableListOf() } += point
            names.putIfAbsent(exercise.exerciseKey, exercise.exerciseName)
        }
    }
    val order = caseInsensitiveOrder(locale)
    return points.mapNotNull { (key, progress) -> trendEntry(key, names[key] ?: "", progress, now, weeks, info) }
        .sortedWith { a, b -> order.compare(a.name, b.name) }
}

/** Trend jedne vježbe u zadnjih `weeks` tjedana. Null za vrste bez mjerljivog napretka (trajanje, udaljenost). */
fun StatisticsEngine.exerciseTrend(
    ref: ExerciseRef,
    weeks: Int = TrendAnalysis.WINDOW_WEEKS,
    now: Instant = Instant.now(),
    info: ExerciseInfoProvider,
    formula: SetMetrics.OneRepMaxFormula = SetMetrics.OneRepMaxFormula.EPLEY,
): ExerciseTrendEntry? = trendEntry(ref.key, ref.name, progress(ref, formula), now, weeks, info)

private fun trendEntry(
    key: String,
    name: String,
    progress: List<ExercisePoint>,
    now: Instant,
    weeks: Int,
    info: ExerciseInfoProvider,
): ExerciseTrendEntry? {
    val (measure, points) = TrendAnalysis.points(progress) ?: return null
    val details = info(key)
    val trend = TrendAnalysis.trend(
        points, now, weeks, defaultNoise = TrendAnalysis.defaultNoise(details?.isCompound, measure),
    )
    return ExerciseTrendEntry(key, name, measure, trend, details?.primaryRegions ?: emptyList())
}

// MARK: Tablica rekorda po ponavljanjima

/** Najteža serija za svaki raspon ponavljanja ([PersonalRecordDetector.repRanges]): s barem toliko ponavljanja. */
fun StatisticsEngine.repMaxTable(ref: ExerciseRef): List<RepMaxEntry> {
    val key = ref.key
    val best = mutableMapOf<Int, RepMaxEntry>()
    for (session in store.sessions) {
        if (session.state != SessionState.FINISHED) continue
        for (exercise in session.exercises) {
            if (exercise.exerciseKey != key || exercise.isRemoved) continue
            for (set in exercise.orderedSets) {
                if (!set.isCompleted || set.kind != SetKind.WORKING) continue
                val values = set.values
                val load = SetMetrics.load(values, exercise.inputType)?.takeIf { it > 0 } ?: continue
                val reps = values.reps ?: continue
                for (range in PersonalRecordDetector.repRanges) {
                    if (reps >= range && load > (best[range]?.weightKg ?: 0.0)) {
                        best[range] = RepMaxEntry(range, load, session.startedAt)
                    }
                }
            }
        }
    }
    return PersonalRecordDetector.repRanges.mapNotNull { best[it] }
}

// MARK: Napor i intenzitet

/** Radne serije u razdoblju po ponavljanjima u rezervi (iz upisanog RPE-a). */
fun StatisticsEngine.effortDistribution(start: Instant, end: Instant): EffortDistribution {
    val result = EffortDistribution()
    for (session in store.finishedSessions(start, end)) {
        for (exercise in session.orderedExercises) {
            if (exercise.isRemoved) continue
            for (set in exercise.orderedSets) {
                if (!set.isCompleted || set.kind != SetKind.WORKING) continue
                val rpe = set.rpe
                if (rpe == null) {
                    result.unrated += 1
                    continue
                }
                val rir = floor(maxOf(0.0, 10 - rpe)).toInt()
                result.counts[minOf(rir, 4)] += 1
            }
        }
    }
    return result
}

/**
 * Radne serije s teretom u razdoblju po udjelu najbolje procjene 1RM vježbe. Najbolja procjena gleda se
 * u razdoblju i 8 tjedana prije njega, da prvi tjedni razdoblja imaju s čime se usporediti.
 */
fun StatisticsEngine.intensityDistribution(
    start: Instant,
    end: Instant,
    formula: SetMetrics.OneRepMaxFormula = SetMetrics.OneRepMaxFormula.EPLEY,
): IntensityDistribution {
    val sessions = store.finishedSessions(start.minusSeconds(8L * 7 * 24 * 3600), end)
    val reference = mutableMapOf<String, Double>()
    for (session in sessions) for (exercise in session.orderedExercises) {
        if (exercise.isRemoved) continue
        for (set in exercise.orderedSets) {
            if (!set.isCompleted) continue
            val estimate = SetMetrics.strengthEstimate(set.values, exercise.inputType, formula) ?: continue
            reference[exercise.exerciseKey] = maxOf(reference[exercise.exerciseKey] ?: 0.0, estimate)
        }
    }
    val result = IntensityDistribution()
    for (session in sessions) {
        if (session.startedAt < start) continue
        for (exercise in session.orderedExercises) {
            if (exercise.isRemoved) continue
            val best = reference[exercise.exerciseKey]?.takeIf { it > 0 } ?: continue
            for (set in exercise.orderedSets) {
                if (!set.isCompleted || set.kind != SetKind.WORKING) continue
                val load = SetMetrics.load(set.values, exercise.inputType)?.takeIf { it > 0 } ?: continue
                result.counts[IntensityDistribution.zone(load / best)] += 1
            }
        }
    }
    return result
}
