package com.brunodobric.gymapp.health

import com.brunodobric.gymapp.model.BodyMeasurement
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.MeasurementSource
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionState
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class HealthExportPlanTest {
    private val now: Instant = Instant.parse("2026-11-10T12:00:00Z")
    private val zone = ZoneOffset.UTC

    private fun session(daysAgo: Long, name: String = "Push"): Session {
        val start = now.minus(Duration.ofDays(daysAgo))
        val session = Session(name, startedAt = start)
        session.state = SessionState.FINISHED
        session.endedAt = start.plusSeconds(3_600)
        return session
    }

    private fun weight(daysAgo: Long, kg: Double = 80.0, source: MeasurementSource = MeasurementSource.MANUAL) =
        BodyMeasurement(BodyMeasurementKind.WEIGHT, kg, now.minus(Duration.ofDays(daysAgo)), source)

    private fun plan(sessions: List<Session>, measurements: List<BodyMeasurement> = emptyList(), ledger: HealthLedger = HealthLedger()) =
        HealthExportPlanner.plan(sessions, measurements, ledger, now = now, zone = zone)

    @Test
    fun `prvi izvoz nosi treninge iz zadnjih 30 dana i rucne tezine iz zadnje godine`() {
        val recent = session(3)
        val old = session(45)
        val unfinished = session(1).also { it.state = SessionState.ACTIVE; it.endedAt = null }
        val manual = weight(10)
        val fromHealth = weight(5, source = MeasurementSource.HEALTH_KIT)
        val height = BodyMeasurement(BodyMeasurementKind.HEIGHT, 180.0, now)
        val oldWeight = weight(400)
        val result = plan(listOf(recent, old, unfinished), listOf(manual, fromHealth, height, oldWeight))
        assertEquals(listOf(recent.id), result.workouts.map { it.sessionId })
        assertEquals(listOf(manual.id), result.weights.map { it.id })
        assertEquals(setOf(recent.id), result.ledger.workouts.keys)
        assertEquals(setOf(manual.id), result.ledger.weights.keys)
    }

    @Test
    fun `nepromijenjen zapis se ne upisuje ponovno, a izmjena da`() {
        val workout = session(2)
        val scale = weight(1)
        val first = plan(listOf(workout), listOf(scale))
        assertTrue(plan(listOf(workout), listOf(scale), first.ledger).isEmpty)

        workout.name = "Pull"
        scale.value = 79.5
        val second = plan(listOf(workout), listOf(scale), first.ledger)
        assertEquals(listOf(workout.id), second.workouts.map { it.sessionId })
        assertEquals(listOf(scale.id), second.weights.map { it.id })
    }

    @Test
    fun `obrisan trening i tezina brisu se i iz Health Connecta`() {
        val workout = session(2)
        val scale = weight(1)
        val first = plan(listOf(workout), listOf(scale))
        val second = plan(emptyList(), emptyList(), first.ledger)
        assertEquals(listOf(workout.id), second.deletedWorkouts)
        assertEquals(listOf(scale.id), second.deletedWeights)
        assertTrue(second.ledger.workouts.isEmpty() && second.ledger.weights.isEmpty())
    }

    @Test
    fun `vec upisan stari trening prati izmjene i izvan prozora`() {
        val workout = session(40)
        val ledger = HealthLedger(workouts = mapOf(workout.id to "staro"))
        val result = plan(listOf(workout), ledger = ledger)
        assertEquals(listOf(workout.id), result.workouts.map { it.sessionId })
        assertTrue(result.deletedWorkouts.isEmpty())
    }

    @Test
    fun `trening iz Zdravlja na iPhoneu se ne sprema`() {
        val copied = session(1).also { it.healthKitWorkoutId = java.util.UUID.randomUUID() }
        assertTrue(plan(listOf(copied)).isEmpty)
    }

    @Test
    fun `zapis se cita kako je spremljen, a neispravni retci se preskacu`() {
        val workout = session(2)
        val scale = weight(1)
        val ledger = plan(listOf(workout), listOf(scale)).ledger
        assertEquals(ledger, HealthLedger.decode(ledger.encode() + "smece\nw\tnije-uuid\tx\n"))
    }
}
