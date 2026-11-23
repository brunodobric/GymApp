package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.PersonalRecord
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Pravila ekrana Pregled na Androidu (na iOS-u su u `OverviewScreen` i `OverviewSummaryCard`).
class OverviewNavigationTest {

    @Test
    fun `promjena broja treninga, trajanja i postotka prema razdoblju prije`() {
        assertEquals(2, PeriodChange.count(5, 3))
        assertEquals(-1, PeriodChange.count(2, 3))
        assertNull(PeriodChange.count(3, 3))
        assertNull(PeriodChange.count(3, null))

        assertEquals(600.0, PeriodChange.duration(3600.0, 3000.0))
        assertEquals(-120.0, PeriodChange.duration(3000.0, 3120.0))
        // Manje od minute se ne prikazuje.
        assertNull(PeriodChange.duration(3000.0, 3030.0))
        assertNull(PeriodChange.duration(3000.0, null))

        assertEquals(0.5, PeriodChange.percent(15, 10))
        assertEquals(-0.25, PeriodChange.percent(30, 40))
        assertNull(PeriodChange.percent(10, 10))
        assertNull(PeriodChange.percent(10, 0))
        assertNull(PeriodChange.percent(10, null))
    }

    @Test
    fun `tekuce razdoblje, naprijed najdalje do danas i najvise deset godina unatrag`() {
        val now = base
        assertTrue(OverviewNavigation.isCurrent(OverviewPeriod.WEEK, now, now, utcMonday))
        val lastWeek = OverviewNavigation.shift(OverviewPeriod.WEEK, now, -1, now, utcMonday)
        assertFalse(OverviewNavigation.isCurrent(OverviewPeriod.WEEK, lastWeek, now, utcMonday))
        assertEquals(now, OverviewNavigation.shift(OverviewPeriod.WEEK, lastWeek, 1, now, utcMonday))
        // Naprijed iz tekućeg razdoblja ostaje danas.
        assertEquals(now, OverviewNavigation.shift(OverviewPeriod.MONTH, now, 1, now, utcMonday))

        assertTrue(OverviewNavigation.canGoBack(OverviewPeriod.YEAR, now, now, utcMonday))
        val nineYears = OverviewPeriod.YEAR.shift(now, -9, utcMonday)
        assertTrue(OverviewNavigation.canGoBack(OverviewPeriod.YEAR, nineYears, now, utcMonday))
        val tenYears = OverviewPeriod.YEAR.shift(now, -10, utcMonday)
        assertFalse(OverviewNavigation.canGoBack(OverviewPeriod.YEAR, tenYears, now, utcMonday))
    }

    @Test
    fun `rekordi razdoblja su samo oni postavljeni unutar njega`() {
        val week = OverviewPeriod.WEEK.interval(base, utcMonday)
        fun entry(at: java.time.Instant) =
            RecordEntry(at, "bench", "Potisak s klupe", PersonalRecord(PRKind.MAX_WEIGHT, 100.0, 95.0))
        val inside = entry(week.start)
        val before = entry(week.start.minusSeconds(1))
        val atEnd = entry(week.end)
        assertEquals(listOf(inside), OverviewNavigation.records(listOf(atEnd, inside, before), week))
    }
}
