package com.brunodobric.gymapp.model

import java.io.File
import java.nio.file.Files
import java.time.Instant
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StoreRecoveryTest {

    @Test
    fun `baza i dnevnik premjestaju se u novu mapu, a ostale datoteke ostaju`() {
        val directory = Files.createTempDirectory("store").toFile()
        val database = File(directory, "gym.db").apply { writeText("baza") }
        File(directory, "gym.db-journal").writeText("dnevnik")
        val other = File(directory, "health.json").apply { writeText("{}") }

        val moved = StoreRecovery.moveAside(database, Instant.ofEpochSecond(1_800_000_000))

        assertEquals("Neotvorena baza 1800000000", moved.name)
        assertEquals(directory.absoluteFile, moved.parentFile)
        assertFalse(database.exists())
        assertFalse(File(directory, "gym.db-journal").exists())
        assertEquals("baza", File(moved, "gym.db").readText())
        assertEquals("dnevnik", File(moved, "gym.db-journal").readText())
        assertTrue(other.exists())
        directory.deleteRecursively()
    }

    @Test
    fun `bez datoteke baze nastaje samo prazna mapa`() {
        val directory = Files.createTempDirectory("store").toFile()
        val moved = StoreRecovery.moveAside(File(directory, "gym.db"), Instant.ofEpochSecond(5))
        assertTrue(moved.isDirectory)
        assertEquals(0, moved.listFiles()?.size)
        directory.deleteRecursively()
    }
}
