package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.TemplateEngine
import com.brunodobric.gymapp.planning.TemplateStarter
import com.brunodobric.gymapp.training.CardioPart
import com.brunodobric.gymapp.training.RestDefaults
import com.brunodobric.gymapp.training.SessionMix
import com.brunodobric.gymapp.training.WorkoutEngine
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

private val WR = ExerciseInputType.WEIGHT_REPS
private val bike = com.brunodobric.gymapp.model.ExerciseRef.catalog("bike", "Bicikl")

/** Trening sa sata: potisak (dvije serije, prva završena) i veslanje (dvije serije). */
internal fun sampleSnapshot(device: DeviceRole = DeviceRole.WATCH): SessionSnapshot = SessionSnapshot(
    name = "Push",
    startedAt = base,
    controllingDevice = device,
    notes = "Bilješka",
    restTimerStartedAt = base.plusSeconds(30),
    restTimerEndsAt = base.plusSeconds(120),
    updatedAt = base.plusSeconds(30),
    exercises = listOf(
        ExerciseSnapshot(
            orderIndex = 0, exercise = bench, inputType = WR, restSeconds = 90,
            sets = listOf(
                SetSnapshot(orderIndex = 0, weightKg = 60.0, reps = 8, rpe = 8.0, completedAt = base.plusSeconds(30)),
                SetSnapshot(orderIndex = 1, weightKg = 60.0, reps = 8),
            ),
        ),
        ExerciseSnapshot(
            orderIndex = 1, exercise = row, inputType = WR,
            sets = listOf(SetSnapshot(orderIndex = 0, kind = SetKind.WARM_UP, weightKg = 40.0, reps = 10), SetSnapshot(orderIndex = 1, weightKg = 50.0, reps = 10)),
        ),
    ),
)

class SessionSnapshotStoreTest {

    @Test
    fun `snimka se upisuje i čita natrag jednaka, a ponovljena ne stvara duplikate`() {
        val persistence = InMemoryPersistence()
        val store = GymStore(persistence)
        val snapshots = SessionSnapshotStore(store)
        val snapshot = sampleSnapshot()

        assertEquals(SessionSnapshotStore.Outcome.Applied(null), snapshots.apply(snapshot))
        assertEquals(SessionSnapshotStore.Outcome.Applied(SessionState.ACTIVE), snapshots.apply(snapshot))

        assertEquals(1, store.sessions.size)
        val session = store.sessions[0]
        assertEquals(2, session.exercises.size)
        assertEquals(4, session.exercises.sumOf { it.sets.size })
        assertEquals(snapshot, session.snapshot())
        assertEquals(DeviceRole.WATCH, session.controllingDevice)
        assertEquals(bench.key, session.orderedExercises[0].exerciseKey)

        // Nakon ponovnog učitavanja baze trening je isti.
        val reloaded = GymStore(persistence)
        assertEquals(snapshot, reloaded.sessions.single().snapshot())
    }

    @Test
    fun `starija snimka ne prepisuje noviju promjenu`() {
        val snapshots = SessionSnapshotStore(GymStore())
        val sample = sampleSnapshot()
        fun withSecondCompleted(at: java.time.Instant?, updated: java.time.Instant) = sample.copy(
            updatedAt = updated,
            exercises = listOf(sample.exercises[0].copy(sets = listOf(sample.exercises[0].sets[0], sample.exercises[0].sets[1].copy(completedAt = at)))) + sample.exercises.drop(1),
        )
        val newer = withSecondCompleted(base.plusSeconds(100), base.plusSeconds(100))
        snapshots.apply(newer)

        val older = withSecondCompleted(null, base.plusSeconds(50))
        assertEquals(SessionSnapshotStore.Outcome.IgnoredOlder, snapshots.apply(older))
        assertTrue(snapshots.session(newer.id)!!.orderedExercises[0].orderedSets[1].isCompleted)

        // Uređaj koji vodi trening upisuje vlastito stanje bez obzira na vrijeme.
        assertEquals(SessionSnapshotStore.Outcome.Applied(SessionState.ACTIVE), snapshots.apply(older, force = true))
        assertFalse(snapshots.session(newer.id)!!.orderedExercises[0].orderedSets[1].isCompleted)
    }

    @Test
    fun `završena snimka briše nezavršene serije, a odbačena cijeli trening`() {
        val store = GymStore()
        val snapshots = SessionSnapshotStore(store)
        val active = sampleSnapshot()
        snapshots.apply(active)

        val engine = SnapshotEngine(active)
        engine.completeSet(active.exercises[0].orderedSets[1].id, RestDefaults.uniform(90), now = base.plusSeconds(60))
        engine.finish(base.plusSeconds(1800))
        engine.recordHealth(250.0, 120.0, now = base.plusSeconds(1801))
        assertEquals(SessionSnapshotStore.Outcome.Applied(SessionState.ACTIVE), snapshots.apply(engine.snapshot))

        val session = assertNotNull(snapshots.session(active.id))
        assertEquals(SessionState.FINISHED, session.state)
        assertEquals(base.plusSeconds(1800), session.endedAt)
        assertEquals(250.0, session.activeEnergyKilocalories)
        assertEquals(120.0, session.averageHeartRate)
        assertEquals(2, session.exercises.sumOf { it.sets.size })
        assertEquals(1, session.exercises.size)
        // Isti završni zapis stigne i drugim kanalom: ništa se ne mijenja.
        assertEquals(SessionSnapshotStore.Outcome.Applied(SessionState.FINISHED), snapshots.apply(engine.snapshot))
        assertEquals(1, store.sessions.size)

        val discarded = sampleSnapshot()
        snapshots.apply(discarded)
        val gone = discarded.copy(state = SessionState.DISCARDED, updatedAt = base.plusSeconds(40))
        assertEquals(SessionSnapshotStore.Outcome.Discarded, snapshots.apply(gone))
        assertEquals(SessionState.DISCARDED, snapshots.session(discarded.id)?.state)
        assertEquals(1, snapshots.purgeDiscarded())
        assertNull(snapshots.session(discarded.id))
        assertEquals(1, store.sessions.size)
    }

    @Test
    fun `trening s mobitela u snimci i natrag kroz naredbe sa sata`() {
        val store = GymStore()
        val engine = WorkoutEngine(store)
        val session = engine.startSession("Push", now = base)
        val exercise = engine.addExercise(bench, WR, session, now = base)
        store.save()
        val snapshot = session.snapshot()
        assertEquals(DeviceRole.PHONE, snapshot.controllingDevice)
        assertEquals(WorkoutEngine.DEFAULT_WORKING_SETS, snapshot.exercises[0].sets.size)

        // Sat upiše težinu i ponavljanja i označi prvu seriju.
        val first = snapshot.exercises[0].orderedSets[0]
        val edited = snapshot.copy(
            exercises = listOf(
                snapshot.exercises[0].copy(
                    sets = snapshot.exercises[0].sets.map {
                        if (it.id == first.id) it.copy(weightKg = 70.0, reps = 5, completedAt = base.plusSeconds(30)) else it
                    },
                ),
            ),
        )
        val commands = SnapshotDiff.commands(snapshot, edited)
        val merged = SnapshotDiff.apply(commands, session.snapshot(), base.plusSeconds(31))
        SessionSnapshotStore(store).apply(merged, force = true)

        val set = exercise.orderedSets[0]
        assertEquals(70.0, set.weightKg)
        assertEquals(5, set.reps)
        assertTrue(set.isCompleted)
        assertEquals(base.plusSeconds(31), session.lastActivityAt)
        assertEquals(WorkoutEngine.DEFAULT_WORKING_SETS, exercise.sets.size)
    }

    @Test
    fun `izvještaj sata o mjerenju vrijedi i za završen trening s mobitela`() {
        val store = GymStore()
        val session = WorkoutEngine(store).startSession("Push", now = base)
        val snapshots = SessionSnapshotStore(store)

        assertFalse(snapshots.applyWatchHealth(listOf(WorkoutCommand.SetNotes("x")), session.id))
        assertFalse(session.healthRecordedByWatch)

        assertTrue(snapshots.applyWatchHealth(listOf(WorkoutCommand.HealthRecordingStarted), session.id))
        assertTrue(session.healthRecordedByWatch)

        session.state = SessionState.FINISHED
        assertTrue(snapshots.applyWatchHealth(listOf(WorkoutCommand.HealthRecorded(310.0, 128.0)), session.id))
        assertEquals(310.0, session.activeEnergyKilocalories)
        assertEquals(128.0, session.averageHeartRate)

        // Prazan izvještaj ne briše izmjereno.
        snapshots.applyWatchHealth(listOf(WorkoutCommand.HealthRecorded(null, null)), session.id)
        assertEquals(128.0, session.averageHeartRate)
    }

    @Test
    fun `izvještaj o mjerenju ne dira trening koji vodi sat ni nepoznat trening`() {
        val store = GymStore()
        val snapshots = SessionSnapshotStore(store)
        snapshots.apply(sampleSnapshot(DeviceRole.WATCH))
        val watchLed = store.sessions.single()
        assertFalse(snapshots.applyWatchHealth(listOf(WorkoutCommand.HealthRecordingStarted), watchLed.id))
        assertFalse(watchLed.healthRecordedByWatch)
        assertFalse(snapshots.applyWatchHealth(listOf(WorkoutCommand.HealthRecordingStarted), UUID.randomUUID()))
    }

    @Test
    fun `naredbe za mjerenje ne nastaju iz razlike snimki, a na snimku upisuju puls`() {
        val snapshot = sampleSnapshot(DeviceRole.PHONE)
        val edited = snapshot.copy(averageHeartRate = 140.0)
        assertFalse(SnapshotDiff.commands(snapshot, edited).any { it.isHealthReport })
        val merged = SnapshotDiff.apply(listOf(WorkoutCommand.HealthRecorded(0.0, 140.0)), snapshot, base)
        assertEquals(140.0, merged.averageHeartRate)
        assertEquals(snapshot.activeEnergyKilocalories, merged.activeEnergyKilocalories)
    }
}

class WatchContextBuilderTest {

    @Test
    fun `serije u kontekstu jednake su serijama treninga pokrenutog na mobitelu`() {
        val store = GymStore()
        // Povijest: veslanje s jednom serijom zagrijavanja i radnim serijama.
        val workout = WorkoutEngine(store)
        val past = workout.startSession("Prije", now = base)
        val pastRow = workout.addExercise(row, WR, past, now = base)
        workout.addSet(pastRow, SetKind.WARM_UP, now = base)
        pastRow.orderedSets.forEachIndexed { index, set ->
            set.weightKg = 50.0 + index * 5
            set.reps = 10 - index
            workout.completeSet(set, 90, base)
        }
        workout.finishSession(past, now = base.plusSeconds(600))

        // Predložak: veslanje bez ciljeva i potisak s ciljevima (2 serije, druga s 85 kg).
        val templates = TemplateEngine(store)
        val template = templates.createTemplate("Pull")
        templates.addExercise(row, WR, template)
        val benchEx = templates.addExercise(bench, WR, template, setCount = 0)
        templates.setTargets(templates.addSet(benchEx), weightKg = null, reps = 8)
        templates.setTargets(templates.addSet(benchEx), weightKg = 85.0, reps = null)

        val later = base.plusSeconds(3600)
        val payload = WatchContextBuilder(store).make(later)
        val planned = assertNotNull(payload.templates.firstOrNull { it.templateId == template.id })
        assertEquals(listOf(row, bench), planned.exercises.map { it.exercise })

        // Isti trening pokrenut na mobitelu.
        val started = TemplateStarter(store).start(template, later)
        val startedSets = started.orderedExercises.map { exercise ->
            exercise.orderedSets.map { PlannedSetPayload(it.kind, it.weightKg, it.reps, it.extraWeightKg, it.durationSeconds, it.distanceMeters) }
        }
        assertEquals(startedSets, planned.exercises.map { it.sets })
        assertEquals("kilograms", payload.weightUnit)
        assertEquals(90, payload.defaultRestSeconds)
        assertEquals("steel", payload.accent)
        // "Prošli put" za sat: završene serije zadnjeg izvođenja; potisak još nije odrađen.
        assertEquals(pastRow.orderedSets.map { it.weightKg }, planned.exercises[0].previous.map { it.weightKg })
        assertEquals(emptyList(), planned.exercises[1].previous)
        assertEquals(listOf(false, false), planned.exercises.map { it.isCardio })

        val withCardio = WatchContextBuilder(store, isCardio = { it == row.key }).make(later)
        val cardioPlan = assertNotNull(withCardio.templates.firstOrNull { it.templateId == template.id })
        assertEquals(listOf(true, false), cardioPlan.exercises.map { it.isCardio })
        assertEquals(SessionMix.MIXED, cardioPlan.mix)
    }

    @Test
    fun `sljedeći trening rasporeda je u kontekstu s nazivom rasporeda i supersetom`() {
        val store = GymStore()
        val templates = TemplateEngine(store)
        val template = templates.createTemplate("Push")
        val first = templates.addExercise(bench, WR, template)
        val second = templates.addExercise(row, WR, template)
        templates.makeSuperset(listOf(first, second), template)
        val schedules = ScheduleEngine(store)
        val schedule = schedules.createSchedule("PPL")
        schedules.addWorkout(template, schedule)

        val payload = WatchContextBuilder(store).make(base)
        val next = assertNotNull(payload.upcoming.firstOrNull())
        assertEquals("Push", next.name)
        assertEquals("PPL", next.scheduleName)
        assertEquals(schedule.id, next.scheduleId)
        assertEquals(listOf(0, 0), next.exercises.map { it.supersetGroup })

        val started = SnapshotEngine.start(next, DeviceRole.WATCH, now = base)
        assertNotNull(started.exercises[0].supersetGroupId)
        assertEquals(started.exercises[0].supersetGroupId, started.exercises[1].supersetGroupId)

        // Kontekst preživi pakiranje za Data Layer.
        assertEquals(payload, WearCoding.decodeContext(WearCoding.encodeContext(payload)))
    }
}

class WatchPlanInfoTest {
    private fun cardioPlan() = PlannedWorkoutPayload(
        name = "Snaga i bicikl",
        exercises = listOf(
            PlannedExercisePayload(
                bench, WR, restSeconds = 120,
                sets = listOf(PlannedSetPayload(SetKind.WARM_UP, 40.0, 10), PlannedSetPayload(weightKg = 80.0, reps = 8), PlannedSetPayload(weightKg = 80.0, reps = 8)),
                previous = listOf(PlannedSetPayload(SetKind.WARM_UP, 40.0, 10), PlannedSetPayload(weightKg = 77.5, reps = 8), PlannedSetPayload(weightKg = 80.0, reps = 7)),
                isCompound = true,
            ),
            PlannedExercisePayload(
                bike, ExerciseInputType.DURATION_DISTANCE,
                sets = listOf(PlannedSetPayload(durationSeconds = 900)),
                isCardio = true,
            ),
        ),
    )

    @Test
    fun `vrsta treninga iz vježbi`() {
        assertEquals(SessionMix.MIXED, cardioPlan().mix)
        assertEquals(SessionMix.STRENGTH, PlannedWorkoutPayload(name = "Prazan").mix)
        assertEquals(SessionMix.CARDIO, cardioPlan().copy(exercises = cardioPlan().exercises.drop(1)).mix)
    }

    @Test
    fun `procjena trajanja s radom, odmorom i prijelazom, zaokruženo na 5 minuta`() {
        // Potisak: 3 × 45 s rada i 2 × 120 s odmora; prijelaz 60 s; bicikl 900 s. Ukupno 1335 s ≈ 22 min → 20.
        assertEquals(20, cardioPlan().estimatedMinutes(RestDefaults.uniform(90)))
        assertNull(PlannedWorkoutPayload(name = "Prazan").estimatedMinutes(RestDefaults.uniform(90)))
        // Bez vlastite pauze složena vježba odmara 150 s: 1395 s ≈ 23 min → 25.
        val noRest = cardioPlan().copy(exercises = listOf(cardioPlan().exercises[0].copy(restSeconds = null)) + cardioPlan().exercises.drop(1))
        assertEquals(25, noRest.estimatedMinutes(RestDefaults(150, 90)))
    }

    @Test
    fun `prošli put po mjestu serije, a iznad broja prošlih zadnja`() {
        val context = WatchContextPayload(templates = listOf(cardioPlan()))
        assertEquals(77.5, context.previousSet(bench, SetKind.WORKING, 0)?.weightKg)
        assertEquals(7, context.previousSet(bench, SetKind.WORKING, 1)?.reps)
        assertEquals(80.0, context.previousSet(bench, SetKind.WORKING, 5)?.weightKg)
        assertEquals(40.0, context.previousSet(bench, SetKind.WARM_UP, 0)?.weightKg)
        assertNull(context.previousSet(bike, SetKind.WORKING, 0))
        assertTrue(context.isCardio(bike))
        assertFalse(context.isCardio(bench))
    }

    @Test
    fun `broj serije - radne 1, 2, zagrijavanje bez broja`() {
        val exercise = SnapshotEngine.start(cardioPlan(), DeviceRole.WATCH, now = base).visibleExercises[0]
        val sets = exercise.orderedSets
        assertNull(exercise.workingNumber(sets[0].id))
        assertEquals(0, exercise.position(sets[0].id))
        assertEquals(1, exercise.workingNumber(sets[1].id))
        assertEquals(2, exercise.workingNumber(sets[2].id))
        assertEquals(1, exercise.position(sets[2].id))
    }

    @Test
    fun `sažetak s kardio dijelom, vrstom i serijama bez kardija`() {
        val engine = SnapshotEngine(SnapshotEngine.start(cardioPlan(), DeviceRole.WATCH, now = base))
        val isCardio: (com.brunodobric.gymapp.model.ExerciseRef) -> Boolean = { it == bike }
        val benchSets = engine.snapshot.visibleExercises[0].orderedSets
        engine.completeSet(benchSets[1].id, RestDefaults.uniform(90), now = base.plusSeconds(60))
        assertEquals(SessionMix.STRENGTH, engine.snapshot.mix(isCardio))
        assertNull(engine.snapshot.cardioPart(isCardio))

        val bikeSet = engine.snapshot.visibleExercises[1].orderedSets[0]
        engine.updateSet(bikeSet.id) { it.copy(distanceMeters = 5_000.0) }
        engine.completeSet(bikeSet.id, RestDefaults.uniform(90), now = base.plusSeconds(1_200))
        assertEquals(SessionMix.MIXED, engine.snapshot.mix(isCardio))
        assertEquals(CardioPart(900, 5_000.0), engine.snapshot.cardioPart(isCardio))
        assertEquals(1, engine.snapshot.strengthSetCount(isCardio))
        assertEquals(1, engine.snapshot.completedExerciseCount)
    }
}

class WorkoutEventTest {

    @Test
    fun `snimka i naredbe prežive pakiranje i raspakiravanje`() {
        val snapshot = sampleSnapshot()
        val event = WorkoutEvent(sessionId = snapshot.id, createdAt = base, origin = DeviceRole.WATCH, kind = WorkoutEvent.Kind.Snapshot(snapshot))
        assertEquals(event, WorkoutEvent.decode(event.encode()))

        val commands = WorkoutEvent(
            createdAt = base,
            origin = DeviceRole.PHONE,
            kind = WorkoutEvent.Kind.Commands(
                listOf(
                    WorkoutCommand.UpsertSet(snapshot.exercises[0].id, snapshot.exercises[0].sets[1]),
                    WorkoutCommand.DeleteSet(UUID.randomUUID()),
                    WorkoutCommand.UpsertExercise(snapshot.exercises[1]),
                    WorkoutCommand.DeleteExercise(UUID.randomUUID()),
                    WorkoutCommand.SetRestTimer(base, base.plusSeconds(90)),
                    WorkoutCommand.SetRestTimer(null, null),
                    WorkoutCommand.SetNotes("Dobar"),
                    WorkoutCommand.Finish(base),
                    WorkoutCommand.Discard,
                    WorkoutCommand.HealthRecordingStarted,
                    WorkoutCommand.HealthRecorded(200.0, null),
                ),
            ),
        )
        assertEquals(commands, WorkoutEvent.decode(commands.encode()))
    }

    @Test
    fun `neispravan sadržaj daje null`() {
        assertNull(WorkoutEvent.decode(byteArrayOf(1, 2, 3)))
        assertNull(WearCoding.decodeContext(ByteArray(0)))
    }

    @Test
    fun `isti događaj obrađuje se samo jednom`() {
        val event = WorkoutEvent(origin = DeviceRole.WATCH, kind = WorkoutEvent.Kind.Commands(emptyList()))
        val deduplicator = WorkoutEventDeduplicator()
        assertTrue(deduplicator.accept(event))
        assertFalse(deduplicator.accept(event))
        assertTrue(deduplicator.accept(event.copy(id = UUID.randomUUID())))
    }
}
