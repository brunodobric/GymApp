package com.brunodobric.gymapp.model

import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GymStoreTest {

    @Test
    fun `spremanje zapisuje samo promjene i podiže reviziju`() {
        val persistence = InMemoryPersistence()
        val store = GymStore(persistence)
        val revisions = mutableListOf<Long>()
        store.addListener { revisions += it }

        val session = store.makeSession(bench, at(1000), sets = listOf(80.0 to 8, 85.0 to 6))
        assertTrue(store.hasChanges())
        assertEquals(4, store.save()) // trening, vježba i dvije serije
        assertFalse(store.hasChanges())
        assertEquals(0, store.save())
        assertEquals(1, persistence.writeCount)

        session.orderedExercises[0].orderedSets[1].reps = 7
        assertEquals(1, store.save())
        assertEquals(listOf(1L, 2L), revisions)
    }

    @Test
    fun `odbacivanje vraća zadnje spremljeno stanje`() {
        val store = GymStore()
        val session = store.makeSession(bench, at(1000))
        store.save()

        session.name = "Promijenjeno"
        session.exercises[0].add(SetLog(1))
        store.insert(WorkoutTemplate("Novi"))
        store.rollback()

        assertEquals("Trening", store.sessions.single().name)
        assertEquals(1, store.setLogs.size)
        assertTrue(store.templates.isEmpty())
        assertFalse(store.hasChanges())
    }

    @Test
    fun `učitavanje gradi graf, a zapisi bez roditelja i nepoznati zapisi ostaju u bazi`() {
        val store = GymStore()
        store.makeSession(squat, Instant.now())
        store.save()
        val orphan = GymStore.encode(SetLog(0).apply { exerciseId = java.util.UUID.randomUUID() })
        val future = StoredRecord("FutureModel", "X", "{}")
        val broken = StoredRecord("Session", "Y", "nije json")
        val persistence = InMemoryPersistence(store.persistence.loadAll() + orphan + future + broken)

        val reloaded = GymStore(persistence)
        assertEquals(1, reloaded.sessions.size)
        assertEquals(reloaded.sessions[0], reloaded.sessionExercises.single().session)
        assertEquals(1, reloaded.setLogs.size)
        assertFalse(reloaded.hasChanges())

        reloaded.sessions[0].name = "Novo ime"
        reloaded.save()
        assertEquals(6, persistence.records.size)
    }

    @Test
    fun `postavke se stvaraju jednom i pamte nakon ponovnog učitavanja`() {
        val store = GymStore()
        store.settings().defaultRestSeconds = 120
        store.save()
        val reloaded = GymStore(store.persistence)
        assertEquals(120, reloaded.settings().defaultRestSeconds)
        assertEquals(1, reloaded.settingsRecords.size)
    }
}
