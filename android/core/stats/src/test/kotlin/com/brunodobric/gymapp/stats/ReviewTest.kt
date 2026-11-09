package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseCategory
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.catalog.uppercaseString
import com.brunodobric.gymapp.model.CustomExercise
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.training.CardioPart
import com.brunodobric.gymapp.training.SessionCardio
import com.brunodobric.gymapp.training.SetValues
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/StatsTests: ProgressTests (tjedni pregled, sažetak treninga), ExerciseHistoryTests i
// SessionCardioTests (dio koji ovisi o statistici).

private val reviewPress = ExerciseRef.catalog("press", "Potisak")
private val reviewCurl = ExerciseRef.catalog("curl", "Pregib")

class ReviewTest {

    @Nested
    inner class WeeklyReviewTests {
        private fun entry(name: String, status: ExerciseStatus, region: String = "chest") = ExerciseTrendEntry(
            "c:$name", name, TrendMeasure.ONE_REP_MAX,
            ExerciseTrend(status, 0.01, 0.03, 4, 100.0), listOf(region),
        )

        @Test
        fun `snaga - napreduje ili stoji je dobro, plato i pad nisu`() {
            val good = WeeklyReviewBuilder.strength(
                listOf(entry("a", ExerciseStatus.IMPROVING), entry("b", ExerciseStatus.STABLE), entry("c", ExerciseStatus.IMPROVING), entry("d", ExerciseStatus.PLATEAU)),
            )
            assertTrue(good.level == ReviewLevel.GOOD && good.improving == 2 && good.plateau == 1)
            assertEquals(ReviewLevel.ATTENTION, WeeklyReviewBuilder.strength(listOf(entry("a", ExerciseStatus.DECLINING), entry("b", ExerciseStatus.PLATEAU))).level)
            assertEquals(ReviewLevel.NO_DATA, WeeklyReviewBuilder.strength(listOf(entry("a", ExerciseStatus.INSUFFICIENT_DATA))).level)
        }

        @Test
        fun `volumen prema cilju - zona za rast je 10 do 20 serija, za snagu dovoljno manje`() {
            val sets = BodyRegion.major.associateWith { 6.0 }
            assertEquals(ReviewLevel.ATTENTION, WeeklyReviewBuilder.volume(sets, TrainingGoal.HYPERTROPHY).level)
            assertEquals(ReviewLevel.GOOD, WeeklyReviewBuilder.volume(sets, TrainingGoal.STRENGTH).level)
            assertEquals(ReviewLevel.NO_DATA, WeeklyReviewBuilder.volume(emptyMap(), null).level)
        }

        @Test
        fun `redovitost prema planu iz onboardinga ili prema broju treninga tjedno`() {
            assertEquals(ReviewLevel.GOOD, WeeklyReviewBuilder.consistency(11, 4.0, 3).level)
            assertEquals(ReviewLevel.ATTENTION, WeeklyReviewBuilder.consistency(6, 4.0, 3).level)
            assertEquals(ReviewLevel.GOOD, WeeklyReviewBuilder.consistency(8, 4.0, null).level)
            assertEquals(ReviewLevel.FAIR, WeeklyReviewBuilder.consistency(4, 4.0, null).level)
        }

        @Test
        fun `napor - udio serija s RIR 0 do 3, tek s dovoljno ocijenjenih serija`() {
            assertEquals(ReviewLevel.NO_DATA, WeeklyReviewBuilder.effort(listOf(8.0, 9.0)).level)
            val hard = WeeklyReviewBuilder.effort(List(8) { 8.0 } + listOf(5.0, 6.0))
            assertTrue(hard.level == ReviewLevel.GOOD && hard.closeToFailureShare == 0.8)
        }

        @Test
        fun `prijedlozi - laksi tjedan, manje dana, serije za misic na platou, veca tezina i misic koji je izostao`() {
            val consistency = WeeklyReviewBuilder.consistency(4, 4.0, 3)
            val input = SuggestionInput(
                trends = listOf(
                    entry("Potisak", ExerciseStatus.PLATEAU),
                    entry("Čučanj", ExerciseStatus.DECLINING, "quads"),
                    entry("Veslanje", ExerciseStatus.DECLINING, "lats"),
                ),
                weeklySets = mapOf("chest" to 6.0, "quads" to 12.0),
                lastTrained = mapOf("biceps" to base.plusDays(-20.0), "chest" to base.plusDays(-2.0)),
                consistency = consistency,
                goal = TrainingGoal.HYPERTROPHY,
                easyExercises = listOf("Pregib"),
                now = base,
            )
            val result = SuggestionEngine.suggestions(input)
            assertEquals(Suggestion.Deload(2), result.first())
            assertTrue(Suggestion.FewerDays(1.0, 12) in result)
            assertTrue(Suggestion.AddSets("chest", "Potisak") in result)
            assertTrue(Suggestion.IncreaseLoad("Pregib") in result)
            assertTrue(Suggestion.MissedMuscle("biceps", 20) in result)
            assertFalse(Suggestion.MissedMuscle("chest", 2) in result)
        }

        @Test
        fun `pregled iz baze - trend, volumen, redovitost i lagane vjezbe`() {
            val store = newStore()
            listOf(60.0, 62.5, 65.0, 67.5).forEachIndexed { index, weight ->
                store.addLift(reviewPress, 21.0 - index * 7, listOf(Triple(weight, 5, 8.0), Triple(weight, 5, 8.0), Triple(weight, 5, 9.0)))
            }
            for (daysAgo in listOf(15.0, 8.0, 1.0)) {
                store.addLift(reviewCurl, daysAgo, listOf(Triple(12.0, 10, 5.0), Triple(12.0, 10, 6.0)))
            }
            val engine = StatisticsEngine(store)
            val (review, suggestions) = engine.weeklyReview(base, TrainingGoal.HYPERTROPHY, 2, progressInfo)
            assertEquals(1, review.strength.improving)
            assertEquals(7, review.consistency.sessions)
            assertEquals(18, review.effort.ratedSets)
            assertTrue(Suggestion.IncreaseLoad("Pregib") in suggestions)
            assertEquals(listOf("Pregib"), engine.easyExercises(base))
        }
    }

    @Nested
    inner class SessionComparisonTests {
        @Test
        fun `usporedba s proslim izvodenjem istog treninga`() {
            val store = newStore()
            val template = UUID.randomUUID()
            store.addLift(reviewPress, 7.0, listOf(Triple(80.0, 8, null), Triple(80.0, 8, null)), template)
            store.addLift(reviewPress, 3.0, listOf(Triple(100.0, 1, null)))
            val current = store.addLift(reviewPress, 0.0, listOf(Triple(82.5, 8, null), Triple(82.5, 8, null), Triple(82.5, 6, 5.0)), template)
            val engine = StatisticsEngine(store)
            val comparison = assertNotNull(engine.comparison(current))
            assertEquals(base.plusDays(-7.0), comparison.previousDate)
            assertTrue(comparison.hardSets == 2 && comparison.previousHardSets == 2)
            assertTrue(comparison.volumeKg == 82.5 * 22 && comparison.previousVolumeKg == 1280.0)
            assertNull(engine.comparison(store.addLift(reviewPress, 0.0, listOf(Triple(50.0, 5, null)))))
        }

        @Test
        fun `rezultat vjezbe - najbolja serija, procjena 1RM, promjena i odmor`() {
            val store = newStore()
            store.addLift(reviewPress, 7.0, listOf(Triple(80.0, 8, null)))
            val current = store.addLift(reviewPress, 0.0, listOf(Triple(85.0, 8, null), Triple(60.0, 20, null)), restSeconds = 150)
            val result = assertNotNull(StatisticsEngine(store).exerciseResults(current).firstOrNull())
            assertEquals(85.0, result.bestSet?.weightKg)
            assertTrue(abs((result.change ?: 0.0) - (85.0 / 80 - 1)) < 1e-9)
            assertEquals(150.0, result.restSeconds)
            assertEquals(2, result.hardSets)
        }

        @Test
        fun `odmor - medijan razmaka, bez dugih stanki`() {
            val times = listOf(0L, 90, 210, 330, 3000).map { base.plusSeconds(it) }
            assertEquals(120.0, SessionMetrics.medianRest(times))
            assertNull(SessionMetrics.medianRest(listOf(base)))
        }
    }

    @Nested
    inner class ExerciseHistoryTests {
        private inner class Done(val weight: Double, val reps: Int, val kind: SetKind = SetKind.WORKING, val completed: Boolean = true)

        private fun GymStore.add(
            at: Instant,
            name: String = "Trening",
            state: SessionState = SessionState.FINISHED,
            lifts: List<Pair<ExerciseRef, List<Done>>>,
            removed: Boolean = false,
        ): Session {
            val session = insert(Session(name, startedAt = at))
            session.state = state
            lifts.forEachIndexed { index, (ref, sets) ->
                val exercise = session.add(SessionExercise(index, ref, ExerciseInputType.WEIGHT_REPS))
                exercise.isRemoved = removed
                sets.forEachIndexed { setIndex, work ->
                    val set = exercise.add(SetLog(setIndex, work.kind))
                    set.weightKg = work.weight
                    set.reps = work.reps
                    set.completedAt = if (work.completed) at.plusSeconds(600) else null
                }
            }
            save()
            return session
        }

        @Test
        fun `izvodenja od najnovijeg, samo zavrsene radne serije iz zavrsenih treninga`() {
            val store = newStore()
            store.add(base, "Push A", lifts = listOf(bench to listOf(Done(40.0, 10, SetKind.WARM_UP), Done(80.0, 8), Done(80.0, 7, completed = false))))
            val later = store.add(
                base.plusDays(3.0), "Gornji dio",
                lifts = listOf(squat to listOf(Done(120.0, 5)), bench to listOf(Done(82.5, 6), Done(80.0, 7))),
            )
            // Ne broje se: aktivan trening, izbačena vježba, izvođenje samo sa zagrijavanjem.
            store.add(base.plusDays(5.0), state = SessionState.ACTIVE, lifts = listOf(bench to listOf(Done(90.0, 5))))
            store.add(base.plusDays(6.0), lifts = listOf(bench to listOf(Done(90.0, 5))), removed = true)
            store.add(base.plusDays(7.0), lifts = listOf(bench to listOf(Done(40.0, 10, SetKind.WARM_UP))))

            val history = StatisticsEngine(store).history(bench)
            assertEquals(2, history.count)
            assertEquals(listOf("Gornji dio", "Push A"), history.performances.map { it.sessionName })
            assertEquals(later.id, history.performances[0].sessionId)
            assertEquals(listOf(82.5, 80.0), history.performances[0].sets.map { it.weightKg })
            assertEquals(listOf(8), history.performances[1].sets.map { it.reps })
            assertTrue(StatisticsEngine(store).history(ExerciseRef.catalog("row", "Veslanje")).isEmpty)
        }

        @Test
        fun `rekord se oznaci tek nakon kalibracije i samo kad se rekordi prate`() {
            val store = newStore()
            for (index in 0 until 3) store.add(base.plusDays(index * 2.0), lifts = listOf(bench to listOf(Done(80.0, 5))))
            store.add(base.plusDays(6.0), lifts = listOf(bench to listOf(Done(90.0, 5))))

            val history = StatisticsEngine(store).history(bench)
            assertEquals(listOf(true, false, false, false), history.performances.map { it.hasRecord })
            val untracked = StatisticsEngine(store).history(bench, emptySet())
            assertTrue(untracked.performances.none { it.hasRecord })
        }

        private fun performance(type: ExerciseInputType, sets: List<SetValues>, date: Instant = base) =
            ExercisePerformance(UUID.randomUUID(), UUID.randomUUID(), "", date, type, sets, false)

        @Test
        fun `istaknute brojke ovise o vrsti unosa`() {
            val strength = ExerciseHistory(listOf(
                performance(ExerciseInputType.WEIGHT_REPS, listOf(SetValues(weightKg = 100.0, reps = 5), SetValues(weightKg = 90.0, reps = 8))),
            ))
            val heaviest = assertIs<ExerciseHistoryHighlight.Heaviest>(strength.highlights.first())
            val oneRepMax = assertIs<ExerciseHistoryHighlight.OneRepMax>(strength.highlights.last())
            assertEquals(100.0, heaviest.kg)
            assertTrue(abs(oneRepMax.kg - 116.6667) < 0.01)

            val bodyweight = ExerciseHistory(listOf(performance(ExerciseInputType.BODYWEIGHT, listOf(SetValues(reps = 12), SetValues(reps = 15)))))
            assertEquals(listOf(ExerciseHistoryHighlight.MostReps(15)), bodyweight.highlights)

            val cardio = ExerciseHistory(listOf(
                performance(ExerciseInputType.DURATION_DISTANCE, listOf(SetValues(durationSeconds = 1800, distanceMeters = 5000.0))),
            ))
            assertEquals(listOf(ExerciseHistoryHighlight.LongestDistance(5000.0), ExerciseHistoryHighlight.LongestDuration(1800)), cardio.highlights)
            assertTrue(ExerciseHistory(emptyList()).highlights.isEmpty())
        }

        @Test
        fun `izvodenja po mjesecima`() {
            val dates = listOf(base.plusDays(20.0), base.plusDays(1.0), base, base.plusDays(-20.0))
            val history = ExerciseHistory(dates.map { performance(ExerciseInputType.WEIGHT_REPS, emptyList(), it) })
            val months = history.byMonth(utcMonday)
            // 15. 1. 2027.: veljača, siječanj (dva), prosinac.
            assertEquals(listOf(1, 2, 1), months.map { it.performances.size })
            assertEquals(2, months[0].start.atZone(ZoneOffset.UTC).monthValue)
            assertEquals(12, months[2].start.atZone(ZoneOffset.UTC).monthValue)
        }

        @Test
        fun `tocka napretka - tezina i ponavljanja iz iste serije`() {
            val store = newStore()
            store.add(base, lifts = listOf(bench to listOf(Done(85.0, 5), Done(85.0, 4), Done(80.0, 7))))
            val point = assertNotNull(StatisticsEngine(store).progress(bench).firstOrNull())
            assertEquals(85.0, point.bestWeightKg)
            assertEquals(5, point.bestReps)
        }
    }

    @Nested
    inner class SessionCardioStatsTests {
        private val treadmill = ExerciseRef.catalog("treadmill", "Traka za trčanje")
        private val info: ExerciseInfoProvider = { key ->
            when (key) {
                "c:press" -> ExerciseInfo(listOf(Muscle.CHEST), primaryRegions = listOf("chest"))
                "c:treadmill", "c:bike" -> ExerciseInfo(listOf(Muscle.QUADRICEPS), primaryRegions = listOf("quads"), isCardio = true)
                else -> null
            }
        }
        private val isCardio = ExerciseInfoBuilder.isCardio(info)

        private fun GymStore.make(vararg entries: Pair<ExerciseRef, SetValues>, kind: WorkoutKind = WorkoutKind.STRENGTH): Session {
            val session = insert(Session("Trening", kind, base))
            session.state = SessionState.FINISHED
            session.endedAt = base.plusSeconds(3600)
            entries.forEachIndexed { index, (ref, values) ->
                val type = if (values.weightKg != null) ExerciseInputType.WEIGHT_REPS else ExerciseInputType.DURATION_DISTANCE
                val exercise = session.add(SessionExercise(index, ref, type))
                val set = exercise.add(SetLog(0))
                set.weightKg = values.weightKg
                set.reps = values.reps
                set.durationSeconds = values.durationSeconds
                set.distanceMeters = values.distanceMeters
                set.completedAt = base.plusSeconds(600)
            }
            save()
            return session
        }

        private val lift = reviewPress to SetValues(weightKg = 100.0, reps = 5)
        private val run = treadmill to SetValues(durationSeconds = 900, distanceMeters = 2500.0)

        @Test
        fun `mjesoviti trening je u filteru i pod snagom i pod kardiom`() {
            val store = newStore()
            val mixed = store.make(lift, run)
            val strength = store.make(lift)
            val kindsOf: (Session) -> Set<WorkoutKind> = { SessionCardio.mix(it, isCardio).kinds }
            val cardioOnly = HistoryFilter(setOf(WorkoutKind.CARDIO)).apply(listOf(mixed, strength), kindsOf)
            assertEquals(listOf(mixed.id), cardioOnly.map { it.id })
            val strengthOnly = HistoryFilter(setOf(WorkoutKind.STRENGTH)).apply(listOf(mixed, strength), kindsOf)
            assertEquals(setOf(mixed.id, strength.id), strengthOnly.map { it.id }.toSet())
        }

        @Test
        fun `kardio vjezbe se ne broje u serije po misicu`() {
            val store = newStore()
            val session = store.make(lift, run)
            assertEquals(listOf("chest"), SessionRegions.sets(session, info).map { it.region })

            val engine = StatisticsEngine(store)
            val week = engine.volumeBuckets(BucketSize.WEEK, 1, base, info = info)
            assertEquals(1, week.last().totalSets)
            assertNull(week.last().loads["quads"])
            val heatmap = engine.heatmap(base.minusSeconds(DAY), base.plusSeconds(DAY), info)
            assertNull(heatmap["quads"])
            assertEquals(1.0, heatmap["chest"]?.sets)
        }

        @Test
        fun `usporedba s proslim treningom - kardio nije serija, a vrijeme i udaljenost se usporeduju`() {
            val store = newStore()
            val template = UUID.randomUUID()
            val previous = store.make(treadmill to SetValues(durationSeconds = 1200, distanceMeters = 3000.0))
            previous.templateId = template
            previous.startedAt = base.plusDays(-7.0)
            previous.endedAt = previous.startedAt.plusSeconds(1800)
            val current = store.make(run)
            current.templateId = template
            store.save()

            val result = assertNotNull(StatisticsEngine(store).comparison(current, isCardio))
            assertTrue(result.hardSets == 0 && result.previousHardSets == 0)
            assertEquals(CardioPart(900, 2500.0), result.cardio)
            assertEquals(CardioPart(1200, 3000.0), result.previousCardio)
        }

        @Test
        fun `vlastita vjezba - kardio po odabranoj vrsti, a bez vrste po kategoriji`() {
            val byCategory = CustomExercise().apply { name = "Veslanje u parku"; category = ExerciseCategory.CARDIO }
            val byKind = CustomExercise().apply { name = "Penjanje uz stube"; category = ExerciseCategory.LEGS; kind = ExerciseKind.CARDIO }
            val strength = CustomExercise().apply { name = "Iskorak s ruksakom"; category = ExerciseCategory.LEGS }
            val provider = ExerciseInfoBuilder.provider(null, listOf(byCategory, byKind, strength))
            assertEquals(true, provider("u:${byCategory.id.uppercaseString}")?.isCardio)
            assertEquals(true, provider("u:${byKind.id.uppercaseString}")?.isCardio)
            assertEquals(false, provider("u:${strength.id.uppercaseString}")?.isCardio)
        }
    }
}
