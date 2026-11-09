package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.AccentChoice
import com.brunodobric.gymapp.model.AppTheme
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.UserSettings
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.Random
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun work(weight: Double, reps: Int) = SetValues(SetKind.WORKING, weightKg = weight, reps = reps)

private fun near(expected: Double, actual: Double?, tolerance: Double = 0.01) =
    assertTrue(actual != null && abs(actual - expected) < tolerance, "očekivano $expected, dobiveno $actual")

class MetricsTest {
    @Test
    fun `volumen po vrsti unosa`() {
        assertEquals(640.0, SetMetrics.volume(work(80.0, 8), ExerciseInputType.WEIGHT_REPS))
        assertEquals(0.0, SetMetrics.volume(SetValues(reps = 12), ExerciseInputType.BODYWEIGHT))
        assertEquals(80.0, SetMetrics.volume(SetValues(reps = 8, extraWeightKg = 10.0), ExerciseInputType.WEIGHTED_BODYWEIGHT))
        assertEquals(0.0, SetMetrics.volume(SetValues(reps = 8, extraWeightKg = 30.0), ExerciseInputType.ASSISTED))
        assertEquals(0.0, SetMetrics.volume(SetValues(durationSeconds = 60), ExerciseInputType.DURATION))
    }

    @Test
    fun `warm-up nikad ne ulazi u volumen`() {
        assertEquals(0.0, SetMetrics.volume(SetValues(SetKind.WARM_UP, 40.0, 10), ExerciseInputType.WEIGHT_REPS))
    }

    @Test
    fun `1RM po Epleyju i Brzyckom`() {
        assertEquals(100.0, SetMetrics.estimatedOneRepMax(100.0, 1))
        near(133.333, SetMetrics.estimatedOneRepMax(100.0, 10, formula = SetMetrics.OneRepMaxFormula.EPLEY))
        near(133.333, SetMetrics.estimatedOneRepMax(100.0, 10, formula = SetMetrics.OneRepMaxFormula.BRZYCKI))
        assertNull(SetMetrics.estimatedOneRepMax(100.0, 37, formula = SetMetrics.OneRepMaxFormula.BRZYCKI))
        assertNull(SetMetrics.estimatedOneRepMax(0.0, 5))
        assertNull(SetMetrics.estimatedOneRepMax(100.0, 0))
        near(133.333, SetMetrics.estimatedOneRepMax(100.0, 8, rir = 2.0))
    }

    @Test
    fun `pouzdana procjena - RIR iz RPE-a, do 12 ponavljanja do otkaza, samo radne serije s teretom`() {
        assertEquals(1.5, SetMetrics.repsInReserve(SetValues(reps = 5, rpe = 8.5)))
        assertEquals(0.0, SetMetrics.repsInReserve(SetValues(reps = 5)))
        assertNotNull(SetMetrics.strengthEstimate(work(100.0, 12), ExerciseInputType.WEIGHT_REPS))
        assertNull(SetMetrics.strengthEstimate(SetValues(weightKg = 100.0, reps = 10, rpe = 7.0), ExerciseInputType.WEIGHT_REPS))
        assertNull(SetMetrics.strengthEstimate(SetValues(SetKind.WARM_UP, 100.0, 5), ExerciseInputType.WEIGHT_REPS))
        assertNotNull(SetMetrics.strengthEstimate(SetValues(reps = 5, extraWeightKg = 20.0), ExerciseInputType.WEIGHTED_BODYWEIGHT))
        assertNull(SetMetrics.strengthEstimate(SetValues(reps = 5), ExerciseInputType.BODYWEIGHT))
    }

    @Test
    fun `što serija treba da bi se mogla označiti`() {
        assertTrue(SetMetrics.isComplete(work(80.0, 8), ExerciseInputType.WEIGHT_REPS))
        assertFalse(SetMetrics.isComplete(SetValues(reps = 8), ExerciseInputType.WEIGHT_REPS))
        assertFalse(SetMetrics.isComplete(work(80.0, 0), ExerciseInputType.WEIGHT_REPS))
        assertTrue(SetMetrics.isComplete(SetValues(reps = 8), ExerciseInputType.BODYWEIGHT))
        assertTrue(SetMetrics.isComplete(SetValues(durationSeconds = 30), ExerciseInputType.DURATION))
        assertFalse(SetMetrics.isComplete(SetValues(), ExerciseInputType.DURATION))
        assertTrue(SetMetrics.isComplete(SetValues(distanceMeters = 5000.0), ExerciseInputType.DURATION_DISTANCE))
    }

    @Test
    fun `tvrda serija je radna bez RPE-a ispod 6`() {
        assertTrue(SetMetrics.isHard(work(80.0, 8)))
        assertTrue(SetMetrics.isHard(SetValues(weightKg = 80.0, reps = 8, rpe = 6.0)))
        assertFalse(SetMetrics.isHard(SetValues(weightKg = 80.0, reps = 8, rpe = 5.5)))
        assertFalse(SetMetrics.isHard(SetValues(SetKind.WARM_UP, 40.0, 10)))
    }
}

class SmartDefaultsTest {
    private val previous = listOf(SetValues(SetKind.WARM_UP, 40.0, 10), work(80.0, 8), work(85.0, 8), work(90.0, 6))

    @Test
    fun `pozicija se računa zasebno za radne serije i warm-up`() {
        assertEquals(80.0, SmartDefaults.defaults(0, SetKind.WORKING, previous)?.weightKg)
        assertEquals(85.0, SmartDefaults.defaults(1, SetKind.WORKING, previous)?.weightKg)
        assertEquals(6, SmartDefaults.defaults(2, SetKind.WORKING, previous)?.reps)
        assertEquals(40.0, SmartDefaults.defaults(0, SetKind.WARM_UP, previous)?.weightKg)
        assertEquals(40.0, SmartDefaults.defaults(1, SetKind.WARM_UP, previous)?.weightKg)
    }

    @Test
    fun `više serija nego prošli put koristi zadnju prošlu seriju`() {
        assertEquals(90.0, SmartDefaults.defaults(5, SetKind.WORKING, previous)?.weightKg)
    }

    @Test
    fun `bez povijesti nema zadanih vrijednosti, a RPE se ne prenosi`() {
        assertNull(SmartDefaults.defaults(0, SetKind.WORKING, emptyList()))
        assertNull(SmartDefaults.defaults(0, SetKind.WARM_UP, listOf(work(80.0, 8))))
        assertNull(SmartDefaults.defaults(0, SetKind.WORKING, listOf(SetValues(weightKg = 80.0, reps = 8, rpe = 9.0)))?.rpe)
    }
}

class PersonalRecordTest {
    private fun kinds(records: List<PersonalRecord>) = records.map { it.kind }.toSet()

    /** Povijest s dovoljno izvođenja za rekorde: prvo izvođenje ponovljeno do kalibracije. */
    private fun past(sessions: List<List<SetValues>>, type: ExerciseInputType = ExerciseInputType.WEIGHT_REPS): RecordHistory {
        val padding = List(maxOf(0, RecordHistory.CALIBRATION_SESSIONS - sessions.size)) { sessions[0] }
        return RecordHistory(padding + sessions, type)
    }

    private fun records(
        current: List<SetValues>,
        sessions: List<List<SetValues>>,
        type: ExerciseInputType = ExerciseInputType.WEIGHT_REPS,
    ) = PersonalRecordDetector.records(current, past(sessions, type), type)

    private fun List<PersonalRecord>.of(kind: PRKind) = firstOrNull { it.kind == kind }

    @Test
    fun `bez povijesti i u prva tri izvođenja nema rekorda`() {
        val type = ExerciseInputType.WEIGHT_REPS
        assertTrue(PersonalRecordDetector.records(listOf(work(100.0, 5)), RecordHistory(), type).isEmpty())
        val two = RecordHistory(List(2) { listOf(work(80.0, 5)) }, type)
        assertTrue(PersonalRecordDetector.records(listOf(work(100.0, 5)), two, type).isEmpty())
        val three = RecordHistory(List(3) { listOf(work(80.0, 5)) }, type)
        assertTrue(PersonalRecordDetector.records(listOf(work(100.0, 5)), three, type).isNotEmpty())
    }

    @Test
    fun `procjena 1RM je glavni rekord, s pragom od 1 posto`() {
        val record = records(listOf(work(185.0, 5)), listOf(listOf(work(180.0, 5)))).of(PRKind.ESTIMATED_ONE_REP_MAX)
        near(215.833, record?.value)
        near(210.0, record?.previousBest)
        assertTrue(records(listOf(work(140.5, 5)), listOf(listOf(work(140.0, 5)))).isEmpty())
    }

    @Test
    fun `RIR iz RPE-a ulazi u procjenu, a serije iznad 12 ponavljanja do otkaza ne`() {
        val found = records(listOf(SetValues(weightKg = 100.0, reps = 8, rpe = 8.0)), listOf(listOf(work(100.0, 8))))
        near(133.333, found.of(PRKind.ESTIMATED_ONE_REP_MAX)?.value)
        assertFalse(PRKind.ESTIMATED_ONE_REP_MAX in kinds(records(listOf(work(60.0, 20)), listOf(listOf(work(100.0, 5))))))
    }

    @Test
    fun `rekord po rasponu ponavljanja - jedan, najviši nadmašeni raspon`() {
        val history = listOf(listOf(work(100.0, 5), work(80.0, 10)))
        val five = records(listOf(work(102.5, 5)), history)
        assertEquals(PersonalRecord(PRKind.REP_MAX, 102.5, 100.0, reps = 5), five.of(PRKind.REP_MAX))
        assertEquals(1, five.count { it.kind == PRKind.REP_MAX })
        assertEquals(10, records(listOf(work(85.0, 10)), history).of(PRKind.REP_MAX)?.reps)
    }

    @Test
    fun `najveća težina ide u sažetak samo uz blizu najbolju procjenu 1RM`() {
        assertEquals(true, records(listOf(work(185.0, 4)), listOf(listOf(work(180.0, 5)))).of(PRKind.MAX_WEIGHT)?.showsInSummary)
        val far = records(listOf(work(190.0, 1)), listOf(listOf(work(180.0, 5)))).of(PRKind.MAX_WEIGHT)
        assertEquals(190.0, far?.value)
        assertEquals(false, far?.showsInSummary)
    }

    @Test
    fun `tonaža vježbe je rekord treninga, ali ne ide u sažetak`() {
        val record = records(List(3) { work(80.0, 8) }, listOf(List(2) { work(80.0, 8) })).of(PRKind.EXERCISE_VOLUME)
        assertEquals(PersonalRecord(PRKind.EXERCISE_VOLUME, 1920.0, 1280.0, showsInSummary = false), record)
    }

    @Test
    fun `warm-up serije ne mogu biti rekord`() {
        val warmUp = SetValues(SetKind.WARM_UP, 200.0, 20)
        assertTrue(records(listOf(warmUp), listOf(listOf(work(80.0, 5)))).isEmpty())
        assertEquals(85.0, records(listOf(work(85.0, 5)), listOf(listOf(warmUp, work(80.0, 5)))).of(PRKind.MAX_WEIGHT)?.value)
    }

    @Test
    fun `vlastita težina - samo ponavljanja`() {
        assertEquals(setOf(PRKind.MAX_REPS), kinds(records(listOf(SetValues(reps = 15)), listOf(listOf(SetValues(reps = 12))), ExerciseInputType.BODYWEIGHT)))
    }

    @Test
    fun `potpomognuta - rekord je manja pomoć`() {
        val type = ExerciseInputType.ASSISTED
        val history = listOf(listOf(SetValues(reps = 8, extraWeightKg = 30.0)))
        assertEquals(25.0, records(listOf(SetValues(reps = 8, extraWeightKg = 25.0)), history, type).of(PRKind.LOWEST_ASSISTANCE)?.value)
        assertFalse(PRKind.LOWEST_ASSISTANCE in kinds(records(listOf(SetValues(reps = 8, extraWeightKg = 35.0)), history, type)))
        assertEquals(10.0, records(listOf(SetValues(reps = 10, extraWeightKg = 30.0)), history, type).of(PRKind.MAX_REPS)?.value)
    }

    @Test
    fun `trajanje i udaljenost - najdulje`() {
        assertEquals(
            setOf(PRKind.LONGEST_DURATION),
            kinds(records(listOf(SetValues(durationSeconds = 90)), listOf(listOf(SetValues(durationSeconds = 60))), ExerciseInputType.DURATION)),
        )
        val cardio = records(
            listOf(SetValues(durationSeconds = 1800, distanceMeters = 6000.0)),
            listOf(listOf(SetValues(durationSeconds = 1800, distanceMeters = 5000.0))),
            ExerciseInputType.DURATION_DISTANCE,
        )
        assertEquals(setOf(PRKind.LONGEST_DISTANCE), kinds(cardio))
    }

    @Test
    fun `nakon pauze od 6 tjedana prva dva izvođenja nemaju rekorda`() {
        val day = 86_400L
        val start = Instant.ofEpochSecond(1_800_000_000)
        val type = ExerciseInputType.WEIGHT_REPS
        val history = RecordHistory()
        repeat(4) { history.add(listOf(work(80.0, 5)), type, start.plusSeconds(it * 7 * day)) }
        val back = start.plusSeconds(3 * 7 * day + 50 * day)
        assertFalse(history.allowsRecords(back))
        history.add(listOf(work(70.0, 5)), type, back)
        assertFalse(history.allowsRecords(back.plusSeconds(3 * day)))
        history.add(listOf(work(75.0, 5)), type, back.plusSeconds(3 * day))
        assertTrue(history.allowsRecords(back.plusSeconds(6 * day)))
    }

    @Test
    fun `isključeni tipovi se ne prijavljuju`() {
        val result = PersonalRecordDetector.records(
            listOf(work(90.0, 5), work(90.0, 5)), past(listOf(listOf(work(80.0, 5)))), ExerciseInputType.WEIGHT_REPS,
            kinds = PRKind.kindsFromSettings(listOf("maxVolume")),
        )
        assertEquals(setOf(PRKind.EXERCISE_VOLUME), kinds(result))
        assertTrue(PRKind.kindsFromSettings(emptyList()).isEmpty())
    }

    @Test
    fun `rekordi isključeni u postavkama ne prate ništa`() {
        val settings = UserSettings()
        assertEquals(PRKind.kindsFromSettings(listOf("maxWeight", "maxVolume", "maxReps")), PRKind.tracked(settings))
        settings.trackedPRKinds = listOf("maxVolume")
        assertEquals(setOf(PRKind.EXERCISE_VOLUME), PRKind.tracked(settings))
        settings.prEnabled = false
        assertTrue(PRKind.tracked(settings).isEmpty())
        assertEquals(PRKind.entries.toSet(), PRKind.tracked(null))
    }

    @Test
    fun `tema i boja imaju zadane vrijednosti i ignoriraju nepoznate`() {
        val settings = UserSettings()
        assertEquals(AppTheme.SYSTEM, settings.theme)
        assertEquals(AccentChoice.BLUE, settings.accent)
        settings.theme = AppTheme.DARK
        settings.accent = AccentChoice.TEAL
        assertEquals("dark", settings.themeRaw)
        assertEquals("teal", settings.accentColorRaw)
        settings.themeRaw = "nepoznato"
        settings.accentColorRaw = "nepoznato"
        assertEquals(AppTheme.SYSTEM, settings.theme)
        assertEquals(AccentChoice.BLUE, settings.accent)
    }

    @Test
    fun `boje koje su izašle iz ponude čitaju se kao zadana Apolon plava`() {
        val settings = UserSettings()
        for (removed in listOf("green", "orange", "red")) {
            settings.accentColorRaw = removed
            settings.liveActivityAccentRaw = removed
            assertEquals(AccentChoice.BLUE, settings.accent)
            assertEquals(AccentChoice.BLUE, settings.liveActivityAccent)
        }
        assertEquals(
            listOf(AccentChoice.BLUE, AccentChoice.INDIGO, AccentChoice.PURPLE, AccentChoice.PINK, AccentChoice.TEAL, AccentChoice.GRAPHITE),
            AccentChoice.entries,
        )
    }
}

class RestTest {
    private val start = Instant.ofEpochSecond(1_800_000_000)

    @Test
    fun `preostalo vrijeme i istek`() {
        val timer = RestTimer(start, 90)
        assertEquals(60.0, timer.remaining(start.plusSeconds(30)))
        assertFalse(timer.isExpired(start.plusSeconds(89)))
        assertTrue(timer.isExpired(start.plusSeconds(90)))
        assertEquals(0.0, timer.remaining(start.plusSeconds(500)))
        assertEquals(0.5, timer.progress(start.plusSeconds(45)))
    }

    @Test
    fun `plus i minus 10 sekundi, bez skraćivanja ispod trenutka pritiska`() {
        val timer = RestTimer(start, 90)
        val now = start.plusSeconds(20)
        assertEquals(80.0, timer.adjusted(10, now).remaining(now))
        assertEquals(60.0, timer.adjusted(-10, now).remaining(now))
        assertEquals(0.0, timer.adjusted(-500, now).remaining(now))
    }

    @Test
    fun `timer spremljen kao trenutak završetka ispravno se nastavlja nakon oporavka`() {
        val timer = RestTimer(start, 120)
        val restored = RestTimer(timer.startedAt, timer.endsAt)
        assertEquals(20.0, restored.remaining(start.plusSeconds(100)))
        assertTrue(restored.isExpired(start.plusSeconds(3600)))
    }

    @Test
    fun `pauza u supersetu - 0 osim nakon zadnje vježbe`() {
        assertEquals(0, RestPolicy.seconds(0, 2, null, 90))
        assertEquals(90, RestPolicy.seconds(1, 2, null, 90))
        assertEquals(0, RestPolicy.seconds(0, 3, 60, 120))
        assertEquals(120, RestPolicy.seconds(2, 3, null, 120))
        assertEquals(45, RestPolicy.seconds(0, 1, 45, 90))
        assertEquals(90, RestPolicy.seconds(0, 1, null, 90))
    }

    @Test
    fun `zadana pauza prema vrsti vježbe`() {
        val defaults = RestDefaults(150, 90)
        assertEquals(150, defaults.seconds(listOf(true)))
        assertEquals(90, defaults.seconds(listOf(false)))
        assertEquals(90, defaults.seconds(listOf(null)))
        assertEquals(150, defaults.seconds(listOf(false, true)))
        assertEquals(90, defaults.seconds(listOf(false, null)))
        assertEquals(120, RestDefaults.uniform(120).seconds(listOf(true)))
        assertEquals(RestDefaults(150, 90), RestDefaults.STANDARD)
    }

    @Test
    fun `postavke daju zadane pauze`() {
        val settings = UserSettings()
        assertEquals(RestDefaults.STANDARD, settings.restDefaults)
        settings.compoundRestSeconds = 180
        settings.defaultRestSeconds = 60
        assertEquals(RestDefaults(180, 60), settings.restDefaults)
    }

    @Test
    fun `naizmjenični redoslijed superseta`() {
        assertEquals(
            listOf(SetPosition(0, 0), SetPosition(1, 0), SetPosition(0, 1), SetPosition(1, 1), SetPosition(0, 2)),
            SupersetSequence.order(listOf(3, 2)),
        )
        val completed = listOf(SetPosition(0, 0), SetPosition(1, 0))
        assertEquals(SetPosition(0, 1), SupersetSequence.nextIncomplete(listOf(3, 2)) { it in completed })
        assertNull(SupersetSequence.nextIncomplete(listOf(1, 1)) { true })
    }

    @Test
    fun `prva nekompletirana vježba`() {
        assertEquals(1, WorkoutFlow.firstIncompleteExercise(listOf(true, false, false)))
        assertNull(WorkoutFlow.firstIncompleteExercise(listOf(true, true)))
    }

    @Test
    fun `nakon zadnje serije vježbe otvara se sljedeća`() {
        assertEquals(WorkoutFlow.Advance.Stay, WorkoutFlow.advance(false, listOf(false, false)))
        assertEquals(WorkoutFlow.Advance.Open(1), WorkoutFlow.advance(true, listOf(true, false, false)))
        assertEquals(WorkoutFlow.Advance.Open(0), WorkoutFlow.advance(true, listOf(false, true, false)))
        assertEquals(WorkoutFlow.Advance.Finished, WorkoutFlow.advance(true, listOf(true, true)))
    }

    @Test
    fun `nova završena serija od zadnjeg pogleda`() {
        assertTrue(WorkoutFlow.hasNewCompletion(4, 3))
        assertFalse(WorkoutFlow.hasNewCompletion(3, 3))
        assertFalse(WorkoutFlow.hasNewCompletion(2, 3))
    }

    @Test
    fun `zaboravljeni trening nakon 6 sati bez aktivnosti`() {
        val lastSet = start.plusSeconds(600)
        assertFalse(RecoveryAssessment.assess(start, lastSet, lastSet, lastSet.plusSeconds(3600)).isStale)
        val stale = RecoveryAssessment.assess(start, lastSet, lastSet, lastSet.plusSeconds(7 * 3600))
        assertTrue(stale.isStale)
        assertEquals(lastSet, stale.suggestedEnd)
        assertEquals(start, RecoveryAssessment.assess(start, start, null, start).suggestedEnd)
    }
}

class PlateTest {
    private val plates = listOf(1.25, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0)

    @Test
    fun `100 kg na šipki od 20 kg`() {
        val result = PlateCalculator.calculate(100.0, 20.0, plates)
        assertEquals(listOf(25.0, 15.0), result.perSide)
        assertTrue(result.isExact)
        assertEquals(100.0, result.achievedTotal)
    }

    @Test
    fun `decimalne ploče`() {
        val result = PlateCalculator.calculate(62.5, 20.0, plates)
        assertEquals(listOf(20.0, 1.25), result.perSide)
        assertTrue(result.isExact)
    }

    @Test
    fun `težina koja se ne može složiti daje najbližu manju`() {
        val result = PlateCalculator.calculate(61.0, 20.0, plates)
        assertFalse(result.isExact)
        assertEquals(60.0, result.achievedTotal)
        assertTrue(abs(result.shortfall - 1) < 1e-9)
    }

    @Test
    fun `manje od šipke i sama šipka`() {
        assertTrue(PlateCalculator.calculate(15.0, 20.0, plates).isBelowBar)
        val bar = PlateCalculator.calculate(20.0, 20.0, plates)
        assertTrue(bar.perSide.isEmpty())
        assertTrue(bar.isExact)
        assertTrue(PlateCalculator.calculate(100.0, 20.0, emptyList()).perSide.isEmpty())
    }

    @Test
    fun `nestandardan skup ploča - najmanji broj ploča, ne pohlepni izbor`() {
        val result = PlateCalculator.calculate(32.0, 20.0, listOf(4.0, 3.0))
        assertEquals(listOf(3.0, 3.0), result.perSide)
        assertTrue(result.isExact)
    }

    @Test
    fun funte() {
        val result = PlateCalculator.calculate(225.0, 45.0, listOf(45.0, 35.0, 25.0, 10.0, 5.0, 2.5))
        assertEquals(listOf(45.0, 45.0), result.perSide)
        assertTrue(result.isExact)
    }

    @Test
    fun `iste ploče se zbrajaju po veličini`() {
        assertEquals(
            listOf(PlateCalculator.PlateCount(20.0, 2), PlateCalculator.PlateCount(5.0, 1), PlateCalculator.PlateCount(1.25, 2)),
            PlateCalculator.grouped(listOf(20.0, 20.0, 5.0, 1.25, 1.25)),
        )
        assertTrue(PlateCalculator.grouped(emptyList()).isEmpty())
    }

    @Test
    fun `uključivanje i isključivanje ploča`() {
        assertEquals(listOf(1.25, 5.0, 10.0, 20.0), PlateCalculator.setting(5.0, true, listOf(20.0, 1.25, 10.0)))
        assertEquals(listOf(10.0, 20.0), PlateCalculator.setting(10.0, true, listOf(10.0, 20.0)))
        assertEquals(listOf(1.25, 20.0), PlateCalculator.setting(10.0, false, listOf(1.25, 10.0, 20.0)))
        assertEquals(listOf(10.0), PlateCalculator.setting(0.5, false, listOf(10.0)))
    }
}

class CondensedHistoryTest {
    private fun randomSet(random: Random) = SetValues(
        kind = if (random.nextInt(8) == 0) SetKind.WARM_UP else SetKind.WORKING,
        weightKg = random.nextInt(21) * 2.5,
        reps = random.nextInt(16),
        extraWeightKg = random.nextInt(13) * 2.5,
        durationSeconds = random.nextInt(601),
        distanceMeters = random.nextInt(51) * 100.0,
        rpe = if (random.nextInt(3) == 0) null else (12 + random.nextInt(9)) / 2.0,
    )

    @Test
    fun `sa sažetom poviješću rekordi su isti kao s punom, za svaku vrstu unosa`() {
        val random = Random(14)
        for (type in ExerciseInputType.entries) {
            val all = mutableListOf<SetValues>()
            var bestVolume = 0.0
            var sessions = 0
            val condensed = RecordHistory()
            repeat(120) {
                val current = List(1 + random.nextInt(5)) { randomSet(random) }
                val full = RecordHistory(all.toList(), bestVolume, sessions)
                assertEquals(
                    PersonalRecordDetector.records(current, full, type),
                    PersonalRecordDetector.records(current, condensed, type),
                    type.name,
                )
                val working = current.filter { it.kind == SetKind.WORKING }
                if (working.isNotEmpty()) {
                    all += working
                    sessions++
                    bestVolume = maxOf(bestVolume, working.sumOf { SetMetrics.volume(it, type) })
                }
                condensed.add(current, type, null)
            }
        }
    }

    @Test
    fun `sažeta povijest ostaje mala`() {
        val random = Random(7)
        val history = RecordHistory()
        repeat(500) { history.add(List(4) { randomSet(random) }, ExerciseInputType.WEIGHT_REPS, null) }
        assertTrue(history.sets.size < 120)
        assertTrue(PersonalRecordDetector.condensed(emptyList()).isEmpty())
        assertTrue(PersonalRecordDetector.condensed(listOf(SetValues(SetKind.WARM_UP, 20.0, 10))).isEmpty())
    }
}
