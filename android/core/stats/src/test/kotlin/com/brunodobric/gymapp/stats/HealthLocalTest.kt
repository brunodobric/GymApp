package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.HealthLocalSource
import com.brunodobric.gymapp.model.HealthMeasurement
import com.brunodobric.gymapp.model.HealthWorkout
import com.brunodobric.gymapp.model.MeasurementSource
import com.brunodobric.gymapp.model.WorkoutKind
import java.util.UUID
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

private class MemoryHealth(
    override var workouts: List<HealthWorkout> = emptyList(),
    override var measurements: List<HealthMeasurement> = emptyList(),
) : HealthLocalSource {
    override fun deleteWorkout(id: UUID) {
        workouts = workouts.filter { it.id != id }
    }

    override fun deleteMeasurement(id: UUID) {
        measurements = measurements.filter { it.id != id }
    }
}

// Port dijela GymKit/Tests/HealthSyncTests (prikaz uvezenih podataka uz vlastite).
class HealthLocalTest {
    private fun run(start: Double) = HealthWorkout(
        id = UUID.randomUUID(), recordId = "hc-$start", name = "Trčanje",
        startedAt = base.plusDays(start), endedAt = base.plusDays(start).plusSeconds(1_800), distanceMeters = 5_000.0,
    )

    @Test
    fun `uvezeni trening je u povijesti i kalendaru uz vlastite, kao kardio`() {
        val store = newStore()
        val own = store.addSession(base, lifts = emptyList())
        val imported = run(1.0)
        store.health = MemoryHealth(workouts = listOf(imported))
        val history = HistoryQueries(store)

        assertEquals(listOf(imported.id, own.id), history.sessions().map { it.id })
        val shown = history.sessions().first()
        assertTrue(shown.isImportedFromWorkoutsApp)
        assertEquals(WorkoutKind.CARDIO, shown.kind)
        assertEquals(5_000.0, shown.distanceMeters)
        assertEquals(listOf(imported.id), history.sessions(HistoryFilter(setOf(WorkoutKind.CARDIO))).map { it.id })
        assertEquals(2, history.workoutDays(DateInterval(base, base.plusDays(3.0))).size)
        assertNotNull(history.session(imported.id))
    }

    @Test
    fun `brisanje uvezenog treninga brise samo lokalni zapis i javlja promjenu`() {
        val store = newStore()
        val own = store.addSession(base, lifts = emptyList())
        val imported = run(1.0)
        val health = MemoryHealth(workouts = listOf(imported))
        store.health = health
        val history = HistoryQueries(store)
        val revision = store.revision

        history.delete(history.session(imported.id)!!)
        assertTrue(health.workouts.isEmpty())
        assertEquals(listOf(own.id), store.sessions.map { it.id })
        assertTrue(store.revision > revision)
    }

    @Test
    fun `tezina iz Health Connecta je u povijesti mjere i brise se lokalno`() {
        val store = newStore()
        val tracking = BodyTracking(store)
        tracking.add(BodyMeasurementKind.WEIGHT, 82.0, base)
        val fromHealth = HealthMeasurement(UUID.randomUUID(), "w1", BodyMeasurementKind.WEIGHT, 81.0, base.plusDays(2.0))
        val height = HealthMeasurement(UUID.randomUUID(), "h1", BodyMeasurementKind.HEIGHT, 180.0, base)
        val health = MemoryHealth(measurements = listOf(fromHealth, height))
        store.health = health

        val weights = tracking.measurements(BodyMeasurementKind.WEIGHT)
        assertEquals(listOf(82.0, 81.0), weights.map { it.value })
        assertEquals(MeasurementSource.HEALTH_KIT, weights.last().source)
        assertEquals(-1.0, tracking.change(BodyMeasurementKind.WEIGHT))

        tracking.delete(weights.last())
        assertEquals(listOf(height), health.measurements)
        assertEquals(1, store.bodyMeasurements.size)
    }
}
