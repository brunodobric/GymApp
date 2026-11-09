package com.brunodobric.gymapp.stats

import java.time.Instant

/** Raspon koji prikazuje graf napretka vježbe: zadnjih N mjeseci, sve ili vlastiti raspon od–do. */
sealed interface ChartRange {
    data class Months(val count: Int) : ChartRange
    data object All : ChartRange

    /** Vlastiti raspon; oba datuma ulaze cijelim danom. */
    data class Custom(val from: Instant, val to: Instant) : ChartRange

    /** Interval raspona na dan `now`; null za "sve". Vlastiti raspon s obrnutim datumima se okrene. */
    fun interval(now: Instant, calendar: StatsCalendar = StatsCalendar.system()): DateInterval? = when (this) {
        All -> null
        is Months -> {
            val start = calendar.addMonths(calendar.startOfDay(now), -maxOf(count, 1).toLong())
            DateInterval(start, maxOf(now, start))
        }
        is Custom -> {
            val first = calendar.startOfDay(minOf(from, to))
            val lastDay = calendar.startOfDay(maxOf(from, to))
            // Kraj je zadnji trenutak zadnjeg dana, da ponoć sljedećeg dana ne uđe u raspon.
            DateInterval(first, calendar.addDays(lastDay, 1).minusMillis(1))
        }
    }

    /** Točke koje padaju u raspon (granice uključene). */
    fun filter(points: List<ExercisePoint>, now: Instant, calendar: StatsCalendar = StatsCalendar.system()): List<ExercisePoint> {
        val interval = interval(now, calendar) ?: return points
        return points.filter { interval.contains(it.date) }
    }
}
