package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.training.RestDefaults
import com.brunodobric.gymapp.widgets.WidgetSnapshot
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class WatchGlanceTest {
    private val week = WidgetSnapshot.Week.empty(base, sessions = 2, goal = 4, streakWeeks = 1)
    private val context = WatchContextPayload(upcoming = listOf(plan()), templates = listOf(plan().copy(templateId = null, scheduleId = null, name = "Legs")), week = week, accent = "green")

    @Test
    fun `bez treninga - sljedeci trening rasporeda i tjedan`() {
        val glance = WatchGlance.from(WatchUiState(context = context))
        assertEquals(WatchGlance.Kind.NEXT, glance.kind(base))
        assertEquals("Pull", glance.next?.name)
        assertEquals("PPL", glance.next?.scheduleName)
        assertEquals(3, glance.next?.exerciseCount)
        assertEquals(context.upcoming.first().id, glance.next?.planId)
        assertEquals(2, glance.week(base)?.sessions)
        assertEquals("green", glance.accent)
    }

    @Test
    fun `prazan kontekst`() {
        val glance = WatchGlance.from(WatchUiState())
        assertEquals(WatchGlance.Kind.EMPTY, glance.kind(base))
        assertNull(glance.week(base))
    }

    @Test
    fun `trening u tijeku pa odmor koji istjece`() {
        var snapshot = SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base)
        val glance = WatchGlance.from(WatchUiState(context = context, active = snapshot))
        assertEquals(WatchGlance.Kind.ACTIVE, glance.kind(base))
        assertEquals(base, glance.activeStartedAt)

        val engine = SnapshotEngine(snapshot)
        val set = snapshot.exercises.first().sets.first()
        engine.completeSet(set.id, RestDefaults(150, 90), now = base.plusSeconds(30))
        snapshot = engine.snapshot
        val resting = WatchGlance.from(WatchUiState(context = context, active = snapshot, isResting = true))
        val ends = assertNotNullValue(resting.restEndsAt)
        assertEquals(WatchGlance.Kind.RESTING, resting.kind(base.plusSeconds(31)))
        assertEquals(WatchGlance.Kind.ACTIVE, resting.kind(ends))
        assertNotEquals(glance, resting)

        // Store javlja kraj odmora: prikaz se mijenja i bez novog trenutka.
        val after = WatchGlance.from(WatchUiState(context = context, active = snapshot, isResting = false))
        assertNull(after.restEndsAt)
        assertFalse(after.isResting(base.plusSeconds(31)))
        assertNotEquals(resting, after)
    }

    @Test
    fun `zavrseni trening se ne prikazuje kao trening u tijeku`() {
        val snapshot = SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base).copy(state = SessionState.FINISHED, endedAt = base.plusSeconds(600))
        val glance = WatchGlance.from(WatchUiState(context = context, active = snapshot, isResting = true))
        assertEquals(WatchGlance.Kind.NEXT, glance.kind(base))
        assertNull(glance.activeName)
    }

    @Test
    fun `isti sadrzaj daje jednak prikaz`() {
        assertEquals(WatchGlance.from(WatchUiState(context = context)), WatchGlance.from(WatchUiState(context = context.copy())))
    }

    @Test
    fun `plan po id-u iz rasporeda i predlozaka`() {
        assertEquals("Pull", context.plan(context.upcoming.first().id)?.name)
        assertEquals("Legs", context.plan(context.templates.first().id)?.name)
        assertNull(context.plan("nema"))
        assertTrue(context.templates.first().id.startsWith("-/"))
    }

    private fun <T : Any> assertNotNullValue(value: T?): T = kotlin.test.assertNotNull(value)
}
