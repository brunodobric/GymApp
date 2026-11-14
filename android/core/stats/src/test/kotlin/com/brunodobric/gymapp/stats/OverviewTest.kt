package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.MeasurementSource
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.training.SessionMix
import java.time.Instant
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/StatsTests/StatsTests.swift: praćenje tijela, ovaj tjedan i pregled razdoblja.
class OverviewTest {

    private fun close(expected: Double, actual: Double) = assertTrue(abs(expected - actual) < 0.0001, "$expected != $actual")

    @Nested
    inner class BodyTrackingTests {
        @Test
        fun `tezina iz precaca sprema se u kg, a broj izvan razumnog raspona se odbija`() {
            val tracking = BodyTracking(newStore())
            val saved = tracking.addShortcutWeight(81.4, base)
            assertEquals(BodyMeasurementKind.WEIGHT, saved.kind)
            assertEquals(81.4, saved.value)
            assertEquals(MeasurementSource.MANUAL, saved.source)
            assertThrows<BodyTrackingException> { tracking.addShortcutWeight(8.0, base) }
            assertThrows<BodyTrackingException> { tracking.addShortcutWeight(800.0, base) }
            assertThrows<BodyTrackingException> { tracking.addShortcutWeight(Double.NaN, base) }
            assertEquals(1, tracking.measurements(BodyMeasurementKind.WEIGHT).size)
        }

        @Test
        fun `unos, povijest, promjena i brisanje`() {
            val tracking = BodyTracking(newStore())
            tracking.add(BodyMeasurementKind.WEIGHT, 82.0, base)
            val last = tracking.add(BodyMeasurementKind.WEIGHT, 80.5, base.plusDays(7.0))
            tracking.add(BodyMeasurementKind.WAIST, 90.0, base)

            assertEquals(listOf(82.0, 80.5), tracking.measurements(BodyMeasurementKind.WEIGHT).map { it.value })
            assertEquals(80.5, tracking.latest(BodyMeasurementKind.WEIGHT)?.value)
            assertEquals(-1.5, tracking.change(BodyMeasurementKind.WEIGHT))
            assertNull(tracking.change(BodyMeasurementKind.WAIST))
            tracking.delete(last)
            assertEquals(1, tracking.measurements(BodyMeasurementKind.WEIGHT).size)
        }

        @Test
        fun `promjena u zadnjih 30 dana prema mjerenju starom barem 30 dana, inace prema prvom`() {
            val tracking = BodyTracking(newStore())
            tracking.add(BodyMeasurementKind.WEIGHT, 85.0, base)
            assertNull(tracking.recentChange(BodyMeasurementKind.WEIGHT))
            tracking.add(BodyMeasurementKind.WEIGHT, 84.0, base.plusDays(10.0))
            assertEquals(-1.0, tracking.recentChange(BodyMeasurementKind.WEIGHT))
            tracking.add(BodyMeasurementKind.WEIGHT, 83.0, base.plusDays(20.0))
            tracking.add(BodyMeasurementKind.WEIGHT, 82.5, base.plusDays(45.0))
            // Zadnje mjerenje je 45. dan: referenca je 10. dan (zadnje do 15. dana), ne prvo.
            assertEquals(-1.5, tracking.recentChange(BodyMeasurementKind.WEIGHT))
        }

        @Test
        fun `neispravne vrijednosti se odbijaju`() {
            val tracking = BodyTracking(newStore())
            assertThrows<BodyTrackingException> { tracking.add(BodyMeasurementKind.WEIGHT, 0.0) }
            assertThrows<BodyTrackingException> { tracking.add(BodyMeasurementKind.WEIGHT, -3.0) }
            assertThrows<BodyTrackingException> { tracking.add(BodyMeasurementKind.WEIGHT, Double.NaN) }
        }

        @Test
        fun `vlastite mjere se razlikuju po nazivu`() {
            val tracking = BodyTracking(newStore())
            tracking.add(BodyMeasurementKind.CUSTOM, 35.0, customName = "Podlaktica")
            tracking.add(BodyMeasurementKind.CUSTOM, 38.0, customName = " Vrat ")
            tracking.add(BodyMeasurementKind.CUSTOM, 36.0, Instant.now().plusSeconds(DAY), customName = "Podlaktica")
            assertEquals(listOf("Podlaktica", "Vrat"), tracking.customNames())
            assertEquals(listOf(35.0, 36.0), tracking.measurements(BodyMeasurementKind.CUSTOM, "Podlaktica").map { it.value })
            assertEquals(1, tracking.measurements(BodyMeasurementKind.CUSTOM, "Vrat").size)
        }
    }

    @Nested
    inner class WeekProgressTests {
        private val run = ExerciseRef.catalog("run", "Trčanje")
        private val isCardio: (String) -> Boolean = { it == "c:run" }

        /** Ponedjeljak tjedna u kojem je `base` (petak). */
        private val monday = base.plusDays(-4.0)
        private val three = listOf(Work(100.0, 5), Work(100.0, 5), Work(100.0, 5))

        /** Trening snage s kardio vježbom od 20 minuta. */
        private fun GymStore.addMixed(at: Instant): Session {
            val session = addSession(at, lifts = listOf(Lift(bench, listOf(Work(80.0, 8), Work(80.0, 8)))))
            val exercise = session.add(SessionExercise(1, run, ExerciseInputType.DURATION))
            val set = exercise.add(SetLog(0))
            set.durationSeconds = 1200
            set.completedAt = at
            save()
            return session
        }

        @Test
        fun `treninzi, dani, tvrde serije, kardio i niz tjedana`() {
            val store = newStore()
            val sessions = mutableListOf<Session>()
            sessions += store.addSession(monday, lifts = listOf(Lift(squat, three)))
            sessions += store.addSession(monday.plusDays(2.0), WorkoutKind.CARDIO, emptyList())
            sessions += store.addMixed(monday.plusDays(3.0))
            // Nezavršeni trening i trening idućeg tjedna se ne broje.
            val active = store.addSession(monday.plusDays(1.0), lifts = listOf(Lift(squat, three)))
            active.state = SessionState.ACTIVE
            sessions += active
            sessions += store.addSession(monday.plusDays(8.0), lifts = listOf(Lift(squat, three)))
            // Prošla dva tjedna po tri treninga, a tjedan prije njih samo jedan.
            for (week in 1..2) {
                for (offset in 0 until 3) {
                    sessions += store.addSession(monday.plusDays(-week * 7.0 + offset), lifts = listOf(Lift(bench, three)))
                }
            }
            sessions += store.addSession(monday.plusDays(-20.0), lifts = listOf(Lift(bench, three)))

            val progress = WeekProgress.make(sessions, base, 3, utcMonday, isCardio)
            assertEquals(monday.minusSeconds(8 * 3600), progress.start)
            assertEquals(3, progress.sessions)
            assertEquals(1.0, progress.goalFraction)
            assertEquals(5, progress.hardSets)
            assertEquals(3600 + 1200, progress.cardioSeconds)
            assertEquals(3 * 3600.0, progress.totalSeconds)
            assertEquals(
                listOf(SessionMix.STRENGTH, null, SessionMix.CARDIO, SessionMix.MIXED, null, null, null),
                progress.days.map { it.mix },
            )
            assertEquals(3, progress.streakWeeks)
        }

        @Test
        fun `brojke treninga - snaga s kardiom, kardio s udaljenoscu`() {
            val store = newStore()
            val mixed = SessionFigures.of(store.addMixed(monday), isCardio)
            assertEquals(SessionFigures(3600.0, 2, 1200, null), mixed)

            val running = store.addSession(monday, WorkoutKind.CARDIO, emptyList())
            running.distanceMeters = 7200.0
            assertEquals(SessionFigures(3600.0, 0, 3600, 7200.0), SessionFigures.of(running, isCardio))

            val progress = WeekProgress.make(listOf(running), base, null, utcMonday, isCardio)
            assertEquals(7200.0, progress.cardioMeters)
        }

        @Test
        fun `treninzi po danima - poravnato s danima tjedna, od ranijeg, bez nezavrsenih`() {
            val store = newStore()
            val evening = store.addSession(monday.plusSeconds(10 * 3600), lifts = emptyList())
            val morning = store.addSession(monday, lifts = emptyList())
            val friday = store.addSession(base, WorkoutKind.CARDIO, emptyList())
            val active = store.addSession(base, lifts = emptyList())
            active.state = SessionState.ACTIVE
            val sessions = listOf(evening, morning, friday, active)
            val progress = WeekProgress.make(sessions, base, null, utcMonday, isCardio)
            val days = progress.sessionsByDay(sessions, utcMonday)
            assertEquals(7, days.size)
            assertEquals(listOf(morning.id, evening.id), days[0].map { it.id })
            assertEquals(listOf(friday.id), days[4].map { it.id })
            assertTrue(days[1].isEmpty() && days[6].isEmpty())
        }

        @Test
        fun `bez cilja se broji tjedan s barem jednim treningom, a nedovrsen tjedan ne prekida niz`() {
            val store = newStore()
            val sessions = (1..4).map { week -> store.addSession(monday.plusDays(-week * 7.0), lifts = emptyList()) }
            val progress = WeekProgress.make(sessions, base, null, utcMonday, isCardio)
            assertEquals(0, progress.sessions)
            assertNull(progress.goalFraction)
            assertEquals(4, progress.streakWeeks)

            val withGoal = WeekProgress.make(sessions, base, 2, utcMonday, isCardio)
            assertEquals(0.0, withGoal.goalFraction)
            assertEquals(0, withGoal.streakWeeks)
        }

        @Test
        fun `prazan tjedan izmedu ispunjenih ne prekida niz, ali najvise jedan u cetiri tjedna`() {
            assertEquals(3, WeekProgress.streakLength(listOf(3, 0, 3, 3), 3))
            assertEquals(2, WeekProgress.streakLength(listOf(0, 3, 3), 3))
            assertEquals(1, WeekProgress.streakLength(listOf(3, 1, 3), 3))
            assertEquals(1, WeekProgress.streakLength(listOf(3, 0, 0, 3), 3))
            assertEquals(1, WeekProgress.streakLength(listOf(3, 0), 3))
            assertEquals(2, WeekProgress.streakLength(listOf(3, 0, 3, 0, 3), 3))
            assertEquals(5, WeekProgress.streakLength(listOf(3, 0, 3, 3, 3, 0, 3), 3))
        }
    }

    @Nested
    inner class PeriodOverviewTests {
        private val isCardio: (String) -> Boolean = { false }
        private val three = listOf(Work(100.0, 5), Work(100.0, 5), Work(100.0, 5))

        /** 1. 1. 2027., 00:00 UTC. */
        private val january = utcMonday.monthInterval(base).start

        @Test
        fun `tjedan, mjesec i godina prema kalendaru i pomak na susjedno razdoblje`() {
            val monday = base.plusDays(-4.0).minusSeconds(8 * 3600)
            assertEquals(monday, OverviewPeriod.WEEK.interval(base, utcMonday).start)
            assertEquals(DateInterval(january, january.plusSeconds(31 * DAY)), OverviewPeriod.MONTH.interval(base, utcMonday))
            assertEquals(365.0 * DAY, OverviewPeriod.YEAR.interval(base, utcMonday).durationSeconds)
            val december = OverviewPeriod.MONTH.shift(base, -1, utcMonday)
            assertEquals(12, utcMonday.zoned(december).monthValue)
            assertEquals(2028, utcMonday.zoned(OverviewPeriod.YEAR.shift(base, 1, utcMonday)).year)
        }

        @Test
        fun `mjesec - treninzi, dani, tvrde serije, a treninzi izvan mjeseca i nezavrseni se ne broje`() {
            val store = newStore()
            val sessions = mutableListOf<Session>()
            sessions += store.addSession(january.plusDays(3.0).plusSeconds(9 * 3600), lifts = listOf(Lift(squat, three)))
            sessions += store.addSession(base, WorkoutKind.CARDIO, emptyList())
            sessions += store.addSession(january.minusSeconds(3600), lifts = listOf(Lift(squat, three)))
            sessions += store.addSession(january.plusDays(31.0), lifts = listOf(Lift(squat, three)))
            val active = store.addSession(base, lifts = listOf(Lift(squat, three)))
            active.state = SessionState.ACTIVE
            sessions += active

            val summary = PeriodSummary.make(sessions, OverviewPeriod.MONTH, base, now = base, goal = 3, calendar = utcMonday, isCardio = isCardio)
            assertEquals(2, summary.sessions)
            assertEquals(3, summary.hardSets)
            assertEquals(3600, summary.cardioSeconds)
            assertEquals(2 * 3600.0, summary.totalSeconds)
            assertEquals(31, summary.days.size)
            assertEquals(2, summary.trainedDays)
            assertEquals(SessionMix.STRENGTH, summary.days[3].mix)
            assertEquals(SessionMix.CARDIO, summary.days[14].mix)
            assertTrue(summary.months.isEmpty())
            assertEquals(3, summary.weeklyGoal)
            // Tekući mjesec broji tjedne do sada: 14 dana i 8 sati.
            close((14.0 * DAY + 8 * 3600) / (7 * DAY), summary.weeks)
            close(2 / summary.weeks, summary.sessionsPerWeek)

            val byDay = summary.sessionsByDay(sessions, utcMonday)
            assertEquals(2, byDay.size)
            assertEquals(1, byDay[january.plusDays(3.0)]?.size)
        }

        @Test
        fun `godina - dvanaest mjeseci s treninzima, prosjek od prvog treninga`() {
            val store = newStore()
            val first = january.plusDays(9.0)
            val sessions = listOf(
                store.addSession(first, lifts = listOf(Lift(squat, three))),
                store.addSession(base, lifts = listOf(Lift(bench, three))),
                store.addSession(january.plusDays(40.0), lifts = emptyList()),
            )
            val now = january.plusDays(400.0)
            val summary = PeriodSummary.make(sessions, OverviewPeriod.YEAR, base, now, first, null, utcMonday, isCardio)
            assertEquals(365, summary.days.size)
            assertEquals(12, summary.months.size)
            assertEquals(listOf(2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0), summary.months.map { it.sessions })
            assertEquals(6, summary.months[0].hardSets)
            assertNull(summary.weeklyGoal)
            // Prošla godina: tjedni od prvog treninga do kraja godine.
            close(356.0 / 7, summary.weeks)
        }

        @Test
        fun `tjedni za prosjek - najmanje jedan, tekuce razdoblje do sada`() {
            val interval = DateInterval(january, january.plusDays(31.0))
            assertEquals(1.0, PeriodSummary.weeks(interval, january.plusDays(1.0), null))
            close(31.0 / 7, PeriodSummary.weeks(interval, january.plusDays(90.0), null))
            assertEquals(1.0, PeriodSummary.weeks(interval, january.plusDays(90.0), january.plusDays(60.0)))
        }

        @Test
        fun `serije po misicu - tjedan u ukupnim serijama, mjesec u prosjeku tjedno uz mjesec prije`() {
            val store = newStore()
            store.addSession(january.plusDays(-21.0), lifts = listOf(Lift(bench, three)))
            store.addSession(base, lifts = listOf(Lift(squat, three + Work(100.0, 5))))
            val engine = StatisticsEngine(store)
            val now = january.plusDays(40.0)

            val month = assertNotNull(engine.periodVolume(OverviewPeriod.MONTH, base, now, utcMonday, infoProvider))
            val quads = assertNotNull(month.muscles.firstOrNull { it.region == "quads" })
            close(4 / (31.0 / 7), quads.currentSets)
            val chest = assertNotNull(month.muscles.firstOrNull { it.region == "chest" })
            // Prosinac se broji od prvog treninga (11. 12.) do kraja mjeseca: 3 tjedna.
            close(1.0, chest.previousSets)
            assertTrue(month.currentSets == 4 && month.previousSets == 3)

            val week = assertNotNull(engine.periodVolume(OverviewPeriod.WEEK, base, now, utcMonday, infoProvider))
            assertEquals(4.0, week.muscles.firstOrNull { it.region == "quads" }?.currentSets)

            val summary = engine.periodSummary(OverviewPeriod.MONTH, base, now, null, utcMonday) { false }
            assertEquals(1, summary.sessions)
            close(31.0 / 7, summary.weeks)
        }
    }
}
