package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private val bench = ExerciseRef.catalog("bench", "Potisak s klupe")
private val row = ExerciseRef.catalog("row", "Veslanje")
private val squat = ExerciseRef.catalog("squat", "Čučanj")
private val base = Instant.ofEpochSecond(1_800_000_000)
private val WR = ExerciseInputType.WEIGHT_REPS

/** Odradi i završi trening s jednom vježbom: svaka serija je (težina, ponavljanja). */
private fun WorkoutEngine.finishedWorkout(start: Instant, sets: List<Pair<Double, Int>>, ref: ExerciseRef = bench): Session {
    val session = startSession("Trening", now = start)
    val exercise = addExercise(ref, WR, session, now = start)
    exercise.orderedSets.forEach { removeSet(it, start) }
    for ((weight, reps) in sets) {
        val set = addSet(exercise, now = start)
        set.weightKg = weight
        set.reps = reps
        completeSet(set, 90, start.plusSeconds(60))
    }
    finishSession(session, now = start.plusSeconds(3600))
    return session
}

class WorkoutEngineTest {
    private val persistence = InMemoryPersistence()
    private val store = GymStore(persistence)
    private val engine = WorkoutEngine(store)

    @Test
    fun `prethodne vrijednosti su završene serije zadnjeg treninga s tom vježbom`() {
        assertTrue(store.previousSetValues(bench).isEmpty())
        engine.finishedWorkout(base, listOf(60.0 to 10))
        engine.finishedWorkout(base.plusSeconds(86_400), listOf(70.0 to 8, 75.0 to 6))
        val values = store.previousSetValues(bench)
        assertEquals(listOf(70.0, 75.0), values.map { it.weightKg })
        assertEquals(listOf(8, 6), values.map { it.reps })
        assertTrue(store.previousSetValues(row).isEmpty())
    }

    @Test
    fun `samo jedan aktivan trening istovremeno`() {
        engine.startSession("A", now = base)
        assertFailsWith<WorkoutError.AlreadyActive> { engine.startSession("B", now = base) }
    }

    @Test
    fun `vježba bez povijesti dobiva tri prazne radne serije`() {
        val session = engine.startSession("A", now = base)
        val exercise = engine.addExercise(bench, WR, session, now = base)
        assertEquals(WorkoutEngine.DEFAULT_WORKING_SETS, exercise.orderedSets.size)
        assertTrue(exercise.orderedSets.all { it.kind == SetKind.WORKING && it.weightKg == null })
    }

    @Test
    fun `nova vježba preuzima serije i vrijednosti iz zadnjeg treninga`() {
        engine.finishedWorkout(base, listOf(80.0 to 8, 85.0 to 8, 90.0 to 6))
        val later = base.plusSeconds(86_400)
        val session = engine.startSession("B", now = later)
        val exercise = engine.addExercise(bench, WR, session, now = later)
        assertEquals(listOf(80.0, 85.0, 90.0), exercise.orderedSets.map { it.weightKg })
        assertEquals(listOf(8, 8, 6), exercise.orderedSets.map { it.reps })
        assertTrue(exercise.orderedSets.none { it.isCompleted })
    }

    @Test
    fun `dodana serija bez povijesti uzima vrijednosti prethodne serije`() {
        val session = engine.startSession("A", now = base)
        val exercise = engine.addExercise(bench, WR, session, now = base)
        exercise.orderedSets[2].weightKg = 70.0
        exercise.orderedSets[2].reps = 10
        val added = engine.addSet(exercise, now = base)
        assertEquals(70.0, added.weightKg)
        assertEquals(10, added.reps)
        assertEquals(3, added.orderIndex)
    }

    @Test
    fun `zagrijavanje se dodaje ispred prve neodrađene serije, a radna serija na kraj`() {
        val session = engine.startSession("A", now = base)
        val exercise = engine.addExercise(bench, WR, session, now = base)
        val first = exercise.orderedSets[0]
        first.weightKg = 60.0
        first.reps = 10
        engine.completeSet(first, 90, base)

        val warmUp = engine.addSet(exercise, SetKind.WARM_UP, base)
        assertEquals(listOf(SetKind.WORKING, SetKind.WARM_UP, SetKind.WORKING, SetKind.WORKING), exercise.orderedSets.map { it.kind })
        assertEquals(1, warmUp.orderIndex)
        assertEquals(listOf(0, 1, 2, 3), exercise.orderedSets.map { it.orderIndex })
        assertEquals(4, engine.addSet(exercise, SetKind.WORKING, base).orderIndex)

        for (set in exercise.orderedSets.filter { !it.isCompleted }) {
            set.weightKg = 40.0
            set.reps = 10
            engine.completeSet(set, 90, base)
        }
        val last = engine.addSet(exercise, SetKind.WARM_UP, base)
        assertEquals(5, last.orderIndex)
        assertEquals(last.id, exercise.orderedSets.last().id)
    }

    @Test
    fun `označavanje serije traži sve vrijednosti i pokreće rest timer`() {
        val session = engine.startSession("A", now = base)
        val set = engine.addExercise(bench, WR, session, now = base).orderedSets[0]
        assertFailsWith<WorkoutError.SetIncomplete> { engine.completeSet(set, 90, base) }
        assertFalse(set.isCompleted)

        set.weightKg = 80.0
        set.reps = 8
        val timer = engine.completeSet(set, 90, base)
        assertTrue(set.isCompleted)
        assertEquals(90.0, timer?.totalSeconds)
        assertEquals(base.plusSeconds(90), engine.restTimer(session)?.endsAt)

        assertEquals(base.plusSeconds(100), engine.adjustRest(session, 10, base.plusSeconds(30))?.endsAt)
        assertEquals(base.plusSeconds(100), engine.restTimer(session)?.endsAt)

        engine.cancelRest(session, base)
        assertNull(engine.restTimer(session))
    }

    @Test
    fun `pauza vježbe nadjačava zadanu`() {
        val session = engine.startSession("A", now = base)
        val set = engine.addExercise(bench, WR, session, restSeconds = 150, now = base).orderedSets[0]
        set.weightKg = 80.0
        set.reps = 8
        assertEquals(150.0, engine.completeSet(set, 90, base)?.totalSeconds)
    }

    @Test
    fun `superset - bez pauze nakon prve vježbe, zadana nakon zadnje`() {
        val session = engine.startSession("A", now = base)
        val first = engine.addExercise(bench, WR, session, now = base)
        val second = engine.addExercise(row, WR, session, now = base)
        engine.makeSuperset(listOf(first, second), session, base)
        listOf(first.orderedSets[0], second.orderedSets[0]).forEach { it.weightKg = 50.0; it.reps = 10 }
        assertNull(engine.completeSet(first.orderedSets[0], 90, base))
        assertEquals(90.0, engine.completeSet(second.orderedSets[0], 90, base)?.totalSeconds)
    }

    @Test
    fun `zadana pauza prema vrsti vježbe, a vlastita pauza ima prednost`() {
        val session = engine.startSession("A", now = base)
        val compound = engine.addExercise(bench, WR, session, now = base)
        val isolation = engine.addExercise(row, WR, session, now = base)
        val own = engine.addExercise(bench, WR, session, restSeconds = 60, now = base)
        listOf(compound, isolation, own).forEach { it.orderedSets[0].weightKg = 50.0; it.orderedSets[0].reps = 10 }
        val defaults = RestDefaults(180, 75)
        val isCompound: (String) -> Boolean? = { if (it == bench.key) true else null }
        assertEquals(180.0, engine.completeSet(compound.orderedSets[0], defaults, isCompound, base)?.totalSeconds)
        assertEquals(75.0, engine.completeSet(isolation.orderedSets[0], defaults, isCompound, base)?.totalSeconds)
        assertEquals(60.0, engine.completeSet(own.orderedSets[0], defaults, isCompound, base)?.totalSeconds)
    }

    @Test
    fun `superset sa složenom vježbom odmara kao složena vježba`() {
        val session = engine.startSession("A", now = base)
        val first = engine.addExercise(bench, WR, session, now = base)
        val second = engine.addExercise(row, WR, session, now = base)
        engine.makeSuperset(listOf(first, second), session, base)
        listOf(first, second).forEach { it.orderedSets[0].weightKg = 50.0; it.orderedSets[0].reps = 10 }
        val defaults = RestDefaults(150, 90)
        val isCompound: (String) -> Boolean? = { it == bench.key }
        assertNull(engine.completeSet(first.orderedSets[0], defaults, isCompound, base))
        assertEquals(150.0, engine.completeSet(second.orderedSets[0], defaults, isCompound, base)?.totalSeconds)
    }

    @Test
    fun `superset stavlja vježbe jednu do druge, a samac se raspušta`() {
        val session = engine.startSession("A", now = base)
        val first = engine.addExercise(bench, WR, session, now = base)
        val middle = engine.addExercise(squat, WR, session, now = base)
        val last = engine.addExercise(row, WR, session, now = base)

        engine.makeSuperset(listOf(first, last), session, base)
        assertEquals(listOf(first.id, last.id, middle.id), engine.visibleExercises(session).map { it.id })
        assertNotNull(first.supersetGroupId)
        assertEquals(first.supersetGroupId, last.supersetGroupId)
        assertEquals(listOf(first.id, last.id), engine.group(first).map { it.id })

        engine.removeFromSuperset(last, base)
        assertNull(first.supersetGroupId)
        assertNull(last.supersetGroupId)
        assertFailsWith<WorkoutError.NeedsTwoExercises> { engine.makeSuperset(listOf(first), session, base) }
    }

    @Test
    fun `izbacivanje vježbe se poništava i redoslijed se mijenja povlačenjem`() {
        val session = engine.startSession("A", now = base)
        val first = engine.addExercise(bench, WR, session, now = base)
        val second = engine.addExercise(row, WR, session, now = base)
        val third = engine.addExercise(squat, WR, session, now = base)

        engine.moveExercises(session, listOf(2), 0, base)
        assertEquals(listOf(third.id, first.id, second.id), engine.visibleExercises(session).map { it.id })

        engine.removeExercise(first, base)
        assertEquals(listOf(third.id, second.id), engine.visibleExercises(session).map { it.id })
        assertEquals(listOf(first.id), engine.removedExercises(session).map { it.id })

        engine.restoreExercise(first, base)
        assertEquals(listOf(third.id, second.id, first.id), engine.visibleExercises(session).map { it.id })
        assertTrue(engine.removedExercises(session).isEmpty())
    }

    @Test
    fun `brisanje serije se poništava - serija se vraća na isto mjesto s istim vrijednostima`() {
        val session = engine.startSession("A", now = base)
        val exercise = engine.addExercise(bench, WR, session, now = base)
        val sets = exercise.orderedSets
        val middle = sets[1]
        middle.weightKg = 80.0
        middle.reps = 8
        middle.rpe = 8.5
        engine.completeSet(middle, 90, base.plusSeconds(60))
        val ids = sets.map { it.id }

        val removed = engine.removeSet(middle, base.plusSeconds(120))
        assertEquals(listOf(ids[0], ids[2]), exercise.orderedSets.map { it.id })
        assertEquals(listOf(0, 1), exercise.orderedSets.map { it.orderIndex })
        assertEquals(1, removed.position)
        assertEquals(base.plusSeconds(120), session.lastActivityAt)

        val restored = engine.restoreSet(removed, exercise, base.plusSeconds(130))
        assertEquals(ids, exercise.orderedSets.map { it.id })
        assertEquals(listOf(0, 1, 2), exercise.orderedSets.map { it.orderIndex })
        assertEquals(SetValues(SetKind.WORKING, weightKg = 80.0, reps = 8, rpe = 8.5), restored.values)
        assertEquals(base.plusSeconds(60), restored.completedAt)
        assertEquals(base.plusSeconds(130), session.lastActivityAt)
    }

    @Test
    fun `vraćena serija ide na kraj ako je vježba u međuvremenu ostala bez serija`() {
        val session = engine.startSession("A", now = base)
        val exercise = engine.addExercise(bench, WR, session, now = base)
        val removed = engine.removeSet(exercise.orderedSets.last(), base)
        exercise.orderedSets.forEach { engine.removeSet(it, base) }
        engine.restoreSet(removed, exercise, base)
        assertEquals(listOf(removed.id), exercise.orderedSets.map { it.id })
        assertEquals(listOf(0), exercise.orderedSets.map { it.orderIndex })
    }

    @Test
    fun `završetak briše nezavršene serije, prazne i izbačene vježbe`() {
        val session = engine.startSession("A", now = base)
        val kept = engine.addExercise(bench, WR, session, now = base)
        engine.addExercise(row, WR, session, now = base)
        val removed = engine.addExercise(squat, WR, session, now = base)
        val set = kept.orderedSets[0]
        set.weightKg = 80.0
        set.reps = 8
        engine.completeSet(set, 90, base)
        engine.removeExercise(removed, base)

        engine.finishSession(session, "Dobro", base.plusSeconds(1800))

        assertEquals(SessionState.FINISHED, session.state)
        assertEquals("Dobro", session.notes)
        assertEquals(base.plusSeconds(1800), session.endedAt)
        assertNull(engine.restTimer(session))
        val reloaded = GymStore(persistence)
        assertEquals(listOf(kept.id), reloaded.sessionExercises.map { it.id })
        assertEquals(1, reloaded.sessionExercises[0].orderedSets.size)
    }

    @Test
    fun `trening bez ijedne završene serije ne može se spremiti i ostaje netaknut`() {
        val session = engine.startSession("A", now = base)
        val exercise = engine.addExercise(bench, WR, session, now = base)
        assertFailsWith<WorkoutError.NothingCompleted> { engine.finishSession(session, now = base) }
        assertEquals(SessionState.ACTIVE, session.state)
        assertEquals(WorkoutEngine.DEFAULT_WORKING_SETS, exercise.orderedSets.size)
    }

    @Test
    fun `odbacivanje briše trening sa svim serijama`() {
        val session = engine.startSession("A", now = base)
        engine.addExercise(bench, WR, session, now = base)
        engine.discardSession(session)
        assertTrue(persistence.loadAll().isEmpty())
    }

    @Test
    fun `prekinuti trening se pronalazi i rest timer preživi ponovno otvaranje`() {
        val session = engine.startSession("A", now = base)
        val set = engine.addExercise(bench, WR, session, now = base).orderedSets[0]
        set.weightKg = 80.0
        set.reps = 8
        engine.completeSet(set, 120, base)

        // "Ponovno pokretanje": nova baza i engine nad istim spremljenim zapisima.
        val restarted = WorkoutEngine(GymStore(persistence))
        val found = assertNotNull(restarted.store.activeSession())
        assertEquals(session.id, found.id)
        val timer = assertNotNull(restarted.restTimer(found))
        assertEquals(20.0, timer.remaining(base.plusSeconds(100)))
        assertTrue(timer.isExpired(base.plusSeconds(200)))
        assertEquals(base, restarted.lastCompletedSetAt(found))
    }

    @Test
    fun `zaboravljeni trening se zatvara na zadnju završenu seriju`() {
        val session = engine.startSession("A", now = base)
        val set = engine.addExercise(bench, WR, session, now = base).orderedSets[0]
        set.weightKg = 80.0
        set.reps = 8
        engine.completeSet(set, 90, base.plusSeconds(600))
        engine.closeStaleSession(session)
        assertEquals(SessionState.FINISHED, session.state)
        assertEquals(base.plusSeconds(600), session.endedAt)
    }

    @Test
    fun `sažetak - trajanje, volumen bez warm-upa i rekordi samo prema ranijim treninzima`() {
        repeat(3) { engine.finishedWorkout(base.plusSeconds(it * 3600L), listOf(80.0 to 8)) }

        val start = base.plusSeconds(86_400)
        val session = engine.startSession("B", now = start)
        val exercise = engine.addExercise(bench, WR, session, now = start)
        exercise.orderedSets.forEach { engine.removeSet(it, start) }
        val warmUp = engine.addSet(exercise, SetKind.WARM_UP, start)
        warmUp.weightKg = 40.0
        warmUp.reps = 10
        val working = engine.addSet(exercise, SetKind.WORKING, start)
        working.weightKg = 85.0
        working.reps = 8
        engine.completeSet(warmUp, 90, start.plusSeconds(60))
        engine.completeSet(working, 90, start.plusSeconds(300))
        engine.finishSession(session, now = start.plusSeconds(1800))

        val summary = engine.summary(session)
        assertEquals(1800.0, summary.durationSeconds)
        assertEquals(2, summary.completedSets)
        assertEquals(680.0, summary.totalVolumeKg)
        assertEquals(1, summary.hardSets)
        val records = summary.records.first()
        assertEquals("Potisak s klupe", records.exerciseName)
        assertTrue(records.records.any { it.kind == PRKind.MAX_WEIGHT && it.value == 85.0 })
        assertEquals(listOf(PRKind.ESTIMATED_ONE_REP_MAX), summary.highlights.map { it.record.kind })
        assertEquals(records.records.size - 1, summary.otherRecordsCount)

        val excluded = engine.summary(session, excludedExercises = setOf(bench.key))
        assertTrue(excluded.records.isEmpty() && excluded.highlights.isEmpty())
    }

    @Test
    fun `zadnje izvođenje koristi samo završene treninge, ne aktivni`() {
        val first = engine.startSession("A", now = base)
        val set = engine.addExercise(bench, WR, first, now = base).orderedSets[0]
        set.weightKg = 100.0
        set.reps = 5
        engine.completeSet(set, 90, base)
        engine.discardSession(first)

        val second = engine.startSession("B", now = base)
        assertTrue(engine.addExercise(bench, WR, second, now = base).orderedSets.all { it.weightKg == null })
    }

    @Test
    fun `kardio trening sprema ukupnu udaljenost završenih serija`() {
        val session = engine.startSession("Kardio", now = base)
        val run = engine.addExercise(row, ExerciseInputType.DURATION_DISTANCE, session, now = base)
        run.orderedSets.forEach { engine.removeSet(it, base) }
        for (meters in listOf(3000.0, 2000.0)) {
            val set = engine.addSet(run, now = base)
            set.durationSeconds = 900
            set.distanceMeters = meters
            engine.completeSet(set, 60, base.plusSeconds(900))
        }
        val unfinished = engine.addSet(run, now = base)
        unfinished.durationSeconds = 60
        unfinished.distanceMeters = 999.0
        engine.finishSession(session, now = base.plusSeconds(2000))
        assertEquals(5000.0, session.distanceMeters)
    }

    @Test
    fun `udaljenost izbačene vježbe ne ulazi u udaljenost treninga`() {
        val session = engine.startSession("Kardio", now = base)
        val run = engine.addExercise(ExerciseRef.catalog("run", "Trčanje"), ExerciseInputType.DURATION_DISTANCE, session, now = base)
        val bike = engine.addExercise(ExerciseRef.catalog("bike", "Bicikl"), ExerciseInputType.DURATION_DISTANCE, session, now = base)
        for ((exercise, meters) in listOf(run to 3000.0, bike to 8000.0)) {
            val set = exercise.orderedSets.first()
            set.durationSeconds = 900
            set.distanceMeters = meters
            engine.completeSet(set, 60, base.plusSeconds(900))
        }
        engine.removeExercise(bike, base)
        engine.finishSession(session, now = base.plusSeconds(2000))
        assertEquals(3000.0, session.distanceMeters)
    }
}
