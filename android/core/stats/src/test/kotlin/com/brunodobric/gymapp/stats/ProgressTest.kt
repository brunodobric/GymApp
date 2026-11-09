package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.Sex
import com.brunodobric.gymapp.training.SetMetrics
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/StatsTests: ProgressTests (trend, detaljna statistika, DOTS), ChartRangeTests, ChartValueDomainTests.

private val press = ExerciseRef.catalog("press", "Potisak")
private val now = base

internal val progressInfo: ExerciseInfoProvider = { key ->
    when (key) {
        "c:press" -> ExerciseInfo(listOf(Muscle.CHEST), primaryRegions = listOf("chest"), isCompound = true)
        "c:curl" -> ExerciseInfo(listOf(Muscle.BICEPS), primaryRegions = listOf("biceps"), isCompound = false)
        else -> null
    }
}

/** Završen trening s jednom vježbom; serije su (težina, ponavljanja, RPE), označene jedna za drugom. */
internal fun GymStore.addLift(
    ref: ExerciseRef = press,
    daysAgo: Double,
    sets: List<Triple<Double, Int, Double?>>,
    templateId: UUID? = null,
    restSeconds: Long = 120,
): Session {
    val date = now.plusDays(-daysAgo)
    val session = insert(Session("Trening", startedAt = date))
    session.state = SessionState.FINISHED
    session.endedAt = date.plusSeconds(3600)
    session.templateId = templateId
    val exercise = session.add(SessionExercise(0, ref, ExerciseInputType.WEIGHT_REPS))
    sets.forEachIndexed { index, (weight, reps, rpe) ->
        val set = exercise.add(SetLog(index, SetKind.WORKING))
        set.weightKg = weight
        set.reps = reps
        set.rpe = rpe
        set.completedAt = date.plusSeconds(600 + index * restSeconds)
    }
    save()
    return session
}

private fun trend(values: List<Double>, days: List<Double>, noise: Double = 0.03): ExerciseTrend {
    val points = values.zip(days).map { (value, ago) -> TrendPoint(now.plusDays(-ago), value) }
    return TrendAnalysis.trend(points, now, defaultNoise = noise)
}

class ProgressTest {

    @Nested
    inner class TrendAnalysisTests {
        @Test
        fun `Theil–Sen nagib i medijan`() {
            assertEquals(2.0, TrendAnalysis.median(listOf(3.0, 1.0, 2.0)))
            assertEquals(2.5, TrendAnalysis.median(listOf(4.0, 1.0, 2.0, 3.0)))
            assertNull(TrendAnalysis.median(emptyList()))
            // Jedna iznimna točka ne mijenja nagib.
            val slope = assertNotNull(TrendAnalysis.theilSenSlope(listOf(0.0 to 0.0, 1.0 to 1.0, 2.0 to 2.0, 3.0 to 30.0, 4.0 to 4.0)))
            assertTrue(abs(slope - 1) < 1e-9)
            assertNull(TrendAnalysis.theilSenSlope(listOf(1.0 to 1.0, 1.0 to 2.0)))
        }

        @Test
        fun `napreduje, pada, stoji i plato`() {
            assertEquals(ExerciseStatus.IMPROVING, trend(listOf(100.0, 103.0, 106.0, 109.0), listOf(42.0, 28.0, 14.0, 1.0)).status)
            assertEquals(ExerciseStatus.DECLINING, trend(listOf(109.0, 106.0, 103.0, 100.0), listOf(42.0, 28.0, 14.0, 1.0)).status)
            // Bez promjene tri tjedna: stoji; pet tjedana: plato.
            assertEquals(ExerciseStatus.STABLE, trend(listOf(100.0, 100.5, 100.0, 100.5), listOf(21.0, 14.0, 7.0, 1.0)).status)
            assertEquals(ExerciseStatus.PLATEAU, trend(listOf(100.0, 100.5, 100.0, 100.5), listOf(35.0, 21.0, 7.0, 1.0)).status)
        }

        @Test
        fun `premalo izvođenja ili izvan razdoblja - nema statusa`() {
            assertEquals(ExerciseStatus.INSUFFICIENT_DATA, trend(listOf(100.0, 105.0, 110.0), listOf(21.0, 14.0, 7.0)).status)
            assertEquals(ExerciseStatus.INSUFFICIENT_DATA, trend(listOf(100.0, 105.0, 110.0, 115.0), listOf(90.0, 80.0, 70.0, 7.0)).status)
        }

        @Test
        fun `mjesečna promjena je relativna`() {
            val days = listOf(42.0, 28.0, 14.0, 0.0)
            val deadlift = assertNotNull(trend(listOf(200.0, 202.5, 205.0, 207.5), days).monthlyChange)
            val curls = assertNotNull(trend(listOf(20.0, 22.5, 25.0, 27.5), days).monthlyChange)
            assertTrue(deadlift > 0.02 && deadlift < 0.03)
            assertTrue(curls > 0.2)
        }

        @Test
        fun `kolebanje se uči iz podataka od šest izvođenja, unutar granica`() {
            val days = listOf(50.0, 40.0, 30.0, 20.0, 10.0, 1.0)
            val noisy = trend(listOf(100.0, 110.0, 95.0, 112.0, 96.0, 111.0), days)
            assertTrue(noisy.noise > 0.03 && noisy.noise <= TrendAnalysis.noiseRange.endInclusive)
            assertTrue(noisy.status == ExerciseStatus.STABLE || noisy.status == ExerciseStatus.PLATEAU)
            val smooth = trend(List(6) { 100.0 }, days)
            assertEquals(TrendAnalysis.noiseRange.start, smooth.noise)
        }

        @Test
        fun `točke za trend - procjena 1RM, a bez tereta ponavljanja`() {
            assertEquals(TrendMeasure.ONE_REP_MAX, TrendAnalysis.points(listOf(ExercisePoint(now, 100.0, 5, 116.0, 500.0)))?.first)
            val reps = assertNotNull(TrendAnalysis.points(listOf(ExercisePoint(now, 0.0, 12, null, 0.0))))
            assertEquals(TrendMeasure.REPS, reps.first)
            assertEquals(12.0, reps.second.first().value)
            assertNull(TrendAnalysis.points(listOf(ExercisePoint(now, 50.0, 20, null, 1000.0))))
        }
    }

    @Nested
    inner class ProStatisticsTests {
        @Test
        fun `tablica rekorda po ponavljanjima`() {
            val store = newStore()
            store.addLift(daysAgo = 7.0, sets = listOf(Triple(100.0, 5, null), Triple(80.0, 10, null)))
            store.addLift(daysAgo = 1.0, sets = listOf(Triple(110.0, 1, null), Triple(90.0, 8, null)))
            val table = StatisticsEngine(store).repMaxTable(press)
            assertEquals(listOf(1, 3, 5, 8, 10), table.map { it.reps })
            assertEquals(listOf(110.0, 100.0, 100.0, 90.0, 80.0), table.map { it.weightKg })
        }

        @Test
        fun `napor po RIR-u i intenzitet prema najboljoj procjeni 1RM`() {
            val store = newStore()
            store.addLift(daysAgo = 2.0, sets = listOf(Triple(100.0, 5, 10.0), Triple(90.0, 5, 8.0), Triple(50.0, 10, 4.0), Triple(65.0, 5, null)))
            val engine = StatisticsEngine(store)
            val effort = engine.effortDistribution(now.plusDays(-7.0), now)
            assertEquals(listOf(1, 0, 1, 0, 1), effort.counts)
            assertEquals(1, effort.unrated)
            // 50 i 65 kg ispod 60 %, 90 kg 77 %, 100 kg 86 %.
            assertEquals(listOf(2, 0, 1, 1), engine.intensityDistribution(now.plusDays(-7.0), now).counts)
            assertEquals(3, IntensityDistribution.zone(0.9))
        }

        @Test
        fun `trend vježbe i popis trendova`() {
            val store = newStore()
            for ((ago, weight) in listOf(42.0 to 100.0, 28.0 to 103.0, 14.0 to 106.0, 1.0 to 109.0)) {
                store.addLift(daysAgo = ago, sets = listOf(Triple(weight, 5, null)))
            }
            val engine = StatisticsEngine(store)
            val entry = assertNotNull(engine.exerciseTrend(press, now = now, info = progressInfo))
            assertEquals(ExerciseStatus.IMPROVING, entry.trend.status)
            assertEquals(listOf("chest"), entry.primaryRegions)
            assertEquals(listOf("Potisak"), engine.exerciseTrends(now = now, info = progressInfo).map { it.name })
        }
    }

    @Nested
    inner class DotsTests {
        @Test
        fun `formula daje poznate vrijednosti za muškarce i žene`() {
            assertTrue(abs(assertNotNull(Dots.points(600.0, 100.0, Sex.MALE)) - 369.31) < 0.01)
            assertTrue(abs(assertNotNull(Dots.points(300.0, 60.0, Sex.FEMALE)) - 332.56) < 0.01)
            assertNull(Dots.points(0.0, 80.0, Sex.MALE))
            assertNull(Dots.points(500.0, 0.0, Sex.FEMALE))
        }

        @Test
        fun `masa izvan raspona formule uzima se kao granica`() {
            assertEquals(Dots.points(600.0, 210.0, Sex.MALE), Dots.points(600.0, 250.0, Sex.MALE))
            assertEquals(Dots.points(300.0, 40.0, Sex.FEMALE), Dots.points(300.0, 30.0, Sex.FEMALE))
        }

        @Test
        fun `zbroj je iz najbolje procjene 1RM triju dizanja u razdoblju`() {
            val store = newStore()
            val squat = ExerciseRef.catalog("barbell-squat", "Čučanj")
            val bench = ExerciseRef.catalog("barbell-bench-press", "Potisak")
            val deadlift = ExerciseRef.catalog("barbell-deadlift", "Mrtvo")
            store.addLift(squat, 10.0, listOf(Triple(150.0, 1, null)))
            store.addLift(squat, 3.0, listOf(Triple(140.0, 1, null)))
            store.addLift(bench, 5.0, listOf(Triple(100.0, 1, null)))
            // Izvan 12 tjedana: ne ulazi.
            store.addLift(deadlift, 100.0, listOf(Triple(250.0, 1, null)))
            val engine = StatisticsEngine(store)

            val partial = assertNotNull(engine.dotsScore(90.0, Sex.MALE, now = now))
            assertEquals(listOf("barbell-deadlift"), partial.missingLifts)
            assertNull(partial.totalKg)
            assertNull(partial.points)

            store.addLift(deadlift, 2.0, listOf(Triple(200.0, 1, null)))
            val score = assertNotNull(engine.dotsScore(90.0, Sex.MALE, now = now))
            val total = listOf(150.0, 100.0, 200.0).sumOf { SetMetrics.estimatedOneRepMax(it, 1) ?: 0.0 }
            assertTrue(abs((score.totalKg ?: 0.0) - total) < 0.001)
            assertEquals(Dots.points(total, 90.0, Sex.MALE), score.points)
        }

        @Test
        fun `bez ijednog od tri dizanja nema rezultata`() {
            val store = newStore()
            store.addLift(daysAgo = 2.0, sets = listOf(Triple(80.0, 5, null)))
            assertNull(StatisticsEngine(store).dotsScore(80.0, Sex.FEMALE, now = now))
        }
    }

    @Nested
    inner class ChartRangeTests {
        private val utc = utcMonday
        private fun point(daysAgo: Double) = ExercisePoint(now.plusDays(-daysAgo), 50.0, 8, null, 400.0)
        private val points = listOf(400.0, 200.0, 70.0, 45.0, 20.0, 3.0, 0.0).map(::point)

        @Test
        fun `sve zadržava svaku točku`() {
            assertNull(ChartRange.All.interval(now, utc))
            assertEquals(points.size, ChartRange.All.filter(points, now, utc).size)
        }

        @Test
        fun `mjeseci se broje od početka današnjeg dana`() {
            val interval = assertNotNull(ChartRange.Months(1).interval(now, utc))
            // 15. 12. 2026. u ponoć do sada.
            assertEquals(LocalDate.of(2026, 12, 15).atStartOfDay(ZoneOffset.UTC).toInstant(), interval.start)
            assertEquals(now, interval.end)
            assertEquals(3, ChartRange.Months(1).filter(points, now, utc).size)
            assertEquals(4, ChartRange.Months(2).filter(points, now, utc).size)
            assertEquals(5, ChartRange.Months(6).filter(points, now, utc).size)
            assertEquals(6, ChartRange.Months(12).filter(points, now, utc).size)
        }

        @Test
        fun `vlastiti raspon uključuje cijele dane i okreće obrnute datume`() {
            val from = now.plusDays(-45.0).plusSeconds(3600)
            val to = now.plusDays(-20.0).minusSeconds(3600)
            val range = ChartRange.Custom(to, from)
            val interval = assertNotNull(range.interval(now, utc))
            assertEquals(utc.startOfDay(from), interval.start)
            assertTrue(interval.end < utc.addDays(utc.startOfDay(to), 1))
            assertEquals(listOf(point(45.0).date, point(20.0).date), range.filter(points, now, utc).map { it.date })
        }
    }

    @Nested
    inner class ChartValueDomainTests {
        @Test
        fun `jednake vrijednosti dobivaju raspon`() {
            val domain = ChartValueDomain.domain(listOf(14.0, 14.0, 14.0))
            assertTrue(abs(domain.start - 12.6) < 1e-9)
            assertTrue(abs(domain.endInclusive - 15.4) < 1e-9)
        }

        @Test
        fun `male jednake vrijednosti dobivaju barem jednu jedinicu i ostaju iznad nule`() {
            val domain = ChartValueDomain.domain(listOf(0.5, 0.5))
            assertEquals(0.0, domain.start)
            assertEquals(1.5, domain.endInclusive)
            assertEquals(0.0..1.0, ChartValueDomain.domain(listOf(0.0)))
        }

        @Test
        fun `različite vrijednosti dobivaju razmak, pozitivne ne idu ispod nule`() {
            val domain = ChartValueDomain.domain(listOf(10.0, 40.0, 20.0))
            assertTrue(abs(domain.start - 7) < 1e-9)
            assertTrue(abs(domain.endInclusive - 43) < 1e-9)
            assertEquals(0.0, ChartValueDomain.domain(listOf(1.0, 100.0)).start)
        }

        @Test
        fun `prazan popis ima zadani raspon`() {
            assertEquals(0.0..1.0, ChartValueDomain.domain(emptyList()))
            assertEquals(0.0..1.0, ChartValueDomain.domain(listOf(Double.NaN)))
        }
    }
}
