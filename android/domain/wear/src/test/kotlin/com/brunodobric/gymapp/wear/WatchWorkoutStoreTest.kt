package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.training.SetField
import java.time.Instant
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

private class FakeLink : WatchLink {
    val reliable = mutableListOf<WorkoutEvent>()
    val reachable = mutableListOf<WorkoutEvent>()
    val published = mutableListOf<SessionSnapshot?>()
    override fun sendReliably(event: WorkoutEvent) { reliable += event }
    override fun sendIfReachable(event: WorkoutEvent) { reachable += event }
    override fun publishSession(snapshot: SessionSnapshot?) { published += snapshot }

    val commands: List<WorkoutCommand> get() = reliable.mapNotNull { (it.kind as? WorkoutEvent.Kind.Commands)?.commands }.flatten()
}

private class FakeHealth(var allowed: Boolean = true, var result: HealthResult = HealthResult(320.0, 128.0)) : WatchHealth {
    var started = mutableListOf<UUID>()
    var ended = 0
    var discarded = 0
    var recovered = 0
    var endGate: CompletableDeferred<Unit>? = null
    override var isRunning = false
    override suspend fun start(sessionId: UUID, at: Instant): Boolean {
        if (!allowed) return false
        started += sessionId
        isRunning = true
        return true
    }
    override suspend fun end(at: Instant): HealthResult {
        endGate?.await()
        ended++
        isRunning = false
        return result
    }
    override fun discard() { discarded++; isRunning = false }
    override fun recover() { recovered++ }
}

private class MemoryStorage(var state: WatchStateFile? = null) : WatchStateStorage {
    override fun save(state: WatchStateFile) { this.state = WatchStateFile.decode(state.encode()) }
    override fun load(): WatchStateFile? = state
}

@OptIn(ExperimentalCoroutinesApi::class)
private class Harness(val scope: TestScope, storage: MemoryStorage = MemoryStorage()) {
    val link = FakeLink()
    val health = FakeHealth()
    val haptics = mutableListOf<Haptic>()
    val storage = storage
    val store = WatchWorkoutStore(
        link, health, storage, scope.backgroundScope, haptics = { haptics += it },
        now = { base.plusMillis(scope.testScheduler.currentTime) },
    )
    val state get() = store.state.value
    val active get() = state.active!!
}

private fun phoneSnapshot(at: Instant = base): SessionSnapshot = SnapshotEngine.start(plan(), DeviceRole.PHONE, now = at)

@OptIn(ExperimentalCoroutinesApi::class)
class WatchWorkoutStoreTest {

    @Test
    fun `trening na satu šalje snimku zajamčeno, pokreće mjerenje i ide na prvu vježbu`() = runTest {
        val h = Harness(this)
        h.store.begin(plan())
        runCurrent()
        assertTrue(h.state.isController)
        assertEquals(h.active.visibleExercises.first().id, h.state.currentExerciseId)
        val sent = h.link.reliable.single().kind as WorkoutEvent.Kind.Snapshot
        assertEquals(h.active.id, sent.snapshot.id)
        assertEquals(h.active, h.link.published.last())
        assertEquals(listOf(h.active.id), h.health.started)
        assertEquals(h.active, h.storage.state?.active)
    }

    @Test
    fun `kvačica pokreće odmor, haptika prije i na kraju, sat gasi timer`() = runTest {
        val h = Harness(this)
        h.store.begin(plan())
        h.store.completeCurrentSet()
        assertEquals(listOf(Haptic.SUCCESS), h.haptics)
        assertTrue(h.state.isResting)
        assertNotNull(h.state.restTimer)
        val total = h.state.restTimer!!.totalSeconds
        advanceTimeBy(((total - 10) * 1000).toLong() + 1)
        assertEquals(Haptic.CLICK, h.haptics.last())
        advanceTimeBy(10_001)
        assertEquals(Haptic.NOTIFICATION, h.haptics.last())
        assertFalse(h.state.isResting)
        assertNull(h.state.restTimer)
    }

    @Test
    fun `promjene se šalju jednom nakon stanke, nepotpuna serija javlja grešku`() = runTest {
        val h = Harness(this)
        h.store.begin(plan())
        val set = h.state.currentSet!!.second
        h.store.setValue(45.0, SetField.WEIGHT, set.id)
        h.store.setValue(47.5, SetField.WEIGHT, set.id)
        advanceTimeBy(WatchWorkoutStore.SEND_DELAY_MILLIS + 1)
        assertEquals(1, h.link.reachable.size)
        assertEquals(47.5, h.active.set(set.id)?.weightKg)
        // Ista vrijednost ne mijenja snimku.
        h.store.setValue(47.5, SetField.WEIGHT, set.id)
        advanceTimeBy(WatchWorkoutStore.SEND_DELAY_MILLIS + 1)
        assertEquals(1, h.link.reachable.size)

        h.store.setValue(0.0, SetField.REPS, set.id)
        h.store.completeCurrentSet()
        assertEquals(WatchError.SET_INCOMPLETE, h.state.error)
        assertEquals(Haptic.FAILURE, h.haptics.last())
    }

    @Test
    fun `superset ostaje na istoj vježbi, zadnja serija nudi završetak`() = runTest {
        val h = Harness(this)
        h.store.begin(plan())
        val row = h.active.visibleExercises[0]
        val curlEx = h.active.visibleExercises[1]
        repeat(2) { h.store.completeCurrentSet() }
        assertEquals(curlEx.id, h.state.currentExerciseId)
        // curl, bench, curl, bench: naizmjence, a prikazana vježba ostaje ista.
        repeat(3) { h.store.completeCurrentSet() }
        assertEquals(curlEx.id, h.state.currentExerciseId)
        assertFalse(h.state.showsFinishPrompt)
        h.store.completeCurrentSet()
        assertTrue(h.state.showsFinishPrompt)
        assertTrue(h.state.canMoveExercise(-1))
        assertFalse(h.state.canMoveExercise(1))
        h.store.moveExercise(-1)
        assertEquals(row.id, h.state.currentExerciseId)
    }

    @Test
    fun `završetak na satu čeka mjerenje i šalje završni zapis s pulsom`() = runTest {
        val h = Harness(this)
        h.store.begin(plan())
        runCurrent()
        assertFalse(h.store.finish(), "bez završene serije nudi se odbacivanje")
        h.store.completeCurrentSet()
        assertTrue(h.store.finish())
        runCurrent()
        val final = (h.link.reliable.last().kind as WorkoutEvent.Kind.Snapshot).snapshot
        assertEquals(SessionState.FINISHED, final.state)
        assertEquals(320.0, final.activeEnergyKilocalories)
        assertEquals(128.0, final.averageHeartRate)
        assertNull(h.state.active)
        assertEquals(1, h.state.summary?.completedSets)
        assertEquals(128.0, h.state.summary?.averageHeartRate)
        assertNull(h.storage.state?.active)
    }

    @Test
    fun `mjerenje koje ne odgovori ne zaglavi završetak`() = runTest {
        val h = Harness(this)
        h.health.endGate = CompletableDeferred()
        h.store.begin(plan())
        h.store.completeCurrentSet()
        h.store.finish()
        runCurrent()
        assertNotNull(h.state.active)
        advanceTimeBy(WatchWorkoutStore.HEALTH_END_TIMEOUT_MILLIS + 1)
        val final = (h.link.reliable.last().kind as WorkoutEvent.Kind.Snapshot).snapshot
        assertEquals(SessionState.FINISHED, final.state)
        assertNull(final.averageHeartRate)
        assertNull(h.state.active)
    }

    @Test
    fun `naredbe s mobitela mijenjaju trening koji vodi sat, završetak s mobitela zatvara ga`() = runTest {
        val h = Harness(this)
        h.store.begin(plan())
        val active = h.active
        val set = active.visibleExercises[0].orderedSets[1]
        val edited = SnapshotEngine(active).also { it.updateSet(set.id, base.plusSeconds(5)) { s -> s.copy(reps = 6) } }.snapshot
        h.store.handle(WorkoutEvent(sessionId = active.id, createdAt = base.plusSeconds(5), origin = DeviceRole.PHONE, kind = WorkoutEvent.Kind.Commands(SnapshotDiff.commands(active, edited))))
        assertEquals(6, h.active.set(set.id)?.reps)
        assertEquals(h.active, h.link.reachable.mapNotNull { (it.kind as? WorkoutEvent.Kind.Snapshot)?.snapshot }.last())

        h.store.completeCurrentSet()
        h.store.handle(WorkoutEvent(sessionId = active.id, origin = DeviceRole.PHONE, kind = WorkoutEvent.Kind.Commands(listOf(WorkoutCommand.Finish(base.plusSeconds(600))))))
        runCurrent()
        assertNull(h.state.active)
        assertEquals(SessionState.FINISHED, (h.link.reliable.last().kind as WorkoutEvent.Kind.Snapshot).snapshot.state)
    }

    @Test
    fun `trening s mobitela se zrcali, izmjene idu kao naredbe, a njegov sat ne prepisuje`() = runTest {
        val h = Harness(this)
        val phone = phoneSnapshot()
        h.store.handlePhoneSession(phone)
        assertFalse(h.state.isController)
        assertEquals(phone, h.state.active)
        advanceTimeBy(1000)
        h.store.completeCurrentSet()
        advanceTimeBy(WatchWorkoutStore.SEND_DELAY_MILLIS + 1)
        val upsert = h.link.commands.filterIsInstance<WorkoutCommand.UpsertSet>().single()
        assertNotNull(upsert.set.completedAt)
        // Starija snimka s mobitela ne vraća stanje.
        h.store.handlePhoneSession(phone)
        assertNotNull(h.active.set(upsert.set.id)?.completedAt)
        // Sat nikad ne gasi timer treninga koji vodi mobitel.
        advanceTimeBy(600_000)
        assertNotNull(h.active.restTimerEndsAt)

        // Mobitel više nema trening: zrcaljeni se zatvara.
        h.store.handlePhoneSession(null)
        assertNull(h.state.active)
    }

    @Test
    fun `trening koji vodi sat ne mijenja se snimkom s mobitela`() = runTest {
        val h = Harness(this)
        h.store.begin(plan())
        val own = h.active
        h.store.handlePhoneSession(phoneSnapshot(base.plusSeconds(10)))
        assertEquals(own.id, h.active.id)
        h.store.handlePhoneSession(null)
        assertEquals(own.id, h.active.id)
    }

    @Test
    fun `završetak zrcaljenog treninga šalje naredbu i prikazuje sažetak`() = runTest {
        val h = Harness(this)
        h.store.handlePhoneSession(phoneSnapshot())
        h.store.completeCurrentSet()
        assertTrue(h.store.finish())
        assertTrue(h.link.commands.any { it is WorkoutCommand.Finish })
        assertNotNull(h.state.summary)
        assertNull(h.state.active)
    }

    @Test
    fun `odbacivanje zrcaljenog treninga šalje naredbu, a onog na satu odbačenu snimku`() = runTest {
        val h = Harness(this)
        h.store.handlePhoneSession(phoneSnapshot())
        h.store.discard()
        assertEquals(WorkoutCommand.Discard, h.link.commands.last())
        assertNull(h.state.active)

        h.store.begin(plan())
        h.store.discard()
        assertEquals(SessionState.DISCARDED, (h.link.reliable.last().kind as WorkoutEvent.Kind.Snapshot).snapshot.state)
        assertEquals(1, h.health.discarded)
    }

    @Test
    fun `mjerenje za mobitel počinje kad stigne snimka i javlja puls na kraju`() = runTest {
        val h = Harness(this)
        h.store.phoneRequestedHealthSession()
        val phone = phoneSnapshot()
        h.store.handlePhoneSession(phone)
        runCurrent()
        assertEquals(listOf(phone.id), h.health.started)
        assertTrue(h.state.showsHealthMetrics)
        assertTrue(h.link.commands.contains(WorkoutCommand.HealthRecordingStarted))

        val finished = SnapshotEngine(phone).also {
            it.completeSet(phone.visibleExercises[0].orderedSets[0].id, WatchContextPayload.EMPTY.restDefaults, now = base.plusSeconds(30))
            it.finish(base.plusSeconds(900))
        }.snapshot
        h.store.handle(WorkoutEvent(sessionId = phone.id, origin = DeviceRole.PHONE, kind = WorkoutEvent.Kind.Snapshot(finished)))
        runCurrent()
        assertEquals(1, h.health.ended)
        assertEquals(WorkoutCommand.HealthRecorded(320.0, 128.0), h.link.commands.last())
        assertNull(h.state.active)
        assertFalse(h.state.showsHealthMetrics)
    }

    @Test
    fun `stari zahtjev za mjerenje ne pokreće mjerenje kasnijeg treninga`() = runTest {
        val h = Harness(this)
        h.store.phoneRequestedHealthSession()
        advanceTimeBy(WatchWorkoutStore.MIRROR_REQUEST_LIFETIME_SECONDS * 1000 + 1)
        h.store.handlePhoneSession(phoneSnapshot(base.plusSeconds(200)))
        runCurrent()
        assertTrue(h.health.started.isEmpty())
    }

    @Test
    fun `bez završnog zapisa mjerenje za mobitel se zatvara nakon čekanja`() = runTest {
        val h = Harness(this)
        h.store.phoneRequestedHealthSession()
        h.store.handlePhoneSession(phoneSnapshot())
        runCurrent()
        h.store.handlePhoneSession(null)
        advanceTimeBy(WatchWorkoutStore.MIRROR_FALLBACK_DELAY_MILLIS - 1000)
        assertEquals(0, h.health.ended)
        advanceTimeBy(2000)
        assertEquals(1, h.health.ended)
        assertTrue(h.link.commands.last() is WorkoutCommand.HealthRecorded)
    }

    @Test
    fun `stanje preživi ponovno pokretanje, a završen trening ide mobitelu i nestaje`() = runTest {
        val storage = MemoryStorage()
        val first = Harness(this, storage)
        first.store.handleContext(WatchContextPayload(upcoming = listOf(plan())))
        first.store.begin(plan())
        val id = first.active.id

        val second = Harness(this, storage)
        second.store.start()
        assertEquals(id, second.active.id)
        assertEquals(1, second.state.context.upcoming.size)
        assertEquals(1, second.health.recovered)

        val finished = SnapshotEngine(second.active).also { it.discard(base) }.snapshot
        storage.state = storage.state!!.copy(active = finished)
        val third = Harness(this, storage)
        third.store.start()
        assertNull(third.state.active)
        assertEquals(SessionState.DISCARDED, (third.link.reliable.single().kind as WorkoutEvent.Kind.Snapshot).snapshot.state)
    }

    @Test
    fun `štoperica upisuje trajanje prije kvačice`() = runTest {
        val h = Harness(this)
        h.store.begin(plan())
        val set = h.state.currentSet!!.second
        h.store.toggleStopwatch(set.id)
        advanceTimeBy(42_000)
        h.store.completeCurrentSet()
        assertEquals(42, h.active.set(set.id)?.durationSeconds)
        assertNull(h.state.stopwatch)
    }
}
