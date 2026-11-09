package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.WorkoutKind
import java.time.Instant

enum class HistorySort { NEWEST_FIRST, OLDEST_FIRST }

/** Filter i sortiranje popisa odrađenih treninga. Prazan skup vrsta znači sve vrste. */
data class HistoryFilter(val kinds: Set<WorkoutKind> = emptySet(), val sort: HistorySort = HistorySort.NEWEST_FIRST) {

    /**
     * Primjenjuje filter i sortiranje na već učitane treninge. `kindsOf` daje vrste treninga; u sučelju je to
     * `SessionMix.kinds`, pa je trening snage s kardiom i pod snagom i pod kardiom.
     */
    fun apply(sessions: List<Session>, kindsOf: (Session) -> Set<WorkoutKind> = { setOf(it.kind) }): List<Session> {
        val selected = if (kinds.isEmpty()) sessions else sessions.filter { kindsOf(it).any(kinds::contains) }
        return if (sort == HistorySort.NEWEST_FIRST) selected.sortedByDescending { it.startedAt } else selected.sortedBy { it.startedAt }
    }

    /** Popis ispod kalendara: treninzi odabranog dana ili, bez odabira, cijelog prikazanog mjeseca. */
    fun apply(
        sessions: List<Session>,
        month: Instant,
        day: Instant?,
        calendar: StatsCalendar = StatsCalendar.system(),
        kindsOf: (Session) -> Set<WorkoutKind> = { setOf(it.kind) },
    ): List<Session> {
        val interval = if (day == null) calendar.monthInterval(month) else calendar.dayInterval(day)
        return apply(sessions.filter { it.startedAt >= interval.start && it.startedAt < interval.end }, kindsOf)
    }
}

/** Povijest odrađenih treninga: popis, dani s treningom za kalendar i brisanje. */
class HistoryQueries(private val store: GymStore) {

    fun sessions(filter: HistoryFilter = HistoryFilter()): List<Session> = filter.apply(store.finishedSessions())

    /** Početak svakog dana u rasponu u kojem postoji odrađen trening (točkice u kalendaru). */
    fun workoutDays(interval: DateInterval, calendar: StatsCalendar = StatsCalendar.system()): Set<Instant> =
        store.finishedSessions(interval.start, interval.end).map { calendar.startOfDay(it.startedAt) }.toSet()

    /** Treninzi odrađeni određenog dana, od najranijeg. */
    fun sessions(day: Instant, calendar: StatsCalendar = StatsCalendar.system()): List<Session> {
        val interval = calendar.dayInterval(day)
        return store.finishedSessions(interval.start, interval.end).reversed()
    }

    /** Briše trening zajedno s vježbama i serijama. Raspored se ne vraća unatrag. */
    fun delete(session: Session) {
        store.delete(session)
        store.save()
    }
}
