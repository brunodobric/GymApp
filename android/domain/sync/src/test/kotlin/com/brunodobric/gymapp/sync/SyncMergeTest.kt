package com.brunodobric.gymapp.sync

import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.StoredRecord
import com.brunodobric.gymapp.model.WorkoutTemplate
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Uređaj u testu: baza, zapis stanja i sinkronizacija s datotekom kao u aplikaciji. */
private class Device(name: String) {
    val store = GymStore(InMemoryPersistence())
    var ledger = SyncLedger(name)

    fun sync(file: SyncFile, now: Long, canApply: Boolean = true): Pair<SyncFile, SyncMerge.Result> {
        val result = SyncMerge.merge(store.persistedRecords(), ledger, file, now, store.activeSessionKeys(), canApply)
        store.applyExternal(result.upserts, result.deletes)
        ledger = result.ledger
        return (if (result.fileChanged) result.file else file) to result
    }
}

private fun finishedSession(store: GymStore, name: String): Session {
    val session = store.insert(Session().apply { this.name = name; stateRaw = SessionState.FINISHED.raw })
    val exercise = session.add(SessionExercise().apply { exerciseKey = "c:bench" })
    exercise.add(SetLog().apply { reps = 8 })
    store.save()
    return session
}

class SyncMergeTest {

    @Test
    fun `trening s jednog uredaja stize na drugi`() {
        val a = Device("A")
        val b = Device("B")
        finishedSession(a.store, "Push")

        var file = SyncFile()
        file = a.sync(file, now = 1_000).first
        assertEquals(3, file.entries.size)
        val (after, result) = b.sync(file, now = 2_000)

        assertEquals(3, result.received)
        assertEquals("Push", b.store.sessions.single().name)
        assertEquals(1, b.store.setLogs.size)
        assertEquals(after, file) // B nema ničega novog
    }

    @Test
    fun `novija promjena vrijedi, a ponovna sinkronizacija nista ne mijenja`() {
        val a = Device("A")
        val b = Device("B")
        val session = finishedSession(a.store, "Push")
        var file = a.sync(SyncFile(), 1_000).first
        file = b.sync(file, 2_000).first

        session.name = "Push A"
        a.store.save()
        b.store.sessions.single().name = "Push B"
        b.store.save()

        file = a.sync(file, 3_000).first
        file = b.sync(file, 4_000).first // B je promijenio kasnije
        file = a.sync(file, 5_000).first
        assertEquals("Push B", a.store.sessions.single().name)
        assertEquals("Push B", b.store.sessions.single().name)

        val (again, result) = a.sync(file, 6_000)
        assertEquals(0, result.received)
        assertFalse(result.fileChanged)
        assertEquals(file, again)
    }

    @Test
    fun `obrisan trening se brise i na drugom uredaju i ne vraca se`() {
        val a = Device("A")
        val b = Device("B")
        val session = finishedSession(a.store, "Push")
        var file = a.sync(SyncFile(), 1_000).first
        file = b.sync(file, 2_000).first

        a.store.delete(session)
        a.store.save()
        file = a.sync(file, 3_000).first
        assertTrue(file.entries.all { it.isDeleted })

        file = b.sync(file, 4_000).first
        assertTrue(b.store.sessions.isEmpty())
        assertTrue(b.store.persistedRecords().isEmpty())
        file = a.sync(file, 5_000).first
        assertTrue(a.store.sessions.isEmpty())
    }

    @Test
    fun `prvo spajanje - datoteka ima prednost za zajednicke zapise, a lokalni se dodaju`() {
        val a = Device("A")
        val session = finishedSession(a.store, "Novo ime")
        val file = a.sync(SyncFile(), 1_000).first

        // B ima stariju kopiju iste baze (vraćenu iz sigurnosne kopije) i vlastiti predložak.
        val b = Device("B")
        val old = a.store.persistedRecords().map { record ->
            if (record.type == "Session") StoredRecord(record.type, record.id, record.json.replace("Novo ime", "Staro ime")) else record
        }
        val stale = GymStore(InMemoryPersistence(old))
        b.store.applyExternal(stale.persistedRecords(), emptyList())
        b.store.insert(WorkoutTemplate("Legs"))
        b.store.save()

        val (merged, _) = b.sync(file, now = 9_000)
        assertEquals("Novo ime", b.store.session(session.id)?.name)
        assertEquals(listOf("Legs"), b.store.templates.map { it.name })
        assertTrue(merged.entries.any { it.type == "WorkoutTemplate" })

        a.sync(merged, 10_000)
        assertEquals(listOf("Legs"), a.store.templates.map { it.name })
    }

    @Test
    fun `trening u tijeku se ne salje dok ne zavrsi`() {
        val a = Device("A")
        val b = Device("B")
        val active = a.store.insert(Session().apply { name = "U tijeku" })
        active.add(SessionExercise().apply { exerciseKey = "c:bench" })
        a.store.save()

        var file = a.sync(SyncFile(), 1_000).first
        assertTrue(file.entries.isEmpty())

        active.stateRaw = SessionState.FINISHED.raw
        a.store.save()
        file = a.sync(file, 2_000).first
        assertEquals(2, file.entries.size)
        b.sync(file, 3_000)
        assertEquals("U tijeku", b.store.sessions.single().name)
    }

    @Test
    fun `promjene se odgadaju dok je uredivac otvoren`() {
        val a = Device("A")
        val b = Device("B")
        finishedSession(a.store, "Push")
        var file = a.sync(SyncFile(), 1_000).first

        val (kept, deferred) = b.sync(file, 2_000, canApply = false)
        assertEquals(3, deferred.deferred)
        assertTrue(b.store.sessions.isEmpty())
        assertFalse(b.ledger.joined)
        file = kept

        val (_, applied) = b.sync(file, 3_000)
        assertEquals(3, applied.received)
        assertEquals("Push", b.store.sessions.single().name)
        assertTrue(b.ledger.joined)
    }

    @Test
    fun `isto vrijeme - odlucuje uredaj, isto na oba uredaja`() {
        val x = SyncEntry("Session", "1", "{\"a\":1}", 5, "A")
        val y = SyncEntry("Session", "1", "{\"a\":2}", 5, "B")
        assertTrue(SyncMerge.isNewer(y, x))
        assertFalse(SyncMerge.isNewer(x, y))
    }

    @Test
    fun `datoteka - prazna, tuda i novija`() {
        assertTrue(SyncFile.decode("").entries.isEmpty())
        assertTrue(SyncFile.decode("﻿  ").entries.isEmpty())
        assertThrows<SyncException.NotSyncFile> { SyncFile.decode("{\"version\":1}") }
        assertThrows<SyncException.NotSyncFile> { SyncFile.decode("Datum;Trening") }
        assertThrows<SyncException.NewerFormat> { SyncFile.decode("{\"app\":\"Apolon\",\"format\":99}") }
        val file = SyncFile(entries = listOf(SyncEntry("Session", "1", null, 5, "A")))
        assertEquals(file, SyncFile.decode(file.encode()))
        assertNull(SyncFile.decode(file.encode()).entries.single().json)
    }

    @Test
    fun `zapis stanja se cita i pise`() {
        val ledger = SyncLedger("A", listOf(SyncEntry("Session", "1", "{}", 5, "A")), joined = true)
        assertEquals(ledger, SyncLedger.decode(ledger.encode()))
    }
}
