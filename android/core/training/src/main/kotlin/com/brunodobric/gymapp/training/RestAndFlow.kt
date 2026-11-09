package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.UserSettings
import java.time.Duration
import java.time.Instant

internal fun secondsBetween(from: Instant, to: Instant): Double = Duration.between(from, to).toNanos() / 1e9

internal fun Instant.plusSeconds(seconds: Double): Instant = plusNanos((seconds * 1e9).toLong())

/**
 * Rest timer koji se sprema kao trenutak završetka, ne kao preostale sekunde. Nakon oporavka ili povratka
 * iz pozadine isti zapis daje ispravno preostalo vrijeme.
 */
class RestTimer(val startedAt: Instant, endsAt: Instant) {
    val endsAt: Instant = maxOf(endsAt, startedAt)

    constructor(startedAt: Instant, seconds: Int) : this(startedAt, startedAt.plusSeconds(maxOf(0, seconds).toLong()))

    val totalSeconds: Double get() = secondsBetween(startedAt, endsAt)

    fun remaining(now: Instant): Double = maxOf(0.0, secondsBetween(now, endsAt))

    fun isExpired(now: Instant): Boolean = remaining(now) == 0.0

    /** Udio proteklog vremena od 0 do 1, za traku koja teče. */
    fun progress(now: Instant): Double {
        if (totalSeconds <= 0) return 1.0
        return (1 - remaining(now) / totalSeconds).coerceIn(0.0, 1.0)
    }

    /** +10 / −10 sekundi. Timer se nikad ne skraćuje ispod trenutka pritiska (tada istječe odmah). */
    fun adjusted(deltaSeconds: Int, now: Instant): RestTimer =
        RestTimer(startedAt, maxOf(now, endsAt.plusSeconds(deltaSeconds.toLong())))

    override fun equals(other: Any?): Boolean = other is RestTimer && startedAt == other.startedAt && endsAt == other.endsAt

    override fun hashCode(): Int = 31 * startedAt.hashCode() + endsAt.hashCode()

    override fun toString(): String = "RestTimer($startedAt, $endsAt)"
}

/**
 * Zadane pauze iz Postavki, za vježbe bez vlastite pauze. Složene vježbe traže dulji odmor od izolacijskih
 * (2–3 min prema 1–1,5 min), pa pauza ovisi o vrsti vježbe iz kataloga (`Mechanic`).
 */
data class RestDefaults(
    /** Složene vježbe (`Mechanic.COMPOUND`). */
    val compoundSeconds: Int,
    /** Izolacijske i vježbe bez oznake (vlastite vježbe, kardio, istezanje). */
    val otherSeconds: Int,
) {
    /**
     * Zadana pauza nakon vježbe ili kruga superseta. Superset s barem jednom složenom vježbom dobiva pauzu
     * složenih. Null znači da se vrsta vježbe ne zna.
     */
    fun seconds(isCompound: List<Boolean?>): Int = if (isCompound.contains(true)) compoundSeconds else otherSeconds

    companion object {
        /** Ista pauza za sve vježbe. */
        fun uniform(seconds: Int) = RestDefaults(seconds, seconds)

        /** Tvorničke vrijednosti: 2:30 za složene, 1:30 za ostale. */
        val STANDARD = RestDefaults(150, 90)
    }
}

object RestPolicy {
    /**
     * Pauza nakon serije: 0 nakon svake vježbe u supersetu osim zadnje, a nakon zadnje vrijedi postavljena
     * pauza vježbe ili superseta, inače zadana. Vježba izvan superseta je grupa veličine 1.
     */
    fun seconds(positionInGroup: Int, groupSize: Int, configured: Int?, defaultSeconds: Int): Int {
        if (groupSize > 1 && positionInGroup < groupSize - 1) return 0
        return maxOf(0, configured ?: defaultSeconds)
    }
}

data class SetPosition(val exercise: Int, val set: Int)

object SupersetSequence {
    /** Naizmjenični redoslijed serija: A1, B1, A2, B2, ... Vježba s manje serija ispadne iz kruga. */
    fun order(setCounts: List<Int>): List<SetPosition> {
        val rounds = setCounts.maxOrNull() ?: 0
        val result = mutableListOf<SetPosition>()
        for (round in 0 until maxOf(rounds, 0)) {
            setCounts.forEachIndexed { exercise, count -> if (round < count) result += SetPosition(exercise, round) }
        }
        return result
    }

    /** Prva serija u naizmjeničnom redoslijedu koja još nije završena. */
    fun nextIncomplete(setCounts: List<Int>, isCompleted: (SetPosition) -> Boolean): SetPosition? =
        order(setCounts).firstOrNull { !isCompleted(it) }
}

object WorkoutFlow {
    /** Prva vježba koja nije potpuno završena; null znači da je sve završeno. */
    fun firstIncompleteExercise(isFullyCompleted: List<Boolean>): Int? =
        isFullyCompleted.indexOf(false).takeIf { it >= 0 }

    /** Što ekran treninga radi nakon što je serija označena završenom. */
    sealed interface Advance {
        /** Otvorena vježba (ili superset) još ima serija: ostaje otvorena. */
        data object Stay : Advance

        /** Otvara se vježba na ovom indeksu. */
        data class Open(val index: Int) : Advance

        /** Sve je završeno: nudi se "Završi trening / Dodaj vježbu". */
        data object Finished : Advance
    }

    /** Odluka nakon označene serije, na ekranu ili u obavijesti. */
    fun advance(openGroupDone: Boolean, isFullyCompleted: List<Boolean>): Advance {
        if (!openGroupDone) return Advance.Stay
        return firstIncompleteExercise(isFullyCompleted)?.let { Advance.Open(it) } ?: Advance.Finished
    }

    /** Je li od zadnjeg pogleda označena nova serija (npr. iz obavijesti). */
    fun hasNewCompletion(completedCount: Int, lastSeen: Int): Boolean = completedCount > lastSeen
}

object RecoveryAssessment {
    /** Trening bez aktivnosti dulje od ovoga (u sekundama) nudi se za zatvaranje. */
    const val STALE_AFTER_SECONDS = 6 * 3600.0

    data class Result(
        val isStale: Boolean,
        /** Kraj treninga ako se zatvara: zadnja završena serija, inače početak. */
        val suggestedEnd: Instant,
    )

    fun assess(startedAt: Instant, lastActivityAt: Instant, lastCompletedSetAt: Instant?, now: Instant): Result =
        Result(secondsBetween(lastActivityAt, now) > STALE_AFTER_SECONDS, lastCompletedSetAt ?: startedAt)
}

/** Zadane pauze iz Postavki. */
val UserSettings.restDefaults: RestDefaults get() = RestDefaults(compoundRestSeconds, defaultRestSeconds)

/** Je li vježba složena, po ključu vježbe. Null za vlastitu vježbu i vježbu bez oznake. */
fun ExerciseCatalog.isCompound(exerciseKey: String): Boolean? {
    val id = ExerciseRef.fromKey(exerciseKey, "")?.catalogId ?: return null
    return exercise(id)?.mechanic?.let { it == Mechanic.COMPOUND }
}
