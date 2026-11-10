package com.brunodobric.gymapp.widgets

import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.units.WeightUnit
import java.nio.file.Files
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale
import java.util.UUID
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Petak 15. 1. 2027., 08:00 UTC. */
internal val base: Instant = Instant.ofEpochSecond(1_800_000_000)
internal const val DAY = 86_400L

/** UTC, tjedan od ponedjeljka (kao `calendar` u testovima GymKita). */
internal val utcMonday = StatsCalendar(ZoneOffset.UTC, DayOfWeek.MONDAY)

private val weekStart: Instant get() = utcMonday.weekInterval(base).start

// Port GymKit/Tests/WidgetDataTests/WidgetDataTests.swift.
class WidgetDataTest {
    private val croatian = Locale.forLanguageTag("hr-HR")

    @Test
    fun `plan vjezbe - serije x ponavljanja i tezina, trajanje ili samo serije`() {
        val unit = WeightUnit.KILOGRAMS
        assertEquals("4 × 8 · 80 kg", WidgetSnapshot.PlannedExercise("Bench", 4, reps = 8, weightKg = 80.0).summary(unit, croatian))
        assertEquals("3 × 12", WidgetSnapshot.PlannedExercise("Dips", 3, reps = 12).summary(unit, croatian))
        assertEquals("3 × 0:45", WidgetSnapshot.PlannedExercise("Plank", 3, durationSeconds = 45).summary(unit, croatian))
        assertEquals("2 × 5 · 82,5 kg", WidgetSnapshot.PlannedExercise("Bench", 2, reps = 5, weightKg = 82.5).summary(unit, croatian))
        assertEquals("", WidgetSnapshot.PlannedExercise("Prazno", 0).summary(unit))
    }

    @Test
    fun `tezina se prikazuje u odabranoj jedinici`() {
        val exercise = WidgetSnapshot.PlannedExercise("Bench", 1, reps = 5, weightKg = 45.359237)
        assertEquals("1 × 5 · 100 lbs", exercise.summary(WeightUnit.POUNDS, Locale.US))
    }

    @Test
    fun `sljedeci trening pamti najvise tri vjezbe i broji ostale`() {
        val exercises = (1..5).map { WidgetSnapshot.PlannedExercise("V$it", 3) }
        val next = WidgetSnapshot.NextWorkout("Push", null, 5, exercises)
        assertEquals(listOf("V1", "V2", "V3"), next.exercises.map { it.name })
        assertEquals(2, next.remainingExercises)
    }

    @Test
    fun `krivulja tezine je izmedu 0 i 1, ravna je na sredini, a jedna tocka nema krivulje`() {
        assertEquals(listOf(1.0, 0.5, 0.0), WidgetSnapshot.BodyWeight(80.0, base, null, listOf(82.0, 81.0, 80.0)).normalizedPoints)
        assertEquals(listOf(0.5, 0.5), WidgetSnapshot.BodyWeight(80.0, base, null, listOf(80.0, 80.0)).normalizedPoints)
        assertTrue(WidgetSnapshot.BodyWeight(80.0, base, null, listOf(80.0)).normalizedPoints.isEmpty())
        val many = WidgetSnapshot.BodyWeight(80.0, base, null, (1..50).map { it.toDouble() })
        assertEquals(WidgetSnapshot.BodyWeight.MAX_POINTS, many.points.size)
        assertEquals(50.0, many.points.last())
    }

    @Test
    fun `zadnji trening pamti najvise dva rekorda`() {
        val highlights = (1..3).map { WidgetSnapshot.Highlight("V$it", "$it") }
        val last = WidgetSnapshot.LastWorkout("Legs", base, 60, WidgetSnapshot.Mix.STRENGTH, 3, highlights)
        assertEquals(2, last.highlights.size)
    }

    @Test
    fun `dani od treninga se broje po kalendarskim danima`() {
        assertEquals(0, WidgetDates.daysAgo(base, base, utcMonday))
        // Jučer u 23:00 je prije jednog dana i kad je prošlo samo nekoliko sati.
        val lateYesterday = utcMonday.startOfDay(base).minusSeconds(3600)
        assertEquals(1, WidgetDates.daysAgo(lateYesterday, base, utcMonday))
        assertEquals(3, WidgetDates.daysAgo(base.minusSeconds(3 * DAY), base, utcMonday))
        assertEquals(0, WidgetDates.daysAgo(base.plusSeconds(DAY), base, utcMonday))
    }

    @Test
    fun `iduca ponoc za osvjezavanje widgeta`() {
        assertEquals(utcMonday.startOfDay(base).plusSeconds(DAY), WidgetDates.nextMidnight(base, utcMonday))
    }

    private fun week(sessions: Int, goal: Int?, streak: Int): WidgetSnapshot.Week {
        val week = WidgetSnapshot.Week.empty(weekStart, sessions, goal, streak, utcMonday)
        return week.copy(days = week.days.mapIndexed { index, day -> if (index == 0) day.copy(strength = sessions > 0) else day })
    }

    @Test
    fun `u istom tjednu snimka ostaje ista`() {
        val current = week(2, 3, 1)
        assertEquals(current, current.current(base, utcMonday))
        assertEquals(current, current.current(weekStart, utcMonday))
    }

    @Test
    fun `iduci tjedan je prazan, a niz se nastavlja samo ako je cilj ispunjen`() {
        val nextMonday = weekStart.plusSeconds(7 * DAY + 3600)
        val met = week(3, 3, 4).current(nextMonday, utcMonday)
        assertEquals(0, met.sessions)
        assertEquals(4, met.streakWeeks)
        assertEquals(3, met.goal)
        assertEquals(utcMonday.date(weekStart.plusSeconds(7 * DAY)), utcMonday.date(met.start))
        assertEquals(7, met.days.size)
        assertTrue(met.days.none { it.isTrained })
        assertEquals(0, week(2, 3, 4).current(nextMonday, utcMonday).streakWeeks)
    }

    @Test
    fun `nakon praznog tjedna niz je prekinut`() {
        val later = week(3, 3, 4).current(weekStart.plusSeconds(15 * DAY), utcMonday)
        assertEquals(0, later.streakWeeks)
        assertEquals(0, later.sessions)
    }

    @Test
    fun `bez cilja tjedan s jednim treningom nastavlja niz`() {
        val next = week(1, null, 2).current(weekStart.plusSeconds(8 * DAY), utcMonday)
        assertEquals(2, next.streakWeeks)
        assertNull(next.goalFraction)
    }

    @Test
    fun `udio cilja je ogranicen na 1, a cilj 0 znaci bez cilja`() {
        assertEquals(0.5, week(2, 4, 0).goalFraction)
        assertEquals(1.0, week(5, 4, 0).goalFraction)
        assertNull(week(1, 0, 0).goal)
    }

    @Test
    fun `svaka poveznica se procita natrag`() {
        val links = listOf(
            WidgetLink.Home, WidgetLink.StartWorkout, WidgetLink.ActiveWorkout, WidgetLink.Week, WidgetLink.BodyWeight,
            WidgetLink.LastWorkout, WidgetLink.Session(UUID.fromString("6E1F2A3B-4C5D-4E6F-8A9B-0C1D2E3F4A5B")),
        )
        links.forEach { assertEquals(it, WidgetLink.parse(it.uri)) }
    }

    @Test
    fun `trening u tijeku ima istu poveznicu kao na iOS-u, a tude poveznice se odbijaju`() {
        assertEquals("apolon://trening", WidgetLink.ActiveWorkout.uri)
        assertEquals("apolon://povijest/6E1F2A3B-4C5D-4E6F-8A9B-0C1D2E3F4A5B",
            WidgetLink.Session(UUID.fromString("6e1f2a3b-4c5d-4e6f-8a9b-0c1d2e3f4a5b")).uri)
        assertNull(WidgetLink.parse("https://apolon.app/trening"))
        assertNull(WidgetLink.parse("apolon://nepoznato"))
        assertNull(WidgetLink.parse("apolon://povijest/nije-uuid"))
    }

    @Test
    fun `snimka se sprema i cita, a ista snimka s novim vremenom nije promjena`() {
        val directory = Files.createTempDirectory("widget").toFile()
        try {
            val store = WidgetSnapshotStore(directory)
            assertNull(store.load())
            val snapshot = WidgetSnapshot.sample(base, utcMonday)
                .copy(activeWorkout = WidgetSnapshot.ActiveWorkout("Push", base.minusNanos(1_234_567_891)))
            assertTrue(store.save(snapshot))
            assertEquals(snapshot, store.load())

            var later = snapshot.copy(generatedAt = base.plusSeconds(60))
            assertFalse(store.save(later))

            later = later.copy(week = later.week?.copy(sessions = 3))
            assertTrue(store.save(later))
            assertEquals(3, store.load()?.week?.sessions)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `bez mape nema spremanja`() {
        val store = WidgetSnapshotStore(null)
        assertFalse(store.save(WidgetSnapshot.EMPTY))
        assertNull(store.load())
    }
}
