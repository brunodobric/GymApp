package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog

/** Vrijednosti jedne serije bez veze s bazom: ulaz za volumen, rekorde i smart defaults. Težine su u kg. */
data class SetValues(
    val kind: SetKind = SetKind.WORKING,
    val weightKg: Double? = null,
    val reps: Int? = null,
    /** Dodatna težina (vlastita težina + teret) ili pomoć (potpomognuta vježba). */
    val extraWeightKg: Double? = null,
    val durationSeconds: Int? = null,
    val distanceMeters: Double? = null,
    val rpe: Double? = null,
)

val SetLog.values: SetValues
    get() = SetValues(kind, weightKg, reps, extraWeightKg, durationSeconds, distanceMeters, rpe)

object SetMetrics {

    /** Volumen serije po vrsti unosa. Warm-up se nikad ne računa; vježbe bez tereta nemaju volumen. */
    fun volume(set: SetValues, inputType: ExerciseInputType): Double {
        if (set.kind != SetKind.WORKING) return 0.0
        return when (inputType) {
            ExerciseInputType.WEIGHT_REPS -> (set.weightKg ?: 0.0) * (set.reps ?: 0)
            ExerciseInputType.WEIGHTED_BODYWEIGHT -> (set.extraWeightKg ?: 0.0) * (set.reps ?: 0)
            ExerciseInputType.BODYWEIGHT, ExerciseInputType.ASSISTED,
            ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> 0.0
        }
    }

    enum class OneRepMaxFormula { EPLEY, BRZYCKI }

    /**
     * Procjena 1RM. [rir] su ponavljanja u rezervi: računa se s ponavljanjima do otkaza (reps + RIR).
     * Null kad se ne može izračunati (bez težine ili ponavljanja, Brzycki od 37 ponavljanja do otkaza).
     */
    fun estimatedOneRepMax(
        weightKg: Double,
        reps: Int,
        rir: Double = 0.0,
        formula: OneRepMaxFormula = OneRepMaxFormula.EPLEY,
    ): Double? {
        if (weightKg <= 0 || reps < 1) return null
        val toFailure = reps + maxOf(0.0, rir)
        if (toFailure <= 1) return weightKg
        return when (formula) {
            OneRepMaxFormula.EPLEY -> weightKg * (1 + toFailure / 30)
            OneRepMaxFormula.BRZYCKI -> if (toFailure < 37) weightKg * 36 / (37 - toFailure) else null
        }
    }

    /** Najviše ponavljanja do otkaza s kojima je procjena 1RM pouzdana. */
    const val RELIABLE_REPS_TO_FAILURE = 12.0

    /** Ponavljanja u rezervi iz RPE-a (RIR = 10 − RPE). Bez RPE-a pretpostavlja se otkaz (RIR 0). */
    fun repsInReserve(set: SetValues): Double = set.rpe?.let { maxOf(0.0, 10 - it) } ?: 0.0

    /** Teret serije za procjenu snage: težina ili dodatni teret. Null za vrste bez tereta. */
    fun load(set: SetValues, inputType: ExerciseInputType): Double? = when (inputType) {
        ExerciseInputType.WEIGHT_REPS -> set.weightKg
        ExerciseInputType.WEIGHTED_BODYWEIGHT -> set.extraWeightKg
        ExerciseInputType.BODYWEIGHT, ExerciseInputType.ASSISTED,
        ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> null
    }

    /** Pouzdana procjena 1RM radne serije: s RIR-om iz RPE-a i samo do 12 ponavljanja do otkaza. */
    fun strengthEstimate(
        set: SetValues,
        inputType: ExerciseInputType,
        formula: OneRepMaxFormula = OneRepMaxFormula.EPLEY,
    ): Double? {
        if (set.kind != SetKind.WORKING) return null
        val load = load(set, inputType) ?: return null
        val reps = set.reps?.takeIf { it >= 1 } ?: return null
        val rir = repsInReserve(set)
        if (reps + rir > RELIABLE_REPS_TO_FAILURE) return null
        return estimatedOneRepMax(load, reps, rir, formula)
    }

    /** Najmanji RPE s kojim se serija broji kao tvrda (RPE 6 = RIR 4). */
    const val MINIMUM_HARD_RPE = 6.0

    /** Tvrda serija: radna, bez upisanog RPE-a ispod [MINIMUM_HARD_RPE]. */
    fun isHard(set: SetValues): Boolean {
        if (set.kind != SetKind.WORKING) return false
        val rpe = set.rpe
        return rpe == null || rpe >= MINIMUM_HARD_RPE
    }

    /** Ima li serija sve što vrsta unosa traži da bi se mogla označiti kvačicom. */
    fun isComplete(set: SetValues, inputType: ExerciseInputType): Boolean = when (inputType) {
        ExerciseInputType.WEIGHT_REPS -> set.weightKg != null && (set.reps ?: 0) > 0
        ExerciseInputType.BODYWEIGHT, ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> (set.reps ?: 0) > 0
        ExerciseInputType.DURATION -> (set.durationSeconds ?: 0) > 0
        ExerciseInputType.DURATION_DISTANCE -> (set.durationSeconds ?: 0) > 0 || (set.distanceMeters ?: 0.0) > 0
    }
}

object SmartDefaults {
    /**
     * Zadane vrijednosti za seriju na zadanoj poziciji, iz zadnjeg izvođenja iste vježbe. Pozicija se računa
     * zasebno za warm-up i radne serije; kad je novih serija više, koristi se zadnja. RPE se ne prenosi.
     */
    fun defaults(position: Int, kind: SetKind, previous: List<SetValues>): SetValues? {
        val sameKind = previous.filter { it.kind == kind }
        if (sameKind.isEmpty()) return null
        return sameKind[position.coerceIn(0, sameKind.size - 1)].copy(kind = kind, rpe = null)
    }

    /**
     * Koliko radnih serija planirati: najčešći broj u zadnjim izvođenjima (od najnovijeg), a kod izjednačenja
     * noviji. Tako jedan prekinut trening s dvije serije ne smanji sljedeći plan. null bez povijesti.
     */
    fun workingSetCount(recent: List<Int>): Int? {
        val counts = recent.filter { it > 0 }
        if (counts.isEmpty()) return null
        val tally = counts.groupingBy { it }.eachCount()
        val best = tally.values.max()
        return counts.first { tally[it] == best }
    }

    /** Broj zadnjih izvođenja koja odlučuju o broju radnih serija. */
    const val RECENT_PERFORMANCE_COUNT = 3
}

/**
 * Završene serije zadnjeg izvođenja vježbe: prethodne vrijednosti i izvor smart defaultsa. S [templateId]
 * prvo zadnje izvođenje u treningu iz istog predloška (teški i lagani dan s istom vježbom se ne miješaju).
 */
fun GymStore.previousSetValues(exercise: ExerciseRef, templateId: java.util.UUID? = null): List<SetValues> =
    lastPerformance(exercise, templateId)?.orderedSets?.filter { it.isCompleted }?.map { it.values }.orEmpty()
