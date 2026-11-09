package com.brunodobric.gymapp.stats

import java.time.Instant
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sqrt

/** Stanje napretka jedne vježbe u zadnjih nekoliko tjedana. */
enum class ExerciseStatus(val raw: String) {
    IMPROVING("improving"),
    STABLE("stable"),

    /** Stoji barem [TrendAnalysis.PLATEAU_DAYS] dana. */
    PLATEAU("plateau"),
    DECLINING("declining"),
    INSUFFICIENT_DATA("insufficientData"),
}

data class TrendPoint(val date: Instant, val value: Double)

data class ExerciseTrend(
    val status: ExerciseStatus,
    /** Relativna promjena mjesečno (0,02 = +2 % mjesečno). Pozitivno je uvijek napredak. */
    val monthlyChange: Double?,
    /** Uobičajeno kolebanje vrijednosti između treninga (udio), polazno ili naučeno iz podataka. */
    val noise: Double,
    /** Broj izvođenja u razdoblju. */
    val sessions: Int,
    val latest: Double?,
)

/** Što trend vježbe mjeri. */
enum class TrendMeasure(val raw: String) {
    /** Najbolja pouzdana procjena 1RM treninga (vježbe s teretom). */
    ONE_REP_MAX("oneRepMax"),

    /** Najviše ponavljanja u seriji (vlastita težina). */
    REPS("reps"),
}

/**
 * Trend napretka iz točaka po treningu: Theil–Senov nagib logaritma vrijednosti (medijan nagiba svih parova
 * točaka), otporan na jedan loš ili iznimno dobar dan. Promjena se uspoređuje s kolebanjem vježbe, pa
 * "napreduje" znači više od šuma, a ne samo jedan bolji dan (Hopkins 2000).
 */
object TrendAnalysis {
    const val MINIMUM_SESSIONS = 4
    const val WINDOW_WEEKS = 8

    /** Od toliko izvođenja kolebanje se uči iz podataka korisnika. */
    const val LEARNED_NOISE_SESSIONS = 6
    val noiseRange = 0.02..0.08

    /** Najmanja mjesečna promjena koja se računa kao napredak ili pad. */
    const val MINIMUM_MONTHLY_CHANGE = 0.005

    /** Vježba koja stoji ovoliko dana je na platou. */
    const val PLATEAU_DAYS = 28.0
    private const val DAY = 24 * 3600.0

    /**
     * Polazno kolebanje dok nema dovoljno podataka: složene vježbe 3 %, ostale 5 % (procjena iz pouzdanosti
     * mjerenja 1RM, Grgic i sur. 2020, i grubljih koraka težine kod izolacijskih vježbi).
     */
    fun defaultNoise(isCompound: Boolean?, measure: TrendMeasure = TrendMeasure.ONE_REP_MAX): Double {
        if (measure == TrendMeasure.REPS) return 0.08
        return if (isCompound == true) 0.03 else 0.05
    }

    fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2 else sorted[middle]
    }

    /** Medijan nagiba svih parova točaka s različitim x. Null za manje od dvije takve točke. */
    fun theilSenSlope(points: List<Pair<Double, Double>>): Double? {
        val slopes = mutableListOf<Double>()
        for (first in points.indices) {
            for (second in first + 1 until points.size) {
                if (points[second].first == points[first].first) continue
                slopes += (points[second].second - points[first].second) / (points[second].first - points[first].first)
            }
        }
        return median(slopes)
    }

    /** Trend točaka u zadnjih `windowWeeks` tjedana do `now`. `higherIsBetter` je false kad je manje bolje (npr. pomoć). */
    fun trend(
        points: List<TrendPoint>,
        now: Instant,
        windowWeeks: Int = WINDOW_WEEKS,
        higherIsBetter: Boolean = true,
        defaultNoise: Double,
    ): ExerciseTrend {
        val start = now.minusSeconds(windowWeeks * 7L * 24 * 3600)
        val window = points.filter { it.date >= start && it.date <= now && it.value > 0 }.sortedBy { it.date }
        val insufficient = ExerciseTrend(ExerciseStatus.INSUFFICIENT_DATA, null, defaultNoise, window.size, window.lastOrNull()?.value)
        if (window.size < MINIMUM_SESSIONS) return insufficient
        val first = window.first()
        val last = window.last()
        if (last.date <= first.date) return insufficient
        val sign = if (higherIsBetter) 1.0 else -1.0
        val samples = window.map { secondsBetween(first.date, it.date) / DAY to sign * ln(it.value) }
        val slope = theilSenSlope(samples) ?: return insufficient

        var noise = defaultNoise
        if (window.size >= LEARNED_NOISE_SESSIONS) {
            val intercept = median(samples.map { it.second - slope * it.first })
            val deviation = intercept?.let { b -> median(samples.map { abs(it.second - (b + slope * it.first)) }) }
            if (deviation != null) {
                // Robusna procjena standardne devijacije iz medijana apsolutnih odstupanja.
                noise = (1.4826 * deviation).coerceIn(noiseRange.start, noiseRange.endInclusive)
            }
        }
        val logMonthly = slope * 30
        val threshold = maxOf(MINIMUM_MONTHLY_CHANGE, noise / sqrt(window.size.toDouble()))
        val status = when {
            logMonthly > threshold -> ExerciseStatus.IMPROVING
            logMonthly < -threshold -> ExerciseStatus.DECLINING
            secondsBetween(first.date, last.date) / DAY >= PLATEAU_DAYS -> ExerciseStatus.PLATEAU
            else -> ExerciseStatus.STABLE
        }
        return ExerciseTrend(status, exp(logMonthly) - 1, noise, window.size, last.value)
    }

    /** Točke za trend iz napretka vježbe: procjena 1RM kad je ima, inače ponavljanja (vlastita težina). */
    fun points(progress: List<ExercisePoint>): Pair<TrendMeasure, List<TrendPoint>>? {
        val strength = progress.mapNotNull { point -> point.estimatedOneRepMaxKg?.let { TrendPoint(point.date, it) } }
        if (strength.isNotEmpty()) return TrendMeasure.ONE_REP_MAX to strength
        val hasLoad = progress.any { it.bestWeightKg > 0 }
        val reps = progress.filter { it.bestReps > 0 }.map { TrendPoint(it.date, it.bestReps.toDouble()) }
        if (!hasLoad && reps.isNotEmpty()) return TrendMeasure.REPS to reps
        return null
    }
}

/** Sekunde između dva trenutka, s milisekundama (`timeIntervalSince` na iOS-u). */
internal fun secondsBetween(from: Instant, to: Instant): Double = (to.toEpochMilli() - from.toEpochMilli()) / 1000.0

internal fun Instant.plusSecondsDouble(seconds: Double): Instant = plusMillis(Math.round(seconds * 1000))
