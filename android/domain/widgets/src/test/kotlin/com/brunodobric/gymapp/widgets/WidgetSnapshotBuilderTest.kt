package com.brunodobric.gymapp.widgets

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.AccentChoice
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.TemplateEngine
import com.brunodobric.gymapp.stats.BodyTracking
import com.brunodobric.gymapp.training.SetValues
import com.brunodobric.gymapp.training.WorkoutEngine
import java.time.Instant
import org.junit.jupiter.api.Test
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private val bench = ExerciseRef.catalog("bench", "Potisak s klupe")
private val row = ExerciseRef.catalog("row", "Veslanje")

// Port GymKit/Tests/WidgetSyncTests/WidgetSnapshotBuilderTests.swift.
class WidgetSnapshotBuilderTest {
    private fun newStore() = GymStore(InMemoryPersistence())

    private fun builder(store: GymStore) = WidgetSnapshotBuilder(store, recordText = { "${it.value}" })

    /** Završen trening snage s jednom vježbom. */
    private fun GymStore.addSession(name: String, at: Instant, weight: Double = 100.0): Session {
        val session = insert(Session(name, WorkoutKind.STRENGTH, at))
        session.state = SessionState.FINISHED
        session.endedAt = at.plusSeconds(3_600)
        val exercise = session.add(SessionExercise(0, bench, ExerciseInputType.WEIGHT_REPS))
        val set = exercise.add(SetLog(0, SetKind.WORKING))
        set.weightKg = weight
        set.reps = 5
        set.completedAt = at.plusSeconds(600)
        save()
        return session
    }

    @Test
    fun `prazna baza - bez treninga, tezine i rekorda, a tjedan postoji`() {
        val snapshot = builder(newStore()).make(base, utcMonday)
        assertNull(snapshot.activeWorkout)
        assertNull(snapshot.nextWorkout)
        assertNull(snapshot.bodyWeight)
        assertNull(snapshot.lastWorkout)
        assertNull(snapshot.latestRecord)
        assertEquals(0, snapshot.week?.sessions)
        assertEquals(7, snapshot.week?.days?.size)
        assertEquals(AccentChoice.BLUE.raw, snapshot.accent)
        assertEquals("kilograms", snapshot.weightUnit)
    }

    @Test
    fun `sljedeci trening rasporeda s nazivom rasporeda i vjezbama`() {
        val store = newStore()
        val templates = TemplateEngine(store)
        val template = templates.createTemplate("Push")
        templates.addExercise(bench, ExerciseInputType.WEIGHT_REPS, template)
        templates.addExercise(row, ExerciseInputType.WEIGHT_REPS, template)
        val schedules = ScheduleEngine(store)
        val schedule = schedules.createSchedule("PPL")
        schedules.addWorkout(template, schedule)

        val next = assertNotNull(builder(store).make(base, utcMonday).nextWorkout)
        assertEquals("Push", next.name)
        assertEquals("PPL", next.scheduleName)
        assertEquals(2, next.exerciseCount)
        assertEquals(listOf(bench.name, row.name), next.exercises.map { it.name })
        assertTrue(next.exercises.all { it.workingSets > 0 })
    }

    @Test
    fun `tjedan broji treninge prema cilju iz postavki`() {
        val store = newStore()
        store.settings().trainingDaysPerWeek = 3
        store.save()
        store.addSession("Legs", base.minusSeconds(3_600 * 2))
        store.addSession("Stari", base.minusSeconds(14 * DAY))

        val week = assertNotNull(builder(store).make(base, utcMonday).week)
        assertEquals(1, week.sessions)
        assertEquals(3, week.goal)
        assertEquals(1, week.days.count { it.isTrained })
        assertEquals(1, week.hardSets)
    }

    @Test
    fun `zadnji trening i najnoviji rekord`() {
        val store = newStore()
        // Rekordi traže nekoliko treninga povijesti (kalibracija), pa se težina postupno diže.
        for (index in 0 until 5) {
            store.addSession("Trening $index", base.plusSeconds((index - 10) * DAY), 100.0 + index * 5)
        }
        val snapshot = builder(store).make(base, utcMonday)
        val last = assertNotNull(snapshot.lastWorkout)
        assertEquals("Trening 4", last.name)
        assertEquals(3_600, last.durationSeconds)
        assertEquals(WidgetSnapshot.Mix.STRENGTH, last.mix)
        snapshot.latestRecord?.let { record ->
            assertEquals(bench.name, record.exercise)
            assertTrue(record.date <= base)
        }
    }

    @Test
    fun `tezina - zadnja vrijednost, promjena i tocke od najstarije`() {
        val store = newStore()
        val tracking = BodyTracking(store)
        tracking.add(BodyMeasurementKind.WEIGHT, 83.0, base.minusSeconds(40 * DAY))
        tracking.add(BodyMeasurementKind.WEIGHT, 82.4, base)

        val weight = assertNotNull(builder(store).make(base, utcMonday).bodyWeight)
        assertEquals(82.4, weight.latestKg)
        assertEquals(listOf(83.0, 82.4), weight.points)
        assertTrue(abs((weight.changeKg ?: 0.0) + 0.6) < 0.000_1)
    }

    @Test
    fun `trening u tijeku je u snimci`() {
        val store = newStore()
        WorkoutEngine(store).startSession("Pull")
        assertEquals("Pull", builder(store).make(base, utcMonday).activeWorkout?.name)
    }

    @Test
    fun `plan serija - bez ciljeva kao prosli put, s ciljevima prema predlosku, tezina iz povijesti`() {
        val previous = listOf(
            SetValues(SetKind.WARM_UP, weightKg = 40.0, reps = 10),
            SetValues(SetKind.WORKING, weightKg = 80.0, reps = 8),
            SetValues(SetKind.WORKING, weightKg = 82.5, reps = 6),
        )
        val fromHistory = WidgetSnapshotBuilder.plannedSets(previous, emptyList(), ExerciseInputType.WEIGHT_REPS)
        assertEquals(listOf(SetKind.WARM_UP, SetKind.WORKING, SetKind.WORKING), fromHistory.map { it.kind })
        assertEquals(listOf(40.0, 80.0, 82.5), fromHistory.map { it.weightKg })

        assertEquals(WorkoutEngine.DEFAULT_WORKING_SETS, WidgetSnapshotBuilder.plannedSets(emptyList(), emptyList(), ExerciseInputType.WEIGHT_REPS).size)

        val target = TemplateSet(0, SetKind.WORKING).apply {
            targetWeightKg = 90.0
            targetReps = 5
        }
        val withTargets = WidgetSnapshotBuilder.plannedSets(previous, listOf(target), ExerciseInputType.WEIGHT_REPS)
        assertEquals(listOf(SetValues(SetKind.WORKING, weightKg = 80.0, reps = 5)), withTargets)
        val firstTime = WidgetSnapshotBuilder.plannedSets(emptyList(), listOf(target), ExerciseInputType.WEIGHT_REPS)
        assertEquals(listOf(SetValues(SetKind.WORKING, weightKg = 90.0, reps = 5)), firstTime)
    }
}
