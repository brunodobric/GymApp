package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.Sex
import com.brunodobric.gymapp.training.SetMetrics
import java.time.Instant

/**
 * DOTS bodovi: zbroj čučnja, potiska s klupe i mrtvog dizanja prilagođen tjelesnoj masi, da se snaga može
 * usporediti između ljudi različite težine. Formula i koeficijenti su iz powerliftinga (Tim Konertz, 2019;
 * koristi ih OpenPowerlifting). Vrijedi samo za ta tri dizanja sa šipkom, a ovdje se računa iz procjene 1RM,
 * ne iz natjecateljskog maksimuma.
 */
object Dots {
    /** Dizanja koja ulaze u zbroj (id iz kataloga): čučanj, potisak s klupe, mrtvo dizanje. */
    val lifts = listOf("barbell-squat", "barbell-bench-press", "barbell-deadlift")

    /** Koeficijenti nazivnika od slobodnog člana do člana uz m⁴. */
    internal fun coefficients(sex: Sex): List<Double> = when (sex) {
        Sex.MALE -> listOf(-307.75076, 24.0900756, -0.1918759221, 0.0007391293, -0.000001093)
        Sex.FEMALE -> listOf(-57.96288, 13.6175032, -0.1126655495, 0.0005158568, -0.0000010706)
    }

    /** Raspon tjelesne mase za koji formula vrijedi; masa izvan njega uzima se kao granica. */
    fun bodyWeightRange(sex: Sex): ClosedFloatingPointRange<Double> = when (sex) {
        Sex.MALE -> 40.0..210.0
        Sex.FEMALE -> 40.0..150.0
    }

    /** DOTS = zbroj × 500 / (a + b·m + c·m² + d·m³ + e·m⁴). Null bez zbroja ili tjelesne mase. */
    fun points(totalKg: Double, bodyWeightKg: Double, sex: Sex): Double? {
        if (totalKg <= 0 || bodyWeightKg <= 0) return null
        val range = bodyWeightRange(sex)
        val mass = bodyWeightKg.coerceIn(range.start, range.endInclusive)
        var power = 1.0
        var denominator = 0.0
        for (coefficient in coefficients(sex)) {
            denominator += coefficient * power
            power *= mass
        }
        if (denominator <= 0) return null
        return totalKg * 500 / denominator
    }
}

/** DOTS iz najbolje procjene 1RM triju dizanja u razdoblju. */
data class DotsScore(
    /** Najbolja procjena 1RM po dizanju (id iz kataloga), samo za dizanja koja su rađena u razdoblju. */
    val liftsKg: Map<String, Double>,
    val bodyWeightKg: Double,
    val sex: Sex,
) {
    /** Dizanja koja nedostaju za zbroj. */
    val missingLifts: List<String> get() = Dots.lifts.filter { it !in liftsKg }

    /** Zbroj, samo kad su sva tri dizanja rađena. */
    val totalKg: Double? get() = if (missingLifts.isEmpty()) Dots.lifts.sumOf { liftsKg.getValue(it) } else null

    val points: Double? get() = totalKg?.let { Dots.points(it, bodyWeightKg, sex) }
}

/**
 * DOTS iz najbolje pouzdane procjene 1RM čučnja, potiska i mrtvog dizanja u zadnjih `weeks` tjedana.
 * Null kad nijedno od tri dizanja nije rađeno u razdoblju.
 */
fun StatisticsEngine.dotsScore(
    bodyWeightKg: Double,
    sex: Sex,
    weeks: Int = 12,
    now: Instant = Instant.now(),
    formula: SetMetrics.OneRepMaxFormula = SetMetrics.OneRepMaxFormula.EPLEY,
): DotsScore? {
    val start = now.minusSeconds(weeks * 7L * 24 * 3600)
    val lifts = LinkedHashMap<String, Double>()
    for (id in Dots.lifts) {
        val best = progress(ExerciseRef.catalog(id, id), formula)
            .filter { it.date >= start && it.date <= now }
            .mapNotNull { it.estimatedOneRepMaxKg }
            .maxOrNull()
        if (best != null) lifts[id] = best
    }
    if (lifts.isEmpty()) return null
    return DotsScore(lifts, bodyWeightKg, sex)
}
