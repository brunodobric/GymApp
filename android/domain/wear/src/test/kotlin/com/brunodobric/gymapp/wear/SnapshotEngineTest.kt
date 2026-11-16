package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.training.RestDefaults
import com.brunodobric.gymapp.training.WorkoutError
import java.time.Instant
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

internal val base: Instant = Instant.ofEpochSecond(1_800_000_000)
internal val bench = ExerciseRef.catalog("bench", "Potisak s klupe")
internal val row = ExerciseRef.catalog("row", "Veslanje")
internal val curl = ExerciseRef.catalog("curl", "Pregib")
private val WR = ExerciseInputType.WEIGHT_REPS

internal fun plan(): PlannedWorkoutPayload = PlannedWorkoutPayload(
    templateId = UUID.randomUUID(), scheduleId = UUID.randomUUID(), name = "Pull", scheduleName = "PPL",
    exercises = listOf(
        PlannedExercisePayload(
            row, WR, restSeconds = 120,
            sets = listOf(PlannedSetPayload(SetKind.WARM_UP, weightKg = 40.0, reps = 10), PlannedSetPayload(weightKg = 60.0, reps = 8)),
        ),
        PlannedExercisePayload(
            curl, WR, supersetGroup = 3, weightStep = 2.0,
            sets = listOf(PlannedSetPayload(weightKg = 12.0, reps = 12), PlannedSetPayload(weightKg = 12.0, reps = 12)),
        ),
        PlannedExercisePayload(
            bench, WR, restSeconds = 60, supersetGroup = 3,
            sets = listOf(PlannedSetPayload(weightKg = 50.0, reps = 10), PlannedSetPayload(weightKg = 50.0, reps = 10)),
        ),
    ),
)

private val uniform90 = RestDefaults.uniform(90)

/** Redoslijed u listama nije bitan (vrijedi `orderIndex`). */
private fun normalized(snapshot: SessionSnapshot) =
    snapshot.copy(exercises = snapshot.orderedExercises.map { it.copy(sets = it.orderedSets) })

class SnapshotEngineTest {

    @Test
    fun `početak iz plana daje nove UUID-ove, isti redoslijed, vrijednosti i superset`() {
        val payload = plan()
        val snapshot = SnapshotEngine.start(payload, DeviceRole.WATCH, now = base)
        assertEquals("Pull", snapshot.name)
        assertEquals(payload.templateId, snapshot.templateId)
        assertEquals(payload.scheduleId, snapshot.scheduleId)
        assertEquals(DeviceRole.WATCH, snapshot.controllingDevice)
        assertEquals(SessionState.ACTIVE, snapshot.state)
        assertEquals(listOf(row, curl, bench), snapshot.visibleExercises.map { it.exercise })
        assertEquals(listOf(SetKind.WARM_UP, SetKind.WORKING), snapshot.exercises[0].orderedSets.map { it.kind })
        assertEquals(listOf(40.0, 60.0), snapshot.exercises[0].orderedSets.map { it.weightKg })
        assertNull(snapshot.exercises[0].supersetGroupId)
        assertNotNull(snapshot.exercises[1].supersetGroupId)
        assertEquals(snapshot.exercises[1].supersetGroupId, snapshot.exercises[2].supersetGroupId)
        val ids = snapshot.exercises.flatMap { exercise -> exercise.sets.map { it.id } } + snapshot.exercises.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertEquals(listOf(null, 2.0, null), snapshot.exercises.map { it.weightStep })
    }

    @Test
    fun `kvačica pokreće pauzu vježbe, a nepotpuna serija se ne može označiti`() {
        val engine = SnapshotEngine(SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base))
        val set = engine.snapshot.exercises[0].orderedSets[1]
        val timer = engine.completeSet(set.id, uniform90, now = base.plusSeconds(60))
        assertEquals(120.0, timer?.totalSeconds)
        assertEquals(base.plusSeconds(180), engine.snapshot.restTimerEndsAt)
        assertEquals(base.plusSeconds(60), engine.snapshot.set(set.id)?.completedAt)
        assertEquals(base.plusSeconds(60), engine.snapshot.updatedAt)

        engine.adjustRest(10, now = base.plusSeconds(70))
        assertEquals(base.plusSeconds(190), engine.snapshot.restTimerEndsAt)
        engine.cancelRest(now = base.plusSeconds(80))
        assertNull(engine.restTimer)

        val empty = engine.snapshot.exercises[0].orderedSets[0].id
        engine.updateSet(empty, base) { it.copy(reps = null) }
        assertFailsWith<WorkoutError.SetIncomplete> { engine.completeSet(empty, uniform90, now = base) }

        engine.uncompleteSet(set.id, now = base.plusSeconds(90))
        assertFalse(engine.snapshot.set(set.id)!!.isCompleted)
    }

    @Test
    fun `vježba bez vlastite pauze dobiva zadanu prema vrsti`() {
        val original = plan()
        val payload = original.copy(
            exercises = listOf(original.exercises[0].copy(restSeconds = null, isCompound = true)) + original.exercises.drop(1),
        )
        val context = WatchContextPayload(templates = listOf(payload), defaultRestSeconds = 90, compoundRestSeconds = 150)
        assertEquals(true, context.isCompound(row))
        assertNull(context.isCompound(curl))

        val engine = SnapshotEngine(SnapshotEngine.start(payload, DeviceRole.WATCH, now = base))
        val rowSet = engine.snapshot.exercises[0].orderedSets[1]
        val timer = engine.completeSet(rowSet.id, context.restDefaults, { context.isCompound(it) }, now = base)
        assertEquals(150.0, timer?.totalSeconds)
    }

    @Test
    fun `superset bez pauze nakon prve vježbe, naizmjenične serije, zatim sljedeća vježba`() {
        val engine = SnapshotEngine(SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base))
        val curlEx = engine.snapshot.exercises[1]
        val benchEx = engine.snapshot.exercises[2]

        assertEquals(curlEx.orderedSets[0].id, engine.nextSet(curlEx.id)?.second?.id)
        assertNull(engine.completeSet(curlEx.orderedSets[0].id, uniform90, now = base))
        assertEquals(benchEx.orderedSets[0].id, engine.nextSet(curlEx.id)?.second?.id)
        assertEquals(60.0, engine.completeSet(benchEx.orderedSets[0].id, uniform90, now = base)?.totalSeconds)
        assertEquals(curlEx.orderedSets[1].id, engine.nextSet(benchEx.id)?.second?.id)

        engine.completeSet(curlEx.orderedSets[1].id, uniform90, now = base)
        engine.completeSet(benchEx.orderedSets[1].id, uniform90, now = base)
        // Superset je gotov: sljedeća je prva nedovršena vježba (veslanje).
        assertEquals(engine.snapshot.exercises[0].id, engine.exerciseAfterCompleting(curlEx.id))
    }

    @Test
    fun `nova serija preuzima vrijednosti zadnje serije iste vrste`() {
        val engine = SnapshotEngine(SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base))
        val exercise = engine.snapshot.exercises[0]
        engine.updateSet(exercise.orderedSets[1].id, base) { it.copy(rpe = 8.0) }
        val added = assertNotNull(engine.addSet(exercise.id, now = base.plusSeconds(5)))
        val set = assertNotNull(engine.snapshot.set(added))
        assertEquals(2, set.orderIndex)
        assertEquals(SetKind.WORKING, set.kind)
        assertEquals(60.0, set.weightKg)
        assertEquals(8, set.reps)
        assertNull(set.rpe)
        assertFalse(set.isCompleted)
    }

    @Test
    fun `završetak briše nezavršene serije i prazne vježbe, bez serija se ne može završiti`() {
        val engine = SnapshotEngine(SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base))
        assertFailsWith<WorkoutError.NothingCompleted> { SnapshotEngine(engine.snapshot).finish(base) }

        val set = engine.snapshot.exercises[0].orderedSets[1]
        engine.completeSet(set.id, uniform90, now = base.plusSeconds(60))
        engine.finish(base.plusSeconds(1800))
        assertEquals(SessionState.FINISHED, engine.snapshot.state)
        assertEquals(base.plusSeconds(1800), engine.snapshot.endedAt)
        assertNull(engine.snapshot.restTimerEndsAt)
        assertEquals(1, engine.snapshot.exercises.size)
        assertEquals(listOf(set.id), engine.snapshot.exercises[0].sets.map { it.id })
        assertEquals(1, engine.snapshot.completedSetCount)
        assertEquals(480.0, engine.totalVolumeKg)
    }

    @Test
    fun `razlika dviju snimki kao naredbe daje istu snimku`() {
        val start = SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base)
        val engine = SnapshotEngine(start)
        val rowEx = start.exercises[0]
        engine.completeSet(rowEx.orderedSets[0].id, uniform90, now = base.plusSeconds(10))
        engine.updateSet(rowEx.orderedSets[1].id, base.plusSeconds(20)) { it.copy(weightKg = 62.5) }
        engine.addSet(rowEx.id, now = base.plusSeconds(30))

        val current = engine.snapshot
        val edited = current.copy(
            exercises = listOf(
                current.exercises[0],
                current.exercises[1].copy(isRemoved = true),
                current.exercises[2].copy(sets = current.exercises[2].sets.filter { it.orderIndex != 1 }),
                ExerciseSnapshot(orderIndex = 3, exercise = bench, inputType = ExerciseInputType.BODYWEIGHT, sets = listOf(SetSnapshot(orderIndex = 0, reps = 15))),
            ),
            notes = "Dobar dan",
        )

        val commands = SnapshotDiff.commands(start, edited)
        val applied = SnapshotDiff.apply(commands, start, base.plusSeconds(40))
        assertEquals(normalized(edited.copy(updatedAt = base.plusSeconds(40))), normalized(applied))
        assertTrue(SnapshotDiff.commands(edited, edited).isEmpty())
    }

    @Test
    fun `završetak i odbacivanje putuju kao naredbe`() {
        val start = SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base)
        val engine = SnapshotEngine(start)
        engine.completeSet(start.exercises[0].orderedSets[1].id, uniform90, now = base)
        val completed = engine.snapshot
        engine.finish(base.plusSeconds(600))

        val commands = SnapshotDiff.commands(completed, engine.snapshot)
        assertEquals(WorkoutCommand.Finish(base.plusSeconds(600)), commands.last())
        val applied = SnapshotDiff.apply(commands, completed, base.plusSeconds(601))
        assertEquals(SessionState.FINISHED, applied.state)
        assertEquals(1, applied.completedSetCount)

        // Završetak bez ijedne završene serije ne zatvara trening.
        assertEquals(SessionState.ACTIVE, SnapshotDiff.apply(listOf(WorkoutCommand.Finish(base)), start, base).state)
        assertEquals(SessionState.DISCARDED, SnapshotDiff.apply(listOf(WorkoutCommand.Discard), start, base).state)
    }

    @Test
    fun `naredba za nepostojeću seriju se preskače, a stara vježba zadržava svoje serije`() {
        val start = SnapshotEngine.start(plan(), DeviceRole.WATCH, now = base)
        val changed = start.exercises[0].copy(restSeconds = 30, sets = emptyList())
        val applied = SnapshotDiff.apply(
            listOf(WorkoutCommand.UpsertSet(UUID.randomUUID(), SetSnapshot(orderIndex = 0)), WorkoutCommand.UpsertExercise(changed)),
            start,
            base.plusSeconds(1),
        )
        assertEquals(30, applied.exercises[0].restSeconds)
        assertEquals(start.exercises[0].sets, applied.exercises[0].sets)
        assertEquals(base.plusSeconds(1), applied.updatedAt)
    }

    @Test
    fun `vrijeme se zaokružuje na milisekunde kao u protokolu`() {
        val precise = base.plusNanos(123_456_789)
        val engine = SnapshotEngine(SnapshotEngine.start(plan(), DeviceRole.WATCH, now = precise))
        assertEquals(base.plusMillis(123), engine.snapshot.startedAt)
        val decoded = WearCoding.decodeSnapshot(WearCoding.encodeSnapshot(engine.snapshot))
        assertEquals(engine.snapshot, decoded)
    }
}
