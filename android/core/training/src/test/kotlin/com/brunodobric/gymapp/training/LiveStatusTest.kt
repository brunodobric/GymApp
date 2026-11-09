package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.SessionExercise
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LiveStatusTest {
    private val squat = ExerciseRef.catalog("squat", "Čučanj")
    private val bench = ExerciseRef.catalog("bench", "Potisak s klupe")
    private val row = ExerciseRef.catalog("row", "Veslanje")
    private val start = Instant.ofEpochSecond(1_800_000_000)
    private val wr = ExerciseInputType.WEIGHT_REPS
    private val engine = WorkoutEngine(GymStore())

    /** Popunjava sve serije vježbe da se mogu potvrditi. */
    private fun fill(exercise: SessionExercise) = exercise.orderedSets.forEach { it.weightKg = 60.0; it.reps = 8 }

    @Test
    fun `prva serija prve vježbe, pa sljedeća vježba i broj serija`() {
        val session = engine.startSession("A", now = start)
        val first = engine.addExercise(squat, wr, session, now = start)
        engine.addExercise(bench, wr, session, now = start)

        val status = engine.liveStatus(session)
        assertEquals("Čučanj", status.currentExerciseName)
        assertEquals("Potisak s klupe", status.nextExerciseName)
        assertEquals(1, status.setNumber)
        assertEquals(3, status.setCount)
        assertEquals(first.orderedSets[0].id, status.nextSetId)
        assertEquals(0, status.completedSets)
        assertEquals(6, status.totalSets)
        assertNull(status.rest)
        assertFalse(status.canConfirmNextSet)
    }

    @Test
    fun `nakon potvrde serije - sljedeća serija iste vježbe i rest timer`() {
        val session = engine.startSession("A", now = start)
        val first = engine.addExercise(squat, wr, session, now = start)
        fill(first)
        engine.completeSet(engine.nextSet(session)!!, 90, start.plusSeconds(30))

        val status = engine.liveStatus(session)
        assertEquals(2, status.setNumber)
        assertEquals(first.orderedSets[1].id, status.nextSetId)
        assertTrue(status.canConfirmNextSet)
        assertEquals(1, status.completedSets)
        assertEquals(start.plusSeconds(120), status.rest?.endsAt)
        assertNull(status.nextExerciseName)
    }

    @Test
    fun `ostaje na vježbi koju korisnik radi, i kad nije prva po redu`() {
        val session = engine.startSession("A", now = start)
        engine.addExercise(squat, wr, session, now = start)
        val second = engine.addExercise(bench, wr, session, now = start)
        fill(second)
        engine.completeSet(second.orderedSets[0], 90, start)

        val status = engine.liveStatus(session)
        assertEquals("Potisak s klupe", status.currentExerciseName)
        assertEquals(2, status.setNumber)
        assertEquals("Čučanj", status.nextExerciseName)
    }

    @Test
    fun `kad je vježba gotova, prelazi se na prvu nezavršenu po redu`() {
        val session = engine.startSession("A", now = start)
        engine.addExercise(squat, wr, session, now = start)
        val second = engine.addExercise(bench, wr, session, now = start)
        engine.addExercise(row, wr, session, now = start)
        fill(second)
        second.orderedSets.forEach { engine.completeSet(it, 90, start) }

        val status = engine.liveStatus(session)
        assertEquals("Čučanj", status.currentExerciseName)
        assertEquals("Veslanje", status.nextExerciseName)
    }

    @Test
    fun `superset - serije idu naizmjence, a sljedeća vježba je partner`() {
        val session = engine.startSession("A", now = start)
        val first = engine.addExercise(bench, wr, session, now = start)
        val second = engine.addExercise(row, wr, session, now = start)
        engine.makeSuperset(listOf(first, second), session, start)
        fill(first)
        fill(second)

        assertEquals("Veslanje", engine.liveStatus(session).nextExerciseName)
        engine.completeSet(first.orderedSets[0], 90, start)
        val status = engine.liveStatus(session)
        assertEquals("Veslanje", status.currentExerciseName)
        assertEquals(second.orderedSets[0].id, status.nextSetId)
        assertEquals("Potisak s klupe", status.nextExerciseName)
    }

    @Test
    fun `sve serije završene - nema serije za potvrdu`() {
        val session = engine.startSession("A", now = start)
        val first = engine.addExercise(squat, wr, session, now = start)
        fill(first)
        first.orderedSets.forEach { engine.completeSet(it, 90, start) }

        val status = engine.liveStatus(session)
        assertTrue(status.isAllCompleted)
        assertNull(status.nextSetId)
        assertNull(status.currentExerciseName)
        assertFalse(status.canConfirmNextSet)
    }

    @Test
    fun `uklonjena vježba ne broji se u serije`() {
        val session = engine.startSession("A", now = start)
        val first = engine.addExercise(squat, wr, session, now = start)
        engine.addExercise(bench, wr, session, now = start)
        engine.removeExercise(first, start)

        val status = engine.liveStatus(session)
        assertEquals("Potisak s klupe", status.currentExerciseName)
        assertEquals(3, status.totalSets)
    }

    @Test
    fun `obavijest o kraju odmora samo za trening koji vodi telefon`() {
        val end = start.plusSeconds(90)
        fun fire(
            endsAt: Instant? = end,
            device: DeviceRole = DeviceRole.PHONE,
            enabled: Boolean = true,
            active: Boolean = true,
            watch: Boolean = false,
        ) = RestNotificationPolicy.fireDate(endsAt, device, enabled, active, watch, start)
        assertEquals(end, fire())
        assertNull(fire(watch = true))
        assertNull(fire(device = DeviceRole.WATCH))
        assertNull(fire(enabled = false))
        assertNull(fire(active = false))
        assertNull(fire(endsAt = null))
        assertNull(fire(endsAt = start.plusMillis(500)))
    }

    @Test
    fun `plus 10 pomiče trenutak obavijesti`() {
        val session = engine.startSession("A", now = start)
        val first = engine.addExercise(squat, wr, session, now = start)
        fill(first)
        engine.completeSet(first.orderedSets[0], 90, start)
        engine.adjustRest(session, 10, start.plusSeconds(5))
        val fire = RestNotificationPolicy.fireDate(
            engine.liveStatus(session).rest?.endsAt, session.controllingDevice, true, true, now = start.plusSeconds(5),
        )
        assertEquals(start.plusSeconds(100), fire)
    }
}
