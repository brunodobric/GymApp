package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.training.SetMetrics

/** Serije jednog treninga po regiji tijela (za prikaz mišića u sažetku i detaljima treninga). */
data class RegionSets(
    val region: String,
    /** Tvrde serije vježbi kojima je regija glavni mišić. */
    var primarySets: Int = 0,
    /** Tvrde serije vježbi kojima regija samo pomaže. */
    var secondarySets: Int = 0,
    var volumeKg: Double = 0.0,
) {
    /** Serije za boju i popis: glavna serija broji se kao 1, pomoćna kao [EffectiveSets.SECONDARY_WEIGHT]. */
    val weightedSets: Double get() = RegionShare(primarySets, secondarySets).weighted

    /** Razina na fiksnoj skali jednog treninga ([LoadScale.sessionLevel]). */
    val level: Int get() = LoadScale.sessionLevel(weightedSets)
}

/** Mišićne regije koje je jedan trening opteretio. */
object SessionRegions {
    /** Udio pomoćne serije u odnosu na seriju u kojoj je regija glavni mišić. */
    const val SECONDARY_WEIGHT = EffectiveSets.SECONDARY_WEIGHT

    /**
     * Serije po regiji, od najopterećenije. Broje se tvrde serije ([EffectiveSets]); warm-up, preslabe
     * serije, kardio vježbe i uklonjene vježbe se ne računaju. Regija bez ijedne serije nije u popisu.
     */
    fun sets(session: Session, info: ExerciseInfoProvider): List<RegionSets> {
        val result = LinkedHashMap<String, RegionSets>()
        for (exercise in session.orderedExercises) {
            if (exercise.isRemoved) continue
            val details = info(exercise.exerciseKey) ?: continue
            if (details.isCardio) continue
            val done = EffectiveSets.hardSets(exercise)
            if (done.isEmpty()) continue
            val volume = done.sumOf { SetMetrics.volume(it, exercise.inputType) }
            for ((region, share) in EffectiveSets.regionCounts(done.size, details)) {
                val load = result.getOrPut(region) { RegionSets(region) }
                load.primarySets += share.primary
                load.secondarySets += share.secondary
                load.volumeKg += if (share.primary > 0) volume else volume * SECONDARY_WEIGHT
            }
        }
        return result.values.sortedWith(compareByDescending<RegionSets> { it.weightedSets }.thenBy { it.region })
    }

    /**
     * Popis ispod mape dijeli regije na glavne (barem jedna serija u kojoj su glavni mišić) i one koje samo
     * pomažu. Redoslijed iz [sets] ostaje unutar obje skupine.
     */
    fun split(sets: List<RegionSets>): Pair<List<RegionSets>, List<RegionSets>> =
        sets.filter { it.primarySets > 0 } to sets.filter { it.primarySets == 0 }

    /**
     * Heatmap treninga na fiksnoj skali: boja ovisi o broju serija regije, ne o najopterećenijoj regiji,
     * pa lagan trening ostaje svijetao.
     */
    fun heatmap(sets: List<RegionSets>): Map<String, RegionLoad> =
        sets.filter { it.weightedSets > 0 }.associate {
            it.region to RegionLoad(
                sessions = 1, volumeKg = it.volumeKg, sets = it.weightedSets, weeklySets = it.weightedSets,
                intensity = LoadScale.intensity(it.level),
            )
        }

    /** Heatmap regija koje je trening opteretio (vidi [sets] i [heatmap]). */
    fun worked(session: Session, info: ExerciseInfoProvider): Map<String, RegionLoad> = heatmap(sets(session, info))
}
