package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.training.SessionCardio
import java.time.Instant

/** Razdoblje pregleda u Statistici: kalendarski tjedan, mjesec ili godina. */
enum class OverviewPeriod(val raw: String) {
    WEEK("week"),
    MONTH("month"),
    YEAR("year"),
    ;

    /** Razdoblje koje sadrži `date` (tjedan počinje prema kalendaru, npr. ponedjeljkom). */
    fun interval(date: Instant, calendar: StatsCalendar = StatsCalendar.system()): DateInterval = when (this) {
        WEEK -> calendar.weekInterval(date)
        MONTH -> calendar.monthInterval(date)
        YEAR -> calendar.yearInterval(date)
    }

    /** Datum pomaknut za `value` razdoblja (-1 prethodno, 1 sljedeće). */
    fun shift(date: Instant, value: Int, calendar: StatsCalendar = StatsCalendar.system()): Instant = when (this) {
        WEEK -> calendar.addWeeks(date, value.toLong())
        MONTH -> calendar.addMonths(date, value.toLong())
        YEAR -> calendar.addYears(date, value.toLong())
    }
}

/**
 * Brojke jednog tjedna, mjeseca ili godine za ekran Pregled: treninzi, vrijeme, tvrde serije, kardio,
 * dani s vrstom treninga i (za godinu) treninzi po mjesecima.
 */
data class PeriodSummary(
    val period: OverviewPeriod,
    val interval: DateInterval,
    /** Svi dani razdoblja, od prvog. */
    val days: List<TrainingDay>,
    /** Dvanaest mjeseci za godinu; prazno za tjedan i mjesec. */
    val months: List<Month>,
    /** Planirani treninzi tjedno (dani tjedno iz onboardinga); null bez plana. */
    val weeklyGoal: Int?,
    /** Tjedni za prosjek ([weeks]). */
    val weeks: Double,
    var sessions: Int = 0,
    /** Tvrde serije snage (`SetMetrics.isHard`); kardio vježbe se ne broje. */
    var hardSets: Int = 0,
    var cardioSeconds: Int = 0,
    var cardioMeters: Double = 0.0,
    var totalSeconds: Double = 0.0,
) {
    /** Jedan mjesec godine za stupce. */
    data class Month(val start: Instant, var sessions: Int = 0, var hardSets: Int = 0)

    val trainedDays: Int get() = days.count { it.isTrained }
    val sessionsPerWeek: Double get() = sessions / maxOf(weeks, 1.0)

    /**
     * Treninzi po danu (ključ je početak dana), svaki dan od ranijeg prema kasnijem.
     * Nezavršeni treninzi i treninzi izvan razdoblja se preskaču.
     */
    fun sessionsByDay(sessions: List<Session>, calendar: StatsCalendar = StatsCalendar.system()): Map<Instant, List<Session>> =
        sessions.filter { it.state == SessionState.FINISHED && it.startedAt >= interval.start && it.startedAt < interval.end }
            .sortedBy { it.startedAt }
            .groupBy { calendar.startOfDay(it.startedAt) }

    companion object {
        /**
         * Tjedni razdoblja za tjedni prosjek, najmanje 1. Tekuće razdoblje broji se do `now`, a razdoblje
         * u kojem je korisnik počeo od prvog treninga (`since`), da prosjek ne bude razvodnjen.
         */
        fun weeks(interval: DateInterval, now: Instant, since: Instant?): Double {
            val from = maxOf(interval.start, since ?: interval.start)
            val to = minOf(interval.end, maxOf(now, from))
            return maxOf(1.0, secondsBetween(from, to) / (7 * 86_400))
        }

        /** Sažetak razdoblja koje sadrži `date` iz završenih treninga; treninzi izvan razdoblja se preskaču. */
        fun make(
            sessions: List<Session>,
            period: OverviewPeriod,
            date: Instant,
            now: Instant = Instant.now(),
            since: Instant? = null,
            goal: Int?,
            calendar: StatsCalendar = StatsCalendar.system(),
            isCardio: (String) -> Boolean,
        ): PeriodSummary {
            val interval = period.interval(date, calendar)
            val days = mutableListOf<TrainingDay>()
            var cursor = interval.start
            while (cursor < interval.end) {
                days += TrainingDay(cursor)
                cursor = calendar.addDays(cursor, 1)
            }
            val months = if (period == OverviewPeriod.YEAR) {
                (0L until 12).map { Month(calendar.addMonths(interval.start, it)) }
            } else {
                emptyList()
            }
            val summary = PeriodSummary(period, interval, days, months, goal?.takeIf { it > 0 }, weeks(interval, now, since))
            val dayIndex = days.withIndex().associate { (index, day) -> day.date to index }

            for (session in sessions) {
                if (session.state != SessionState.FINISHED || session.startedAt < interval.start || session.startedAt >= interval.end) continue
                summary.sessions += 1
                val figures = SessionFigures.of(session, isCardio)
                summary.totalSeconds += figures.durationSeconds
                summary.hardSets += figures.hardSets
                summary.cardioSeconds += figures.cardioSeconds
                summary.cardioMeters += figures.cardioMeters ?: 0.0
                val mix = SessionCardio.mix(session, isCardio)
                dayIndex[calendar.startOfDay(session.startedAt)]?.let { index ->
                    if (WorkoutKind.STRENGTH in mix.kinds) summary.days[index].strength = true
                    if (WorkoutKind.CARDIO in mix.kinds) summary.days[index].cardio = true
                }
                if (period == OverviewPeriod.YEAR) {
                    summary.months.getOrNull(calendar.zoned(session.startedAt).monthValue - 1)?.let {
                        it.sessions += 1
                        it.hardSets += figures.hardSets
                    }
                }
            }
            return summary
        }
    }
}

/**
 * Serije i tonaža po regiji podijeljene s brojem tjedana, za usporedbu mjeseca ili godine
 * sa zonama serija tjedno. Ukupni zbrojevi ostaju.
 */
fun VolumeBucket.perWeek(weeks: Double): VolumeBucket {
    val divisor = maxOf(weeks, 1.0)
    val divided = loads.mapValuesTo(LinkedHashMap()) { (_, load) -> MuscleLoad(load.volumeKg / divisor, load.sets / divisor) }
    return copy(loads = divided)
}

/** Sažetak tjedna, mjeseca ili godine koji sadrži `date`. */
fun StatisticsEngine.periodSummary(
    period: OverviewPeriod,
    date: Instant,
    now: Instant = Instant.now(),
    goal: Int?,
    calendar: StatsCalendar = StatsCalendar.system(),
    isCardio: (String) -> Boolean,
): PeriodSummary {
    val interval = period.interval(date, calendar)
    return PeriodSummary.make(sessions(interval), period, date, now, firstSessionDate(), goal, calendar, isCardio)
}

/** Završeni treninzi u razdoblju. */
fun StatisticsEngine.sessions(interval: DateInterval): List<Session> = store.finishedSessions(interval.start, interval.end)

/** Tvrde serije i tonaža po regiji u razdoblju (kao jedan `volumeBuckets` stupac). */
fun StatisticsEngine.volumeBucket(interval: DateInterval, info: ExerciseInfoProvider): VolumeBucket {
    val bucket = VolumeBucket(interval.start)
    sessions(interval).forEach { bucket.add(it, info) }
    return bucket
}

/**
 * Serije po mišiću u razdoblju koje sadrži `date` i u razdoblju prije. Tjedan se uspoređuje u ukupnim
 * serijama, a mjesec i godina u prosjeku serija tjedno, jer su različite duljine.
 */
fun StatisticsEngine.periodVolume(
    period: OverviewPeriod,
    date: Instant,
    now: Instant = Instant.now(),
    calendar: StatsCalendar = StatsCalendar.system(),
    info: ExerciseInfoProvider,
): VolumeComparison? {
    val current = period.interval(date, calendar)
    val previous = period.interval(period.shift(current.start, -1, calendar), calendar)
    var buckets = listOf(volumeBucket(previous, info), volumeBucket(current, info))
    if (period != OverviewPeriod.WEEK) {
        val since = firstSessionDate()
        buckets = listOf(
            buckets[0].perWeek(PeriodSummary.weeks(previous, now, since)),
            buckets[1].perWeek(PeriodSummary.weeks(current, now, since)),
        )
    }
    return VolumeComparison.of(buckets)
}
