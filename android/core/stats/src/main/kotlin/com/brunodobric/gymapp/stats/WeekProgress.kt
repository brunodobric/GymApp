package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.training.SessionCardio
import com.brunodobric.gymapp.training.SessionMix
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.values
import java.time.Instant

/** Jedan dan i vrste treninga odrađene tog dana (kartica Ovaj tjedan i pregled razdoblja). */
data class TrainingDay(val date: Instant, var strength: Boolean = false, var cardio: Boolean = false) {
    val isTrained: Boolean get() = strength || cardio

    /** Vrsta za prikaz (ikona dana); null za dan bez treninga. */
    val mix: SessionMix?
        get() = when {
            strength && cardio -> SessionMix.MIXED
            strength -> SessionMix.STRENGTH
            cardio -> SessionMix.CARDIO
            else -> null
        }
}

/**
 * Tekući tjedan za karticu Ovaj tjedan na Početnoj: odrađeni treninzi prema cilju iz onboardinga,
 * dani s vrstom treninga, tvrde serije, minute kardija, ukupno vrijeme i niz tjedana s ispunjenim ciljem.
 */
data class WeekProgress(
    /** Početak tjedna (prema kalendaru, npr. ponedjeljak). */
    val start: Instant,
    /** Sedam dana tjedna, od prvog. */
    val days: List<TrainingDay>,
    /** Planirani treninzi tjedno (dani tjedno iz onboardinga); null bez plana. */
    val goal: Int?,
    /** Odrađeni treninzi u tjednu. */
    var sessions: Int = 0,
    /** Tvrde serije snage (`SetMetrics.isHard`); kardio vježbe se ne broje. */
    var hardSets: Int = 0,
    /** Vrijeme kardija: kardio treninzi cijeli, a u treningu snage odrađene kardio vježbe. */
    var cardioSeconds: Int = 0,
    /** Udaljenost kardija u metrima. */
    var cardioMeters: Double = 0.0,
    /** Zbroj trajanja svih treninga. */
    var totalSeconds: Double = 0.0,
    /**
     * Uzastopni tjedni s ispunjenim ciljem (bez cilja: s barem jednim treningom), do prošlog tjedna,
     * i ovaj tjedan ako je cilj već ispunjen.
     */
    var streakWeeks: Int = 0,
) {
    /** Udio cilja (0 do 1) za traku; null bez cilja. */
    val goalFraction: Double?
        get() = goal?.takeIf { it > 0 }?.let { minOf(sessions.toDouble() / it, 1.0) }

    /** Koliko treninga tjedno treba za tjedan koji se broji u niz. */
    internal val weeklyTarget: Int get() = maxOf(goal ?: 1, 1)

    /** Treninzi po danima tjedna (poravnato s [days]), svaki dan od ranijeg prema kasnijem. */
    fun sessionsByDay(sessions: List<Session>, calendar: StatsCalendar = StatsCalendar.system()): List<List<Session>> {
        val sorted = sessions.filter { it.state == SessionState.FINISHED }.sortedBy { it.startedAt }
        return days.map { day -> sorted.filter { calendar.date(it.startedAt) == calendar.date(day.date) } }
    }

    companion object {
        /** Najviše tjedana unatrag koji se gledaju za niz. */
        const val STREAK_LIMIT = 52

        /**
         * Sažetak tjedna koji sadrži `now` iz završenih treninga. `sessions` smije sadržavati i starije treninge
         * (za niz tjedana); treninzi nakon kraja tjedna se ne broje.
         */
        fun make(
            sessions: List<Session>,
            now: Instant,
            goal: Int?,
            calendar: StatsCalendar = StatsCalendar.system(),
            isCardio: (String) -> Boolean,
        ): WeekProgress {
            val week = calendar.weekInterval(now)
            val days = (0L until 7).map { TrainingDay(calendar.addDays(week.start, it)) }
            val progress = WeekProgress(week.start, days, goal?.takeIf { it > 0 })
            val finished = sessions.filter { it.state == SessionState.FINISHED && it.startedAt < week.end }

            for (session in finished) {
                if (session.startedAt < week.start) continue
                progress.sessions += 1
                val figures = SessionFigures.of(session, isCardio)
                progress.totalSeconds += figures.durationSeconds
                progress.hardSets += figures.hardSets
                progress.cardioSeconds += figures.cardioSeconds
                progress.cardioMeters += figures.cardioMeters ?: 0.0
                val mix = SessionCardio.mix(session, isCardio)
                progress.days.firstOrNull { calendar.date(it.date) == calendar.date(session.startedAt) }?.let { day ->
                    if (WorkoutKind.STRENGTH in mix.kinds) day.strength = true
                    if (WorkoutKind.CARDIO in mix.kinds) day.cardio = true
                }
            }
            progress.streakWeeks = streak(finished, week.start, progress.sessions, progress.weeklyTarget, calendar)
            return progress
        }

        private fun streak(sessions: List<Session>, weekStart: Instant, current: Int, target: Int, calendar: StatsCalendar): Int {
            val counts = mutableMapOf<Instant, Int>()
            for (session in sessions) {
                if (session.startedAt >= weekStart) continue
                val start = calendar.weekInterval(session.startedAt).start
                counts[start] = (counts[start] ?: 0) + 1
            }
            var streak = 0
            var cursor = weekStart
            while (streak < STREAK_LIMIT) {
                val start = calendar.weekInterval(calendar.addWeeks(cursor, -1)).start
                if ((counts[start] ?: 0) < target) break
                streak += 1
                cursor = start
            }
            return if (current >= target) streak + 1 else streak
        }
    }
}

/** Brojke jednog treninga za pregled tjedna: trajanje, tvrde serije snage i kardio. */
data class SessionFigures(
    val durationSeconds: Double,
    /** Tvrde serije snage (`SetMetrics.isHard`); kardio vježbe se ne broje. */
    val hardSets: Int = 0,
    /** Kardio trening cijeli, a u treningu snage zbroj odrađenih kardio vježbi. */
    val cardioSeconds: Int = 0,
    /** Udaljenost kardija; null kad je nema. */
    val cardioMeters: Double? = null,
) {
    companion object {
        fun of(session: Session, isCardio: (String) -> Boolean): SessionFigures {
            val duration = maxOf(0.0, secondsBetween(session.startedAt, session.endedAt ?: session.lastActivityAt))
            if (session.kind == WorkoutKind.CARDIO) {
                return SessionFigures(duration, 0, duration.toInt(), session.distanceMeters?.takeIf { it > 0 })
            }
            val part = SessionCardio.part(session, isCardio)
            var hardSets = 0
            for (exercise in session.orderedExercises) {
                if (exercise.isRemoved || isCardio(exercise.exerciseKey)) continue
                hardSets += exercise.orderedSets.filter { it.isCompleted }.map { it.values }.count(SetMetrics::isHard)
            }
            return SessionFigures(duration, hardSets, part?.seconds ?: 0, part?.meters)
        }
    }
}

/** Tekući tjedan s nizom tjedana. */
fun StatisticsEngine.weekProgress(
    now: Instant = Instant.now(),
    goal: Int?,
    calendar: StatsCalendar = StatsCalendar.system(),
    isCardio: (String) -> Boolean,
): WeekProgress {
    val weekStart = calendar.weekInterval(now).start
    val from = calendar.addWeeks(weekStart, -WeekProgress.STREAK_LIMIT.toLong())
    val to = calendar.addWeeks(weekStart, 1)
    return WeekProgress.make(store.finishedSessions(from, to), now, goal, calendar, isCardio)
}

/** Treninzi tjedna koji počinje s `start`. */
fun StatisticsEngine.sessionsInWeek(start: Instant, calendar: StatsCalendar = StatsCalendar.system()): List<Session> =
    store.finishedSessions(start, calendar.addWeeks(start, 1))
