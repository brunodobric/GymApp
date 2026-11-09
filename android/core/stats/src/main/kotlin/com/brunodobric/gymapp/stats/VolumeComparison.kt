package com.brunodobric.gymapp.stats

import java.time.Instant

/** Tvrde serije jedne regije tijela u dva uzastopna razdoblja. */
data class MuscleComparison(val region: String, val currentSets: Double, val previousSets: Double)

/**
 * Usporedba zadnjeg razdoblja (tjedna ili mjeseca, koji je možda još u tijeku) s prethodnim, u tvrdim serijama.
 * Služi za graf usporedbe u statistici.
 */
data class VolumeComparison(
    val currentStart: Instant,
    val previousStart: Instant,
    /** Ukupno tvrdih serija; svaka serija broji se jednom. */
    val currentSets: Int,
    val previousSets: Int,
    /** Regije sa serijama u barem jednom od dva razdoblja, od najviše serija prema manje. */
    val muscles: List<MuscleComparison>,
) {
    /** Relativna promjena ukupnog broja serija (0,1 = +10 %). Bez serija u prethodnom razdoblju nema smisla. */
    val change: Double? get() = if (previousSets > 0) (currentSets - previousSets).toDouble() / previousSets else null

    companion object {
        /**
         * `buckets` su od najstarijeg prema najnovijem, kao iz [StatisticsEngine.volumeBuckets].
         * Uspoređuju se zadnja dva. Bez barem dva razdoblja usporedbe nema.
         */
        fun of(buckets: List<VolumeBucket>): VolumeComparison? {
            if (buckets.size < 2) return null
            val current = buckets[buckets.size - 1]
            val previous = buckets[buckets.size - 2]
            val muscles = (current.loads.keys + previous.loads.keys)
                .map { MuscleComparison(it, current.loads[it]?.sets ?: 0.0, previous.loads[it]?.sets ?: 0.0) }
                .filter { it.currentSets > 0 || it.previousSets > 0 }
                // Jednako serija: stalan redoslijed po nazivu, da se graf ne miješa između učitavanja.
                .sortedWith(compareByDescending<MuscleComparison> { maxOf(it.currentSets, it.previousSets) }.thenBy { it.region })
            return VolumeComparison(current.start, previous.start, current.totalSets, previous.totalSets, muscles)
        }
    }
}
