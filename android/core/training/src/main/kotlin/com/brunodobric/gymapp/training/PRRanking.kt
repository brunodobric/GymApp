package com.brunodobric.gymapp.training

import kotlin.math.ln

/** Rekordi jedne vježbe u jednom treningu, za izbor istaknutih rekorda. */
data class RecordCandidate(
    val exerciseKey: String,
    val exerciseName: String,
    val records: List<PersonalRecord>,
    /** Je li vježba složena. Null kad se ne zna. */
    val isCompound: Boolean?,
)

/** Istaknuti rekord u sažetku treninga. */
data class RecordHighlight(
    val exerciseKey: String,
    val exerciseName: String,
    val record: PersonalRecord,
    /** Značajnost ([PRRanking.significance]): veće je važnije. */
    val score: Double,
)

/**
 * Izbor istaknutih rekorda: najviše jedan po vježbi i najviše [SUMMARY_LIMIT] u sažetku, poredani po tome
 * koliko je napredak velik u odnosu na uobičajeno kolebanje vježbe.
 */
object PRRanking {
    const val SUMMARY_LIMIT = 3

    /** Redoslijed vrsta kad vježba ima više rekorda u istom treningu: prvi postojeći se ističe. */
    val priority = listOf(
        PRKind.ESTIMATED_ONE_REP_MAX, PRKind.REP_MAX, PRKind.MAX_WEIGHT, PRKind.MAX_REPS,
        PRKind.LOWEST_ASSISTANCE, PRKind.LONGEST_DISTANCE, PRKind.LONGEST_DURATION, PRKind.EXERCISE_VOLUME,
    )

    /** Uobičajeno kolebanje rezultata između treninga (udio). */
    fun noise(kind: PRKind, isCompound: Boolean?): Double = when (kind) {
        PRKind.ESTIMATED_ONE_REP_MAX, PRKind.REP_MAX, PRKind.MAX_WEIGHT, PRKind.EXERCISE_VOLUME, PRKind.LOWEST_ASSISTANCE ->
            if (isCompound == true) 0.03 else 0.05
        PRKind.MAX_REPS -> 0.08
        PRKind.LONGEST_DURATION, PRKind.LONGEST_DISTANCE -> 0.05
    }

    /** Složene vježbe imaju veću težinu od izolacijskih, nepoznate su između. */
    fun exerciseWeight(isCompound: Boolean?): Double = when (isCompound) {
        true -> 1.0
        false -> 0.7
        null -> 0.85
    }

    /** Značajnost rekorda: ln(novo / staro) podijeljeno s kolebanjem, puta težina vrste vježbe. */
    fun significance(record: PersonalRecord, isCompound: Boolean?): Double {
        val previous = record.previousBest ?: return 0.0
        if (previous <= 0 || record.value <= 0) return 0.0
        val ratio = if (record.kind == PRKind.LOWEST_ASSISTANCE) previous / record.value else record.value / previous
        if (ratio <= 0) return 0.0
        return ln(ratio) / noise(record.kind, isCompound) * exerciseWeight(isCompound)
    }

    /** Glavni rekord vježbe: prvi po [priority] među onima koji idu u sažetak. */
    fun headline(records: List<PersonalRecord>): PersonalRecord? {
        val shown = records.filter { it.showsInSummary }
        return priority.firstNotNullOfOrNull { kind -> shown.firstOrNull { it.kind == kind } }
    }

    data class Highlights(val shown: List<RecordHighlight>, val hiddenCount: Int)

    /** Istaknuti rekordi (najviše [limit], od najznačajnijeg) i broj ostalih rekorda tog treninga. */
    fun highlights(candidates: List<RecordCandidate>, limit: Int = SUMMARY_LIMIT): Highlights {
        val best = candidates.mapNotNull { candidate ->
            headline(candidate.records)?.let { record ->
                RecordHighlight(candidate.exerciseKey, candidate.exerciseName, record, significance(record, candidate.isCompound))
            }
        }
        val shown = best.sortedWith(compareByDescending<RecordHighlight> { it.score }.thenBy { it.exerciseName }).take(limit)
        val total = candidates.sumOf { it.records.size }
        return Highlights(shown, total - shown.size)
    }
}
