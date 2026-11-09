package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.values
import java.time.Instant
import kotlin.math.roundToLong

/** Ocjena jednog dijela tjednog pregleda. */
enum class ReviewLevel(val raw: String) { GOOD("good"), FAIR("fair"), ATTENTION("attention"), NO_DATA("noData") }

/**
 * Tjedni pregled od četiri dijela, svaki s vlastitim uporištem u istraživanjima. Namjerno nema jedne složene
 * ocjene: zbroj "dobrih" dijelova ([goodCount]) je jedina brojka i nema skrivenih težina.
 */
data class WeeklyReview(val strength: Strength, val volume: Volume, val consistency: Consistency, val effort: Effort) {
    /** Trend snage vježbi ([TrendAnalysis]). */
    data class Strength(
        var level: ReviewLevel,
        var improving: Int = 0,
        var stable: Int = 0,
        var plateau: Int = 0,
        var declining: Int = 0,
        /** Medijan mjesečne promjene vježbi s dovoljno podataka. */
        var medianMonthlyChange: Double? = null,
    )

    /** Glavni mišići u zoni tvrdih serija tjedno za cilj (Pelland i sur. 2024, Schoenfeld i sur. 2017). */
    data class Volume(var level: ReviewLevel, var inZone: Int = 0, var regions: Int = 0, val zone: ClosedFloatingPointRange<Double>)

    /** Odrađeni treninzi prema planiranima. */
    data class Consistency(
        var level: ReviewLevel,
        var sessions: Int = 0,
        var weeks: Double = 1.0,
        /** Planirani treninzi u razdoblju (dani tjedno iz onboardinga × tjedni). Null bez plana. */
        var planned: Int? = null,
    ) {
        val sessionsPerWeek: Double get() = sessions / maxOf(weeks, 1.0)
        val ratio: Double? get() = planned?.let { if (it > 0) sessions.toDouble() / it else 0.0 }
    }

    /** Udio radnih serija blizu otkaza (RIR 0 do 3) kad korisnik upisuje RPE (Robinson i sur. 2024). */
    data class Effort(var level: ReviewLevel, var ratedSets: Int = 0, var closeToFailureShare: Double? = null)

    val levels: List<ReviewLevel> get() = listOf(strength.level, volume.level, consistency.level, effort.level)
    val goodCount: Int get() = levels.count { it == ReviewLevel.GOOD }

    /** Dijelovi s podacima. */
    val ratedCount: Int get() = levels.count { it != ReviewLevel.NO_DATA }
}

object WeeklyReviewBuilder {
    /** Razdoblje pregleda u tjednima. */
    const val WEEKS = 4

    /** Najmanje ocijenjenih serija za dio "napor". */
    const val MINIMUM_RATED_SETS = 10

    /** Zona tvrdih serija tjedno po glavnom mišiću prema cilju iz onboardinga. */
    fun volumeZone(goal: TrainingGoal?): ClosedFloatingPointRange<Double> = when (goal) {
        TrainingGoal.STRENGTH -> 4.0..30.0
        TrainingGoal.RECOMPOSITION, TrainingGoal.GENERAL_FITNESS -> 5.0..30.0
        TrainingGoal.HYPERTROPHY, null -> 10.0..20.0
    }

    private fun level(share: Double, good: Double, fair: Double): ReviewLevel = when {
        share >= good -> ReviewLevel.GOOD
        share >= fair -> ReviewLevel.FAIR
        else -> ReviewLevel.ATTENTION
    }

    fun strength(trends: List<ExerciseTrendEntry>): WeeklyReview.Strength {
        val result = WeeklyReview.Strength(ReviewLevel.NO_DATA)
        val changes = mutableListOf<Double>()
        for (entry in trends) {
            when (entry.trend.status) {
                ExerciseStatus.IMPROVING -> result.improving += 1
                ExerciseStatus.STABLE -> result.stable += 1
                ExerciseStatus.PLATEAU -> result.plateau += 1
                ExerciseStatus.DECLINING -> result.declining += 1
                ExerciseStatus.INSUFFICIENT_DATA -> continue
            }
            entry.trend.monthlyChange?.let { changes += it }
        }
        val rated = result.improving + result.stable + result.plateau + result.declining
        if (rated == 0) return result
        result.medianMonthlyChange = TrendAnalysis.median(changes)
        result.level = level((result.improving + result.stable).toDouble() / rated, 0.75, 0.5)
        return result
    }

    /** `weeklySets`: prosjek tvrdih serija tjedno po regiji ([RegionLoad.weeklySets]). */
    fun volume(weeklySets: Map<String, Double>, goal: TrainingGoal?): WeeklyReview.Volume {
        val zone = volumeZone(goal)
        val result = WeeklyReview.Volume(ReviewLevel.NO_DATA, regions = BodyRegion.major.size, zone = zone)
        if (weeklySets.values.none { it > 0 }) return result
        result.inZone = BodyRegion.major.count { (weeklySets[it] ?: 0.0) in zone }
        result.level = level(result.inZone.toDouble() / result.regions, 0.7, 0.4)
        return result
    }

    fun consistency(sessions: Int, weeks: Double, plannedPerWeek: Int?): WeeklyReview.Consistency {
        val result = WeeklyReview.Consistency(ReviewLevel.ATTENTION, sessions, maxOf(weeks, 1.0))
        if (plannedPerWeek != null && plannedPerWeek > 0) {
            val planned = (plannedPerWeek * result.weeks).roundToLong().toInt()
            result.planned = planned
            result.level = level(sessions.toDouble() / maxOf(planned, 1), 0.9, 0.6)
        } else {
            val perWeek = result.sessionsPerWeek
            result.level = when {
                perWeek >= 2 -> ReviewLevel.GOOD
                perWeek >= 1 -> ReviewLevel.FAIR
                else -> ReviewLevel.ATTENTION
            }
        }
        return result
    }

    /** `rpes`: upisani RPE radnih serija u razdoblju. */
    fun effort(rpes: List<Double>): WeeklyReview.Effort {
        val result = WeeklyReview.Effort(ReviewLevel.NO_DATA, rpes.size)
        if (rpes.size < MINIMUM_RATED_SETS) return result
        // RIR 0 do 3 = RPE 7 i više.
        val share = rpes.count { it >= 7 }.toDouble() / rpes.size
        result.closeToFailureShare = share
        result.level = level(share, 0.7, 0.4)
        return result
    }
}

// MARK: Prijedlozi

/** Prijedlog za dalje. Svaki ima uvjet i izvor (`docs/SPECIFIKACIJA.md`); tekst daje sučelje. */
sealed interface Suggestion {
    /** Više vježbi pada: lakši tjedan (Bell i sur. 2023). */
    data class Deload(val exercises: Int) : Suggestion

    /** Odrađeno manje od 60 % planiranih treninga: raspored s manje dana. */
    data class FewerDays(val sessionsPerWeek: Double, val planned: Int) : Suggestion

    /** Vježba je na platou, a mišić ima manje od 10 serija tjedno (doza i odgovor, Pelland i sur. 2024). */
    data class AddSets(val region: String, val exerciseName: String) : Suggestion

    /** Vježba je na platou, a mišić ima više od 20 serija tjedno: manje volumena ili lakši tjedan. */
    data class ReduceVolume(val region: String, val exerciseName: String) : Suggestion

    /** Tri izvođenja zaredom s RIR 4 i više uz istu težinu: veća težina (dvostruka progresija, Helms i sur. 2016). */
    data class IncreaseLoad(val exerciseName: String) : Suggestion

    /** Glavni mišić nije rađen 14 i više dana, a ranije jest. */
    data class MissedMuscle(val region: String, val days: Int) : Suggestion
}

data class SuggestionInput(
    val trends: List<ExerciseTrendEntry>,
    /** Prosjek tvrdih serija tjedno po regiji u zadnja 4 tjedna. */
    val weeklySets: Map<String, Double>,
    /** Zadnji trening po regiji u zadnjih 8 tjedana. */
    val lastTrained: Map<String, Instant>,
    val consistency: WeeklyReview.Consistency,
    val goal: TrainingGoal?,
    /** Vježbe s tri lagana izvođenja zaredom uz istu težinu. */
    val easyExercises: List<String>,
    val now: Instant,
)

object SuggestionEngine {
    const val MISSED_MUSCLE_DAYS = 14

    /** Prijedlozi od najvažnijeg. Svaki mišić dobiva najviše jedan prijedlog o volumenu. */
    fun suggestions(input: SuggestionInput): List<Suggestion> {
        val result = mutableListOf<Suggestion>()
        val declining = input.trends.count { it.trend.status == ExerciseStatus.DECLINING }
        if (declining >= 2) result += Suggestion.Deload(declining)
        val planned = input.consistency.planned
        val ratio = input.consistency.ratio
        if (planned != null && ratio != null && ratio < 0.6) {
            result += Suggestion.FewerDays(input.consistency.sessionsPerWeek, planned)
        }

        val growthGoal = input.goal == null || input.goal == TrainingGoal.HYPERTROPHY || input.goal == TrainingGoal.STRENGTH
        val handled = mutableSetOf<String>()
        for (entry in input.trends) {
            if (entry.trend.status != ExerciseStatus.PLATEAU) continue
            val region = entry.primaryRegions.firstOrNull() ?: continue
            if (region in handled) continue
            val sets = input.weeklySets[region] ?: 0.0
            if (sets < 10 && growthGoal) {
                result += Suggestion.AddSets(region, entry.name)
                handled += region
            } else if (sets > 20) {
                result += Suggestion.ReduceVolume(region, entry.name)
                handled += region
            }
        }
        result += input.easyExercises.map { Suggestion.IncreaseLoad(it) }

        for (region in BodyRegion.major) {
            val last = input.lastTrained[region] ?: continue
            val days = (secondsBetween(last, input.now) / (24 * 3600)).toInt()
            if (days >= MISSED_MUSCLE_DAYS) result += Suggestion.MissedMuscle(region, days)
        }
        return result
    }
}

// MARK: Izračun iz baze

/** Tjedni pregled i prijedlozi za zadnja 4 tjedna do `now`. */
fun StatisticsEngine.weeklyReview(
    now: Instant = Instant.now(),
    goal: TrainingGoal?,
    plannedPerWeek: Int?,
    info: ExerciseInfoProvider,
): Pair<WeeklyReview, List<Suggestion>> {
    val day = 24L * 3600
    val end = now.plusSeconds(1)
    val start = now.minusSeconds(WeeklyReviewBuilder.WEEKS * 7 * day)
    val trends = exerciseTrends(now = now, info = info)
    val weeklySets = heatmap(start, end, info).mapValues { it.value.weeklySets }
    val sessions = store.finishedSessions(start, end)
    val rpes = sessions.filter { !it.isImportedFromWorkoutsApp }.flatMap { session ->
        session.orderedExercises.filter { !it.isRemoved }.flatMap { exercise ->
            exercise.orderedSets.filter { it.isCompleted && it.kind == SetKind.WORKING }.mapNotNull { it.rpe }
        }
    }
    val weeks = minOf(WeeklyReviewBuilder.WEEKS.toDouble(), weeksCovered(start, end))
    val consistency = WeeklyReviewBuilder.consistency(sessions.size, weeks, plannedPerWeek)
    val review = WeeklyReview(
        WeeklyReviewBuilder.strength(trends),
        WeeklyReviewBuilder.volume(weeklySets, goal),
        consistency,
        WeeklyReviewBuilder.effort(rpes),
    )
    val earlier = heatmap(now.minusSeconds(8 * 7 * day), end, info)
    val input = SuggestionInput(
        trends, weeklySets, earlier.mapNotNull { (region, load) -> load.lastTrained?.let { region to it } }.toMap(),
        consistency, goal, easyExercises(now), now,
    )
    return review to SuggestionEngine.suggestions(input)
}

/**
 * Vježbe čija su zadnja tri izvođenja (u 8 tjedana) bila lagana: sve radne serije s RIR 4 i više
 * (RPE 6 i manje) i ista najveća težina.
 */
fun StatisticsEngine.easyExercises(now: Instant = Instant.now()): List<String> {
    data class Performance(val name: String, val load: Double, val easy: Boolean)
    val performances = LinkedHashMap<String, MutableList<Performance>>()
    // Od najnovijeg prema starijem.
    for (session in store.finishedSessions(now.minusSeconds(8L * 7 * 24 * 3600), now.plusSeconds(1))) {
        for (exercise in session.orderedExercises) {
            if (exercise.isRemoved) continue
            val working = exercise.orderedSets.filter { it.isCompleted && it.kind == SetKind.WORKING }.map { it.values }
            if (working.isEmpty()) continue
            val load = working.mapNotNull { SetMetrics.load(it, exercise.inputType) }.maxOrNull() ?: 0.0
            val easy = load > 0 && working.all { (it.rpe ?: 10.0) <= 6 }
            performances.getOrPut(exercise.exerciseKey) { mutableListOf() } += Performance(exercise.exerciseName, load, easy)
        }
    }
    return performances.values.mapNotNull { list ->
        val last = list.take(3)
        if (last.size == 3 && last.all { it.easy } && last.map { it.load }.toSet().size == 1) last.first().name else null
    }.sorted()
}
