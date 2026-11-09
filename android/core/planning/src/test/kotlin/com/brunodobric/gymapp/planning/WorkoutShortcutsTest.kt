package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.training.WorkoutEngine
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/PlanningTests/WorkoutShortcutsTests.swift.

private val squat = ExerciseRef.catalog("squat", "Čučanj")
private val base = Instant.ofEpochSecond(1_800_000_000)

private fun GymStore.template(name: String, exercises: List<ExerciseRef> = listOf(squat)): WorkoutTemplate {
    val engine = TemplateEngine(this)
    val result = engine.createTemplate(name)
    exercises.forEach { engine.addExercise(it, ExerciseInputType.WEIGHT_REPS, result) }
    return result
}

/** Aktivan raspored A, B. */
private fun GymStore.activeSchedule(): Pair<Schedule, List<WorkoutTemplate>> {
    val engine = ScheduleEngine(this)
    val templates = listOf("A", "B").map { template(it) }
    val schedule = engine.createSchedule("AB")
    templates.forEach { engine.addWorkout(it, schedule) }
    engine.setActive(true, schedule)
    return schedule to templates
}

private fun GymStore.completeFirstSet(session: Session) {
    val set = session.orderedExercises.first().orderedSets.first()
    set.weightKg = 60.0
    set.reps = 5
    WorkoutEngine(this).completeSet(set, 60, base)
}

private fun started(result: ShortcutStartResult): Session = assertIs<ShortcutStartResult.Started>(result).session

class WorkoutShortcutsTest {
    private val store = GymStore(InMemoryPersistence())
    private val shortcuts = WorkoutShortcuts(store)

    @Test
    fun `bez odabranog treninga pokreće se prazan trening`() {
        val session = started(shortcuts.start(null, "Trening", base))
        assertEquals("Trening", session.name)
        assertNull(session.templateId)
        assertTrue(session.exercises.isEmpty())
    }

    @Test
    fun `spremljeni trening izvan rasporeda pokreće se s vježbama, bez rasporeda`() {
        val push = store.template("Push")
        val session = started(shortcuts.start(push.id, "Trening", base))
        assertEquals("Push", session.name)
        assertEquals(push.id, session.templateId)
        assertNull(session.scheduleId)
        assertEquals(1, session.orderedExercises.size)
    }

    @Test
    fun `trening iz aktivnog rasporeda pokreće se kao trening rasporeda, pa raspored napreduje`() {
        val (schedule, templates) = store.activeSchedule()
        // B nije sljedeći (sljedeći je A), ali je u rasporedu.
        val session = started(shortcuts.start(templates[1].id, "Trening", base))
        assertEquals(schedule.id, session.scheduleId)
        store.completeFirstSet(session)
        assertIs<ShortcutFinishResult.Finished>(shortcuts.finishActive(base.plusSeconds(1800)))
        // B je odrađen u ciklusu, a sljedeći je i dalje A.
        assertEquals(templates[0].id, ScheduleEngine(store).nextWorkout(schedule)?.template?.id)
    }

    @Test
    fun `obrisan ili prazan trening javlja grešku umjesto praznog treninga`() {
        val empty = store.template("Prazan", emptyList())
        assertFailsWith<ShortcutError.TemplateUnavailable> { shortcuts.start(empty.id, "Trening", base) }
        assertFailsWith<ShortcutError.TemplateUnavailable> { shortcuts.start(UUID.randomUUID(), "Trening", base) }
        assertNull(store.activeSession())
        assertTrue(shortcuts.startableTemplates().isEmpty())
    }

    @Test
    fun `dok je trening u tijeku, novi se ne pokreće`() {
        val (_, templates) = store.activeSchedule()
        val first = started(shortcuts.start(null, "Trening", base))
        for (result in listOf(shortcuts.start(templates[0].id, "Trening", base), shortcuts.startNextScheduled(base))) {
            assertEquals(first.id, assertIs<ShortcutStartResult.AlreadyActive>(result).session.id)
        }
        assertEquals(1, store.sessions.size)
    }

    @Test
    fun `sljedeći trening iz rasporeda, a bez aktivnog rasporeda nema što pokrenuti`() {
        assertEquals(ShortcutStartResult.NothingScheduled, shortcuts.startNextScheduled(base))
        val (schedule, templates) = store.activeSchedule()
        val session = started(shortcuts.startNextScheduled(base))
        assertEquals(templates[0].id, session.templateId)
        assertEquals(schedule.id, session.scheduleId)
    }

    @Test
    fun `završavanje - bez treninga, trening na satu, trening bez završenih serija i uspjeh`() {
        assertEquals(ShortcutFinishResult.NoActiveWorkout, shortcuts.finishActive(base))

        val push = store.template("Push")
        val session = started(shortcuts.start(push.id, "Trening", base))
        assertIs<ShortcutFinishResult.NothingCompleted>(shortcuts.finishActive(base))
        assertEquals(SessionState.ACTIVE, session.state)

        session.controllingDevice = DeviceRole.WATCH
        store.completeFirstSet(session)
        assertIs<ShortcutFinishResult.LedByWatch>(shortcuts.finishActive(base))
        assertEquals(SessionState.ACTIVE, session.state)

        session.controllingDevice = DeviceRole.PHONE
        val end = base.plusSeconds(1800)
        val finished = assertIs<ShortcutFinishResult.Finished>(shortcuts.finishActive(end))
        assertEquals(session.id, finished.session.id)
        assertEquals(SessionState.FINISHED, session.state)
        assertEquals(end, assertNotNull(session.endedAt))
    }
}
