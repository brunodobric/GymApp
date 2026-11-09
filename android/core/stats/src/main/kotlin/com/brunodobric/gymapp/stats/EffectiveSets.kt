package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.SetValues
import com.brunodobric.gymapp.training.values

/**
 * Tvrde serije: mjera volumena po mišiću za heatmap, graf serija i usporedbu razdoblja.
 *
 * Broje se završene radne serije. Serija s upisanim RPE-om ispod [MINIMUM_RPE] (RIR 5 i više) je preslaba
 * da bi se brojala; serija bez RPE-a broji se uvijek. Regija kojoj je vježba glavni mišić dobiva cijelu
 * seriju, a regija koja samo pomaže pola (frakcijsko brojanje, Pelland i sur., Sports Medicine).
 * Kilogrami se namjerno ne broje: tonaža nije usporediva između mišića različite veličine.
 */
object EffectiveSets {
    /** Udio serije za regiju koja samo pomaže. */
    const val SECONDARY_WEIGHT = 0.5

    /** Najmanji RPE s kojim se serija broji (RPE 6 = RIR 4). */
    const val MINIMUM_RPE = SetMetrics.MINIMUM_HARD_RPE

    /** Je li serija dovoljno teška da se broji. */
    fun isHard(set: SetValues): Boolean = SetMetrics.isHard(set)

    /** Tvrde serije jedne vježbe: završene, radne, bez preslabih. */
    fun hardSets(exercise: SessionExercise): List<SetValues> {
        if (exercise.isRemoved) return emptyList()
        return exercise.orderedSets.filter { it.isCompleted }.map { it.values }.filter(::isHard)
    }

    /**
     * Tvrde serije po regiji za jednu vježbu: glavne i pomoćne odvojeno (pomoćne još nisu prepolovljene).
     * Regija koja je i glavna i pomoćna broji se samo kao glavna.
     */
    fun regionCounts(hardSets: Int, info: ExerciseInfo): Map<String, RegionShare> {
        if (hardSets <= 0) return emptyMap()
        val result = LinkedHashMap<String, RegionShare>()
        val primary = info.primaryRegions.toSet()
        for (region in primary) result[region] = RegionShare(hardSets, 0)
        for (region in info.secondaryRegions.toSet() - primary) result[region] = RegionShare(0, hardSets)
        return result
    }
}

/** Serije jedne regije: one u kojima je glavni mišić i one u kojima samo pomaže. */
data class RegionShare(var primary: Int, var secondary: Int) {
    /** Glavna serija 1, pomoćna [EffectiveSets.SECONDARY_WEIGHT]. */
    val weighted: Double get() = primary + secondary * EffectiveSets.SECONDARY_WEIGHT
}

/** Fiksna skala boje heatmapa. Razina 0 je bez boje, 4 najtamnija. Intenzitet za crtež je razina / 4. */
object LoadScale {
    const val MAXIMUM_LEVEL = 4

    /** Prosjek tvrdih serija tjedno: ispod 5 malo, 5 do 9 održavanje, 10 do 20 zona za rast, iznad 20 visoko. */
    fun weeklyLevel(sets: Double): Int = when {
        sets < 0.25 -> 0
        sets < 5 -> 1
        sets < 10 -> 2
        sets <= 20 -> 3
        else -> 4
    }

    /** Tvrde serije u jednom treningu: 1 do 2, 3 do 5, 6 do 9, 10 i više. */
    fun sessionLevel(sets: Double): Int = when {
        sets < 0.25 -> 0
        sets < 3 -> 1
        sets < 6 -> 2
        sets < 10 -> 3
        else -> 4
    }

    fun intensity(level: Int): Double = level.coerceIn(0, MAXIMUM_LEVEL).toDouble() / MAXIMUM_LEVEL
}
