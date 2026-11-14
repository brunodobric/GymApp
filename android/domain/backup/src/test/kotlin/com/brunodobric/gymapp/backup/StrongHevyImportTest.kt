package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.units.WeightUnit
import org.junit.jupiter.api.Test
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Uvoz iz izvoza aplikacija Strong i Hevy, isti fixturei kao testovi na iOS-u.
private fun fixture(name: String): String =
    File(System.getProperty("fixtures.dir")).resolve(name).readText(Charsets.UTF_8)

class StrongHevyImportTest {

    @Test
    fun `strong - treninzi, zagrijavanje, oprema iz naziva i vrste unosa`() {
        val text = fixture("strong.csv")
        assertTrue(ForeignWorkoutsCsv.matches(text))
        val workouts = ForeignWorkoutsCsv.parse(text, ZoneOffset.UTC)
        assertEquals(listOf("Push", "Legs"), workouts.map { it.name })
        val push = workouts[0]
        assertEquals(Instant.ofEpochSecond(1_768_465_800), push.startedAt)
        assertEquals(3900, push.durationSeconds)
        assertEquals("Dobar dan", push.notes)
        assertEquals(listOf("Bench Press", "Pull Up", "Plank"), push.exercises.map { it.name })
        assertEquals("Barbell", push.exercises[0].equipment)
        assertEquals(listOf(true, false, false), push.exercises[0].sets.map { it.isWarmUp })
        assertEquals(listOf(40.0, 80.0, 80.0), push.exercises[0].sets.map { it.weightKg })
        assertEquals("", push.exercises[0].note)
        assertEquals(
            listOf(ForeignWorkoutsCsv.Kind.WEIGHT_REPS, ForeignWorkoutsCsv.Kind.REPS, ForeignWorkoutsCsv.Kind.DURATION),
            push.exercises.map { it.kind },
        )
        assertEquals(60, push.exercises[2].sets[0].durationSeconds)
        val legs = workouts[1]
        assertEquals(2700, legs.durationSeconds)
        assertEquals(ForeignWorkoutsCsv.Kind.DURATION_DISTANCE, legs.exercises[1].kind)
        assertEquals(5000.0, legs.exercises[1].sets[0].distanceMeters)
    }

    @Test
    fun `strong bez jedinice u stupcu uzima jedinicu iz postavki`() {
        val workouts = ForeignWorkoutsCsv.parse(fixture("strong.csv"), ZoneOffset.UTC, WeightUnit.POUNDS)
        val weight = assertNotNull(workouts[0].exercises[0].sets[1].weightKg)
        assertEquals(80 * 0.45359237, weight, 1e-9)
    }

    @Test
    fun `hevy - trajanje iz početka i kraja, bilješke i zagrijavanje`() {
        val text = fixture("hevy.csv")
        assertTrue(ForeignWorkoutsCsv.matches(text))
        val workouts = ForeignWorkoutsCsv.parse(text, ZoneOffset.UTC)
        assertEquals(1, workouts.size)
        val push = workouts[0]
        assertEquals(Instant.ofEpochSecond(1_768_465_800), push.startedAt)
        assertEquals(3900, push.durationSeconds)
        assertEquals("Dobar dan", push.notes)
        assertEquals(listOf("Bench Press", "Lateral Raise"), push.exercises.map { it.name })
        assertEquals(listOf("Barbell", "Dumbbell"), push.exercises.map { it.equipment })
        assertEquals("Sjedalo 4", push.exercises[0].note)
        assertEquals(listOf(true, false, false), push.exercises[0].sets.map { it.isWarmUp })
        assertEquals(listOf(10, 8, 7), push.exercises[0].sets.map { it.reps })
        assertEquals("Dobar dan\nBench Press: Sjedalo 4", ForeignWorkoutImport.notes(push))
    }

    @Test
    fun `pomoćni dijelovi - naziv s opremom i trajanje`() {
        assertEquals("Bench Press" to "Barbell", StrongHevyCsv.splitName("Bench Press (Barbell)"))
        assertEquals("Pull Up" to "", StrongHevyCsv.splitName("Pull Up"))
        assertEquals(3900, StrongHevyCsv.parseDuration("1h 5m"))
        assertEquals(2700, StrongHevyCsv.parseDuration("45m"))
        assertEquals(90, StrongHevyCsv.parseDuration("90"))
        assertNull(StrongHevyCsv.parseDuration(""))
        assertFalse(StrongHevyCsv.matches("Date;Nešto\n1;2"))
    }
}
