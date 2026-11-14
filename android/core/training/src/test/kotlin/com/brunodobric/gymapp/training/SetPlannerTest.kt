package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.units.WeightUnit
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private val WR = ExerciseInputType.WEIGHT_REPS
private val W = SetKind.WORKING
private val bench = ExerciseRef.catalog("bench", "Potisak s klupe")
private val press = ExerciseRef.catalog("press", "Potisak bučicama")
private val base = Instant.ofEpochSecond(1_800_000_000)

private fun working(weight: Double?, reps: Int?) = SetValues(W, weightKg = weight, reps = reps)
private fun range(count: Int, lower: Int, upper: Int) = List(count) { SetTarget(W, reps = lower, repsMax = upper) }

class SetPlannerTest {

    @Test
    fun `raspon ponavljanja zadržava prošla ponavljanja unutar granica`() {
        val previous = listOf(working(80.0, 10), working(80.0, 13), working(80.0, 6))
        val plan = SetPlanner.plan(previous, targets = range(3, 8, 12), inputType = WR, weightStep = 2.5)
        assertEquals(listOf(10, 12, 8), plan.sets.map { it.reps })
        assertEquals(listOf(80.0, 80.0, 80.0), plan.sets.map { it.weightKg })
        assertNull(plan.loadChangeKg)
        assertEquals(RepRange(8, 12), plan.repRange)
    }

    @Test
    fun `bez povijesti raspon počinje od donje granice`() {
        val plan = SetPlanner.plan(emptyList(), targets = range(3, 8, 12), inputType = WR, weightStep = 2.5)
        assertEquals(listOf(8, 8, 8), plan.sets.map { it.reps })
        assertNull(plan.loadChangeKg)
    }

    @Test
    fun `gornja granica u svim serijama podiže težinu za korak i vraća ponavljanja na donju granicu`() {
        val previous = listOf(working(80.0, 12), working(80.0, 12), working(77.5, 13))
        val plan = SetPlanner.plan(previous, targets = range(3, 8, 12), inputType = WR, weightStep = 2.5)
        assertEquals(listOf(82.5, 82.5, 80.0), plan.sets.map { it.weightKg })
        assertEquals(listOf(8, 8, 8), plan.sets.map { it.reps })
        assertEquals(2.5, plan.loadChangeKg)
    }

    @Test
    fun `jedna serija ispod gornje granice ne podiže težinu`() {
        val previous = listOf(working(80.0, 12), working(80.0, 11), working(80.0, 12))
        assertFalse(SetPlanner.shouldIncreaseLoad(range(3, 8, 12), previous, WR))
        // Manje serija nego u planu: nisu odrađene sve.
        assertFalse(SetPlanner.shouldIncreaseLoad(range(3, 8, 12), previous.take(2), WR))
    }

    @Test
    fun `težina iz predloška ne nadjačava prošli put i ne isključuje prijedlog`() {
        val previous = listOf(working(80.0, 12))
        val targets = listOf(SetTarget(W, weightKg = 80.0, reps = 8, repsMax = 12))
        val plan = SetPlanner.plan(previous, targets = targets, inputType = WR, weightStep = 2.5)
        assertEquals(82.5, plan.sets[0].weightKg)
        assertEquals(2.5, plan.loadChangeKg)
    }

    @Test
    fun `svaka serija dobiva težinu prošlog puta, a ne staru težinu iz predloška`() {
        val previous = listOf(working(60.0, 12), working(70.0, 10), working(70.0, 10))
        val targets = listOf(
            SetTarget(W, weightKg = 60.0, reps = 10),
            SetTarget(W, weightKg = 60.0, reps = 10),
            SetTarget(W, weightKg = 70.0, reps = 10),
        )
        val plan = SetPlanner.plan(previous, targets = targets, inputType = WR)
        assertEquals(listOf(60.0, 70.0, 70.0), plan.sets.map { it.weightKg })
        assertEquals(listOf(10, 10, 10), plan.sets.map { it.reps })
    }

    @Test
    fun `bez povijesti vrijedi težina iz predloška`() {
        val targets = listOf(SetTarget(W, weightKg = 60.0, reps = 10), SetTarget(W, weightKg = 70.0, reps = 10))
        val plan = SetPlanner.plan(emptyList(), targets = targets, inputType = WR, weightStep = 2.5)
        assertEquals(listOf(60.0, 70.0), plan.sets.map { it.weightKg })
        assertNull(plan.loadChangeKg)
    }

    @Test
    fun `fiksni cilj radi kao raspon s istim granicama`() {
        val previous = List(5) { working(100.0, 5) }
        val plan = SetPlanner.plan(previous, targets = List(5) { SetTarget(W, reps = 5) }, inputType = WR, weightStep = 2.5)
        assertEquals(102.5, plan.sets[0].weightKg)
        assertEquals(RepRange(5, 5), plan.repRange)
    }

    @Test
    fun `korak je u jedinici prikaza i težina izvan koraka ide na sljedeću`() {
        assertEquals(85.0, SetPlanner.stepped(83.0, 1, 2.5, WeightUnit.KILOGRAMS))
        assertEquals(82.5, SetPlanner.stepped(83.0, -1, 2.5, WeightUnit.KILOGRAMS))
        val pounds = SetPlanner.stepped(WeightConversionTestValues.LBS_100_IN_KG, 1, 5.0, WeightUnit.POUNDS)
        assertEquals(105.0 * 0.45359237, pounds, 1e-9)
    }

    @Test
    fun `potpomognuta vježba smanjuje pomoć, a dodatni teret raste i od nule`() {
        val assisted = SetPlanner.plan(
            listOf(SetValues(W, extraWeightKg = 20.0, reps = 10)), targets = range(1, 6, 10),
            inputType = ExerciseInputType.ASSISTED, weightStep = 5.0,
        )
        assertEquals(15.0, assisted.sets[0].extraWeightKg)
        assertEquals(-5.0, assisted.loadChangeKg)

        val weighted = SetPlanner.plan(
            listOf(SetValues(W, reps = 10)), targets = range(1, 6, 10),
            inputType = ExerciseInputType.WEIGHTED_BODYWEIGHT, weightStep = 2.5,
        )
        assertEquals(2.5, weighted.sets[0].extraWeightKg)
        assertEquals(6, weighted.sets[0].reps)
    }

    @Test
    fun `vlastita težina i bez koraka nema prijedloga težine`() {
        val bodyweight = SetPlanner.plan(
            listOf(SetValues(W, reps = 15)), targets = range(1, 8, 12),
            inputType = ExerciseInputType.BODYWEIGHT, weightStep = 2.5,
        )
        assertEquals(12, bodyweight.sets[0].reps)
        assertNull(bodyweight.loadChangeKg)
        assertNull(SetPlanner.plan(listOf(working(80.0, 12)), targets = range(1, 8, 12), inputType = WR).loadChangeKg)
    }

    @Test
    fun `zagrijavanje - prazna šipka, 40, 60 i 80 posto zaokruženo na korak, bez ponavljanja težine`() {
        val sets = WarmUpGenerator.sets(100.0, 20.0, 2.5, WeightUnit.KILOGRAMS)
        assertEquals(listOf(20.0, 40.0, 60.0, 80.0), sets.map { it.weightKg })
        assertEquals(listOf(10, 5, 3, 1), sets.map { it.reps })
        assertTrue(sets.all { it.kind == SetKind.WARM_UP })
        assertEquals(listOf(20.0, 25.0), WarmUpGenerator.sets(30.0, 20.0, 5.0, WeightUnit.KILOGRAMS).map { it.weightKg })
        assertEquals(listOf(12.0, 18.0, 24.0), WarmUpGenerator.sets(30.0, null, 2.0, WeightUnit.KILOGRAMS).map { it.weightKg })
        assertTrue(WarmUpGenerator.sets(0.0, 20.0, 2.5, WeightUnit.KILOGRAMS).isEmpty())
    }

    @Test
    fun `oznaka rekorda dok trening traje - samo serija koja sama obara rekord`() {
        val history = RecordHistory(List(3) { listOf(working(100.0, 5)) }, WR)
        val strong = UUID.randomUUID()
        val same = UUID.randomUUID()
        val warmUp = UUID.randomUUID()
        val all = PRKind.entries.toSet()
        val marked = PersonalRecordDetector.liveRecordSets(
            listOf(strong to working(110.0, 5), same to working(100.0, 5), warmUp to SetValues(SetKind.WARM_UP, weightKg = 120.0, reps = 5)),
            history, WR, all,
        )
        assertEquals(setOf(strong), marked)
        val young = RecordHistory(listOf(listOf(working(100.0, 5))), WR)
        assertTrue(PersonalRecordDetector.liveRecordSets(listOf(strong to working(110.0, 5)), young, WR, all).isEmpty())
        assertTrue(PersonalRecordDetector.liveRecordSets(listOf(strong to working(110.0, 5)), history, WR, emptySet()).isEmpty())
    }

    @Test
    fun `broj radnih serija je najčešći iz zadnjih izvođenja`() {
        assertEquals(4, SmartDefaults.workingSetCount(listOf(2, 4, 4)))
        assertEquals(2, SmartDefaults.workingSetCount(listOf(2, 4)))
        assertNull(SmartDefaults.workingSetCount(emptyList()))
        val plan = SetPlanner.plan(listOf(working(60.0, 8), working(60.0, 8)), listOf(2, 4, 4), inputType = WR)
        assertEquals(4, plan.sets.size)
        assertEquals(listOf(60.0, 60.0, 60.0, 60.0), plan.sets.map { it.weightKg })
    }
}

private object WeightConversionTestValues {
    const val LBS_100_IN_KG = 100 * 0.45359237
}

class SetPlannerEngineTest {
    private val store = GymStore(InMemoryPersistence())
    private val engine = WorkoutEngine(store)

    private fun finished(start: Instant, sets: List<Pair<Double, Int>>, templateId: UUID? = null, ref: ExerciseRef = bench) {
        val session = engine.startSession("Trening", templateId = templateId, now = start)
        val exercise = engine.addExercise(ref, WR, session, now = start)
        exercise.orderedSets.forEach { engine.removeSet(it, start) }
        for ((weight, reps) in sets) {
            val set = engine.addSet(exercise, now = start)
            set.weightKg = weight
            set.reps = reps
            engine.completeSet(set, 90, start.plusSeconds(60))
        }
        engine.finishSession(session, now = start.plusSeconds(3600))
    }

    @Test
    fun `prošli put dolazi iz istog treninga kad postoji`() {
        val heavy = UUID.randomUUID()
        val light = UUID.randomUUID()
        finished(base, listOf(140.0 to 5), heavy)
        finished(base.plusSeconds(86_400), listOf(100.0 to 12), light)

        assertEquals(listOf(140.0), store.previousSetValues(bench, heavy).map { it.weightKg })
        assertEquals(listOf(100.0), store.previousSetValues(bench).map { it.weightKg })
        val session = engine.startSession("Teško", templateId = heavy, now = base.plusSeconds(2 * 86_400))
        val exercise = engine.addExercise(bench, WR, session, now = base.plusSeconds(2 * 86_400))
        assertEquals(140.0, exercise.orderedSets.first().weightKg)
    }

    @Test
    fun `jedan prekinut trening ne smanjuje broj serija`() {
        finished(base, List(4) { 60.0 to 8 })
        finished(base.plusSeconds(86_400), List(4) { 60.0 to 8 })
        finished(base.plusSeconds(2 * 86_400), List(2) { 62.5 to 8 })
        val session = engine.startSession("Novi", now = base.plusSeconds(3 * 86_400))
        val exercise = engine.addExercise(bench, WR, session, now = base.plusSeconds(3 * 86_400))
        assertEquals(4, exercise.orderedSets.size)
        assertEquals(62.5, exercise.orderedSets.first().weightKg)
    }

    @Test
    fun `zamjena bez završenih serija mijenja vježbu na istom mjestu`() {
        finished(base, listOf(30.0 to 10, 30.0 to 10), ref = press)
        val session = engine.startSession("Push", now = base.plusSeconds(86_400))
        val first = engine.addExercise(bench, WR, session)
        val second = engine.addExercise(ExerciseRef.catalog("fly", "Razvlačenje"), WR, session)
        first.supersetGroupId = UUID.randomUUID()

        val created = engine.replaceExercise(first, press, WR)
        val visible = engine.visibleExercises(session)
        assertEquals(listOf(press.key, second.exerciseKey), visible.map { it.exerciseKey })
        assertEquals(3, created.orderedSets.size)
        assertEquals(30.0, created.orderedSets.first().weightKg)
        assertEquals(first.supersetGroupId, created.supersetGroupId)
        assertTrue(session.exercises.none { it === first })
    }

    @Test
    fun `zamjena nakon završenih serija ostavlja odrađeno i dodaje preostale serije iza`() {
        val session = engine.startSession("Push", now = base)
        val first = engine.addExercise(bench, WR, session)
        engine.addExercise(ExerciseRef.catalog("fly", "Razvlačenje"), WR, session)
        val done = first.orderedSets.first()
        done.weightKg = 80.0
        done.reps = 8
        engine.completeSet(done, 90, base)

        val created = engine.replaceExercise(first, press, WR)
        val visible = engine.visibleExercises(session)
        assertEquals(listOf(bench.key, press.key, "c:fly"), visible.map { it.exerciseKey })
        assertEquals(1, first.orderedSets.size)
        assertTrue(first.orderedSets.all { it.isCompleted })
        assertEquals(2, created.orderedSets.size)
    }

    @Test
    fun `dodaj zagrijavanje stavlja serije ispred radnih, samo jednom`() {
        val session = engine.startSession("Push", now = base)
        val exercise = engine.addExercise(bench, WR, session)
        assertFalse(engine.canAddWarmUps(exercise))
        exercise.orderedSets.forEach {
            it.weightKg = 100.0
            it.reps = 5
        }
        assertEquals(4, engine.addWarmUps(exercise, 20.0, 2.5, WeightUnit.KILOGRAMS))
        assertEquals(List(4) { SetKind.WARM_UP } + List(3) { W }, exercise.orderedSets.map { it.kind })
        assertEquals((0 until 7).toList(), exercise.orderedSets.map { it.orderIndex })
        assertFalse(engine.canAddWarmUps(exercise))
        assertEquals(0, engine.addWarmUps(exercise, 20.0, 2.5, WeightUnit.KILOGRAMS))
    }

    @Test
    fun `nakon zagrijavanja odmor je kraći - 60 s, a pred radnu seriju pola pune pauze`() {
        assertEquals(60, RestPolicy.afterWarmUp(150, nextIsWarmUp = true))
        assertEquals(75, RestPolicy.afterWarmUp(150, nextIsWarmUp = false))
        assertEquals(60, RestPolicy.afterWarmUp(90, nextIsWarmUp = false))
        assertEquals(45, RestPolicy.afterWarmUp(45, nextIsWarmUp = true))
        assertEquals(0, RestPolicy.afterWarmUp(0, nextIsWarmUp = false))

        val session = engine.startSession("Push", now = base)
        val exercise = engine.addExercise(bench, WR, session)
        repeat(2) { engine.addSet(exercise, SetKind.WARM_UP) }
        val (first, second) = exercise.orderedSets.filter { it.kind == SetKind.WARM_UP }
        for (set in listOf(first, second)) {
            set.weightKg = 40.0
            set.reps = 5
        }
        assertEquals(60.0, engine.completeSet(first, 180, base)?.totalSeconds)
        assertEquals(90.0, engine.completeSet(second, 180, base)?.totalSeconds)
    }
}
