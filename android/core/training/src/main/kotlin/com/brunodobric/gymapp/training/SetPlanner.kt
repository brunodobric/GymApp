package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightUnit
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToLong

/** Cilj serije iz predloška ([TemplateSet]) bez veze s bazom (`SetTarget` na iOS-u). */
data class SetTarget(
    val kind: SetKind,
    val weightKg: Double? = null,
    val reps: Int? = null,
    /** Gornja granica raspona ponavljanja (dvostruka progresija, npr. 8–12). null znači fiksni cilj [reps]. */
    val repsMax: Int? = null,
) {
    /** Gornja granica cilja: kraj raspona, inače sam cilj. */
    val upperReps: Int?
        get() {
            val reps = reps ?: return null
            val max = repsMax
            return if (max != null && max > reps) max else reps
        }
}

val TemplateSet.target: SetTarget get() = SetTarget(kind, targetWeightKg, targetReps, targetRepsMax)

/** Raspon ponavljanja radnih serija (npr. 8–12). Kod fiksnog cilja su granice iste. */
data class RepRange(val lower: Int, val upper: Int)

/** Serije nove vježbe u treningu, s prijedlogom veće težine. */
data class SetPlan(
    val sets: List<SetValues>,
    /**
     * Promjena tereta radnih serija prema prošlom izvođenju, u kilogramima (dvostruka progresija):
     * pozitivna je veća težina ili dodatni teret, negativna manja pomoć. null kad se teret ne mijenja.
     */
    val loadChangeKg: Double? = null,
    /** Raspon ponavljanja radnih serija iz predloška, null bez cilja ponavljanja. */
    val repRange: RepRange? = null,
)

/**
 * Slaže serije vježbe koja se dodaje u trening ([WorkoutEngine.addExercise], `TemplateStarter`, plan za widgete),
 * isto kao `SetPlanner` na iOS-u:
 * - Bez ciljeva: onoliko zagrijavanja koliko je bilo prošli put, a radnih serija koliko ih je bilo najčešće u
 *   zadnja tri izvođenja, inače tri.
 * - Vrijednosti iz zadnjeg izvođenja po poziciji serije ([SmartDefaults]).
 * - Cilj težine iz predloška nadjačava prošli put. Raspon ponavljanja (8–12) zadržava prošla ponavljanja unutar
 *   raspona, a fiksni cilj ih upisuje.
 * - Dvostruka progresija: kad su prošli put sve radne serije dosegle gornju granicu raspona, teret ide jedan korak
 *   gore (potpomognuta vježba: pomoć korak dolje), a ponavljanja na donju granicu. Samo kad predložak ne propisuje
 *   težinu.
 */
object SetPlanner {

    fun plan(
        previous: List<SetValues>,
        recentWorkingCounts: List<Int> = emptyList(),
        targets: List<SetTarget> = emptyList(),
        inputType: ExerciseInputType,
        weightStep: Double? = null,
        unit: WeightUnit = WeightUnit.KILOGRAMS,
    ): SetPlan {
        val kinds: List<SetKind> = if (targets.isEmpty()) {
            val warmUps = previous.count { it.kind == SetKind.WARM_UP }
            val lastWorking = previous.count { it.kind == SetKind.WORKING }
            val working = SmartDefaults.workingSetCount(recentWorkingCounts)
                ?: if (lastWorking > 0) lastWorking else WorkoutEngine.DEFAULT_WORKING_SETS
            List(warmUps) { SetKind.WARM_UP } + List(working) { SetKind.WORKING }
        } else {
            targets.map { it.kind }
        }

        val sets = mutableListOf<SetValues>()
        kinds.forEachIndexed { index, kind ->
            val position = sets.count { it.kind == kind }
            var values = SmartDefaults.defaults(position, kind, previous)
                ?: sets.lastOrNull { it.kind == kind }?.let { SmartDefaults.defaults(0, kind, listOf(it)) }
                ?: SetValues(kind)
            if (index < targets.size) values = apply(targets[index], values, inputType)
            sets += values
        }

        var change: Double? = null
        if (weightStep != null && weightStep > 0 && shouldIncreaseLoad(targets, previous, inputType)) {
            change = increaseLoad(sets, targets, inputType, weightStep, unit)
        }
        return SetPlan(sets, change, repRange(targets, inputType))
    }

    /** Raspon ponavljanja prve radne serije s ciljem ponavljanja. */
    fun repRange(targets: List<SetTarget>, inputType: ExerciseInputType): RepRange? {
        if (!inputType.hasReps) return null
        val first = targets.firstOrNull { it.kind == SetKind.WORKING && it.reps != null } ?: return null
        val lower = first.reps ?: return null
        val upper = first.upperReps ?: return null
        return RepRange(lower, maxOf(lower, upper))
    }

    /** Jesu li prošli put sve planirane radne serije dosegle gornju granicu cilja ponavljanja. */
    fun shouldIncreaseLoad(targets: List<SetTarget>, previous: List<SetValues>, inputType: ExerciseInputType): Boolean {
        if (!inputType.progressesByLoad) return false
        val working = targets.filter { it.kind == SetKind.WORKING }
        if (working.isEmpty() || !working.all { it.reps != null && it.weightKg == null }) return false
        val done = previous.filter { it.kind == SetKind.WORKING }
        if (done.size < working.size) return false
        return working.zip(done).all { (target, set) ->
            val upper = target.upperReps
            val reps = set.reps
            upper != null && reps != null && reps >= upper
        }
    }

    /** Pomiče teret radnih serija za jedan korak i vraća promjenu prve pomaknute serije u kilogramima. */
    private fun increaseLoad(
        sets: MutableList<SetValues>,
        targets: List<SetTarget>,
        inputType: ExerciseInputType,
        step: Double,
        unit: WeightUnit,
    ): Double? {
        var change: Double? = null
        for (index in sets.indices) {
            val set = sets[index]
            if (set.kind != SetKind.WORKING) continue
            val reps = targets.getOrNull(index)?.reps ?: set.reps
            val updated = when (inputType) {
                ExerciseInputType.WEIGHT_REPS -> {
                    val weight = set.weightKg?.takeIf { it > 0 } ?: continue
                    val moved = stepped(weight, 1, step, unit)
                    if (change == null) change = moved - weight
                    set.copy(weightKg = moved, reps = reps)
                }
                ExerciseInputType.WEIGHTED_BODYWEIGHT -> {
                    val extra = set.extraWeightKg ?: 0.0
                    val moved = stepped(extra, 1, step, unit)
                    if (change == null) change = moved - extra
                    set.copy(extraWeightKg = moved, reps = reps)
                }
                ExerciseInputType.ASSISTED -> {
                    val help = set.extraWeightKg?.takeIf { it > 0 } ?: continue
                    val moved = stepped(help, -1, step, unit)
                    if (change == null) change = moved - help
                    set.copy(extraWeightKg = moved, reps = reps)
                }
                ExerciseInputType.BODYWEIGHT, ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> continue
            }
            sets[index] = updated
        }
        return change?.takeIf { abs(it) > 0.0001 }
    }

    /**
     * Težina nakon [steps] koraka, na sljedećoj vrijednosti na koraku (83 kg s korakom 2,5 ide na 85).
     * Korak je u jedinici prikaza, kao na kotačiću.
     */
    fun stepped(kilograms: Double, steps: Int, step: Double, unit: WeightUnit): Double {
        if (step <= 0 || steps == 0) return kilograms
        val display = WeightConversion.value(kilograms, unit)
        val position = display / step
        val tolerance = 1e-6
        val target = if (steps > 0) floor(position + tolerance) + steps else ceil(position - tolerance) + steps
        val moved = (maxOf(0.0, target * step) * 1_000_000).roundToLong() / 1_000_000.0
        return WeightConversion.kilograms(moved, unit)
    }

    private fun apply(target: SetTarget, values: SetValues, inputType: ExerciseInputType): SetValues {
        var result = values
        target.weightKg?.let { weight ->
            result = when (inputType) {
                ExerciseInputType.WEIGHT_REPS -> result.copy(weightKg = weight)
                ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> result.copy(extraWeightKg = weight)
                ExerciseInputType.BODYWEIGHT, ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> result
            }
        }
        val reps = target.reps
        if (!inputType.hasReps || reps == null) return result
        val upper = target.upperReps
        return if (target.kind == SetKind.WORKING && upper != null && upper > reps) {
            result.copy(reps = (result.reps ?: reps).coerceIn(reps, upper))
        } else {
            result.copy(reps = reps)
        }
    }
}

/** Vrsta unosa s ponavljanjima. */
val ExerciseInputType.hasReps: Boolean
    get() = when (this) {
        ExerciseInputType.WEIGHT_REPS, ExerciseInputType.BODYWEIGHT,
        ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> true
        ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> false
    }

/** Vrsta unosa kod koje se napreduje teretom (težina, dodatni teret ili manja pomoć). */
val ExerciseInputType.progressesByLoad: Boolean
    get() = when (this) {
        ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> true
        ExerciseInputType.BODYWEIGHT, ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> false
    }
