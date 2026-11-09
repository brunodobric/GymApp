package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.Session
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionEditorTest {
    private val bench = ExerciseRef.catalog("bench", "Potisak s klupe")
    private val row = ExerciseRef.catalog("row", "Veslanje")
    private val base = Instant.ofEpochSecond(1_800_000_000)
    private val wr = ExerciseInputType.WEIGHT_REPS
    private val persistence = InMemoryPersistence()
    private val store = GymStore(persistence)
    private val engine = WorkoutEngine(store)
    private val editor = SessionEditor(store)

    /** Odrađen trening s potiskom (80 × 8, 85 × 6). */
    private fun finishedSession(): Session {
        val session = engine.startSession("Push", now = base)
        val exercise = engine.addExercise(bench, wr, session, now = base)
        exercise.orderedSets.forEach { engine.removeSet(it, base) }
        for ((weight, reps) in listOf(80.0 to 8, 85.0 to 6)) {
            val set = engine.addSet(exercise, now = base)
            set.weightKg = weight
            set.reps = reps
            engine.completeSet(set, 0, base.plusSeconds(60))
        }
        engine.finishSession(session, now = base.plusSeconds(3600))
        return session
    }

    /** Spremljeno stanje, čitano iznova iz trajne pohrane. */
    private fun saved(session: Session): Session = GymStore(persistence).session(session.id)!!

    @Test
    fun `brisanje svih serija s udaljenošću briše i udaljenost treninga`() {
        val session = engine.startSession("Kondicija", now = base)
        val pressing = engine.addExercise(bench, wr, session, now = base)
        pressing.orderedSets.forEach { engine.removeSet(it, base) }
        engine.addSet(pressing, now = base).apply { weightKg = 80.0; reps = 8 }.also { engine.completeSet(it, 0, base.plusSeconds(60)) }
        val rowing = engine.addExercise(row, ExerciseInputType.DURATION_DISTANCE, session, now = base)
        rowing.orderedSets.forEach { engine.removeSet(it, base) }
        engine.addSet(rowing, now = base).apply { durationSeconds = 300; distanceMeters = 1000.0 }
            .also { engine.completeSet(it, 0, base.plusSeconds(120)) }
        engine.finishSession(session, now = base.plusSeconds(3600))
        assertEquals(1000.0, session.distanceMeters)

        editor.removeExercise(session.orderedExercises.first { it.exercise.key == row.key })
        editor.save(session)
        assertNull(saved(session).distanceMeters)
    }

    @Test
    fun `spremljene izmjene - naziv, vrijednosti, nova serija i nova vježba`() {
        val session = finishedSession()
        session.name = "  Push A  "
        val pressing = session.orderedExercises[0]
        pressing.orderedSets[1].reps = 7
        val added = editor.addSet(pressing)
        assertEquals(85.0, added.weightKg)
        assertEquals(7, added.reps)
        assertEquals(session.endedAt, added.completedAt)
        val rowing = editor.addExercise(row, wr, session)
        val set = rowing.orderedSets[0]
        set.weightKg = 50.0
        set.reps = 10
        editor.toggleCompleted(set)
        editor.save(session)

        val stored = saved(session)
        assertEquals("Push A", stored.name)
        assertEquals(listOf("Potisak s klupe", "Veslanje"), stored.orderedExercises.map { it.exerciseName })
        assertEquals(listOf(8, 7, 7), stored.orderedExercises[0].orderedSets.map { it.reps })
        assertEquals(1, stored.orderedExercises[1].orderedSets.size)
        assertEquals(0, stored.orderedExercises[1].orderedSets[0].orderIndex)
    }

    @Test
    fun `odustajanje vraća odrađeni trening kakav je bio`() {
        val session = finishedSession()
        session.name = "Drugo"
        editor.removeSet(session.orderedExercises[0].orderedSets[0])
        editor.addExercise(row, wr, session)

        assertEquals("Push", saved(session).name)
        editor.cancel()
        val restored = store.session(session.id)!!
        assertEquals("Push", restored.name)
        assertEquals(1, restored.orderedExercises.size)
        assertEquals(2, restored.orderedExercises[0].orderedSets.size)
    }

    @Test
    fun `obrisana vježba i serija nestaju, a redoslijed se slaže iznova`() {
        val session = finishedSession()
        val rowing = editor.addExercise(row, wr, session)
        rowing.orderedSets[0].weightKg = 40.0
        rowing.orderedSets[0].reps = 12
        editor.toggleCompleted(rowing.orderedSets[0])
        editor.removeSet(session.orderedExercises[0].orderedSets[0])
        editor.removeExercise(session.orderedExercises[0])
        editor.save(session)

        val stored = saved(session)
        assertEquals(listOf("Veslanje"), stored.orderedExercises.map { it.exerciseName })
        assertEquals(0, stored.orderedExercises[0].orderIndex)
    }

    @Test
    fun `kvačica traži potpune vrijednosti, a trening bez završene serije se ne sprema`() {
        val session = finishedSession()
        val rowing = editor.addExercise(row, wr, session)
        assertFailsWith<WorkoutError.SetIncomplete> { editor.toggleCompleted(rowing.orderedSets[0]) }
        session.orderedExercises[0].orderedSets.forEach { editor.toggleCompleted(it) }
        assertFailsWith<WorkoutError.NothingCompleted> { editor.save(session) }
        assertTrue(saved(session).orderedExercises[0].orderedSets.all { it.isCompleted })
    }

    @Test
    fun `kraj treninga nije prije početka`() {
        val session = finishedSession()
        session.startedAt = base.plusSeconds(7200)
        editor.save(session)
        val stored = saved(session)
        assertEquals(stored.startedAt, stored.endedAt)
    }
}
