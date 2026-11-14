package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightUnit
import java.time.Instant
import kotlin.math.roundToLong

/**
 * Serije zagrijavanja do radne težine: prazna šipka × 10, 40 % × 5, 60 % × 3 i 80 % × 1.
 * Težine se zaokružuju na korak težine (u jedinici prikaza, kao na kotačiću), a serija koja je jednaka
 * prethodnoj ili nije lakša od radne težine se preskače. Isto kao `WarmUpGenerator` na iOS-u.
 */
object WarmUpGenerator {

    /** Udio radne težine i ponavljanja nakon prazne šipke. */
    internal val ramp: List<Pair<Double, Int>> = listOf(0.4 to 5, 0.6 to 3, 0.8 to 1)

    /** [barKg] je težina šipke za vježbe sa šipkom, null za ostale (tada nema serije s praznom šipkom). */
    fun sets(workingWeightKg: Double, barKg: Double?, step: Double, unit: WeightUnit): List<SetValues> {
        if (workingWeightKg <= 0) return emptyList()
        val tolerance = 1e-6
        val result = mutableListOf<SetValues>()
        var last = 0.0
        if (barKg != null && barKg > 0 && barKg < workingWeightKg - tolerance) {
            result += SetValues(SetKind.WARM_UP, weightKg = barKg, reps = 10)
            last = barKg
        }
        for ((fraction, reps) in ramp) {
            val weight = rounded(workingWeightKg * fraction, step, unit)
            if (weight <= last + tolerance || weight >= workingWeightKg - tolerance) continue
            result += SetValues(SetKind.WARM_UP, weightKg = weight, reps = reps)
            last = weight
        }
        return result
    }

    /** Najbliža težina na koraku, u kilogramima. */
    internal fun rounded(kilograms: Double, step: Double, unit: WeightUnit): Double {
        if (step <= 0) return kilograms
        val display = WeightConversion.value(kilograms, unit)
        val moved = (Math.round(display / step) * step * 1_000_000).roundToLong() / 1_000_000.0
        return WeightConversion.kilograms(moved, unit)
    }
}

/** Nudi li se "Dodaj zagrijavanje": vježba s težinom, bez zagrijavanja i s upisanom težinom radne serije. */
fun WorkoutEngine.canAddWarmUps(exercise: SessionExercise): Boolean =
    exercise.inputType == ExerciseInputType.WEIGHT_REPS &&
        exercise.orderedSets.none { it.kind == SetKind.WARM_UP } &&
        exercise.orderedSets.any { it.kind == SetKind.WORKING && (it.weightKg ?: 0.0) > 0 }

/**
 * Dodaje zagrijavanje do težine prve radne serije, ispred prve neodrađene serije. Samo kad je
 * [canAddWarmUps]. Vraća broj dodanih serija.
 */
fun WorkoutEngine.addWarmUps(
    exercise: SessionExercise,
    barKg: Double?,
    step: Double,
    unit: WeightUnit,
    now: Instant = Instant.now(),
): Int {
    if (!canAddWarmUps(exercise)) return 0
    val sets = exercise.orderedSets
    val weight = sets.firstOrNull { it.kind == SetKind.WORKING && !it.isCompleted }?.weightKg
        ?: sets.firstOrNull { it.kind == SetKind.WORKING }?.weightKg
        ?: return 0
    val planned = WarmUpGenerator.sets(weight, barKg, step, unit)
    if (planned.isEmpty()) return 0
    val ordered = sets.toMutableList()
    val insertIndex = ordered.indexOfFirst { !it.isCompleted }.takeIf { it >= 0 } ?: ordered.size
    planned.forEachIndexed { offset, values ->
        val set = exercise.add(SetLog(insertIndex + offset, SetKind.WARM_UP))
        set.weightKg = values.weightKg
        set.reps = values.reps
        ordered.add(insertIndex + offset, set)
    }
    ordered.forEachIndexed { index, item -> item.orderIndex = index }
    exercise.session?.let { touch(it, now) }
    return planned.size
}
