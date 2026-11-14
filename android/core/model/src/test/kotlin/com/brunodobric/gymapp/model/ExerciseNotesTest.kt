package com.brunodobric.gymapp.model

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ExerciseNotesTest {

    @Test
    fun `bilješka se sprema, briše praznim tekstom i daje isti JSON kao iOS`() {
        val notes = ExerciseNotes()
        notes.setNote("  Sjedalo 4, hvat širi  ", "c:bench")
        notes.setNote("Sprava 3/5", "c:a-row")
        assertEquals("Sjedalo 4, hvat širi", notes.note("c:bench"))
        assertEquals("""{"c:a-row":"Sprava 3/5","c:bench":"Sjedalo 4, hvat širi"}""", notes.raw)

        val decoded = ExerciseNotes(notes.raw)
        assertEquals(notes.raw, decoded.raw)
        decoded.setNote("   ", "c:bench")
        decoded.setNote("", "c:a-row")
        assertNull(decoded.note("c:bench"))
        assertTrue(decoded.raw.isEmpty())
    }

    @Test
    fun `neispravan zapis daje prazne bilješke`() {
        assertTrue(ExerciseNotes("nije json").raw.isEmpty())
        assertNull(ExerciseNotes("").note("c:bench"))
    }
}
