package com.brunodobric.gymapp.catalog

import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/CatalogTests/ExerciseIllustrationTests.swift i LicenseTextTests.swift.
private fun catalogJson(media: String = """, "video": "Media/x.mp4", "poster": "Media/x.jpg""""): String = """
    {
      "version": 2,
      "source": {"name": "MoveKit", "url": "https://movekit.com", "license": "MoveKit License Agreement v1.0"},
      "legacyIds": {"Old_X": "x", "Gone": null},
      "exercises": [{
        "id": "x", "name": {"en": "X", "hr": "Iks"}, "category": "legs",
        "primaryMuscles": ["quadriceps"], "secondaryMuscles": [], "equipment": "barbell", "level": "beginner",
        "mechanic": "compound", "movement": "legs", "inputType": "weightReps",
        "primaryRegions": ["quads"], "secondaryRegions": []$media
      }]
    }
""".trimIndent()

@DisplayName("Prikaz vježbe")
class ExerciseIllustrationTest {

    @Test
    @DisplayName("Klip s posterom kad su obje datoteke u buildu")
    fun videoWithPoster() {
        val exercise = assertNotNull(ExerciseCatalog.decode(catalogJson()).exercise("x"))
        assertEquals(ExerciseIllustration.Video("Media/x.mp4", "Media/x.jpg"), exercise.illustration { true })
    }

    @Test
    @DisplayName("Bez klipa ostaje poster, a bez medija nema prikaza")
    fun missingMedia() {
        val exercise = assertNotNull(ExerciseCatalog.decode(catalogJson()).exercise("x"))
        assertEquals(ExerciseIllustration.Poster("Media/x.jpg"), exercise.illustration { it.endsWith(".jpg") })
        assertEquals(ExerciseIllustration.Video("Media/x.mp4", null), exercise.illustration { it.endsWith(".mp4") })
        assertEquals(ExerciseIllustration.Unavailable, exercise.illustration { false })
        val none = ExerciseCatalog.decode(catalogJson(media = ""))
        assertEquals(ExerciseIllustration.Unavailable, none.exercises[0].illustration { true })
    }

    @Test
    @DisplayName("Privatni tekstovi se spajaju s katalogom")
    fun mergingTexts() {
        val catalog = ExerciseCatalog.decode(catalogJson())
        assertTrue(catalog.exercises[0].displayInstructions("hr").isEmpty())
        val texts = CatalogTexts.decode(
            """
            {"x": {"instructions": {"en": ["Step."], "hr": ["Korak."]}, "commonMistakes": {"en": ["Mistake."]}},
             "nepoznata": {"instructions": {}, "commonMistakes": {}}}
            """.trimIndent(),
        )
        val exercise = assertNotNull(catalog.merging(texts).exercise("x"))
        assertEquals(listOf("Korak."), exercise.displayInstructions("hr"))
        assertEquals(listOf("Step."), exercise.displayInstructions("de"))
        assertEquals(listOf("Mistake."), exercise.displayCommonMistakes("hr"))
    }

    @Test
    @DisplayName("Katalog sa starom tablicom id-jeva se učitava, a stari id se ne prepoznaje")
    fun ignoresLegacyIds() {
        val catalog = ExerciseCatalog.decode(catalogJson())
        assertEquals("x", catalog.exercise("x")?.id)
        assertNull(catalog.exercise("Old_X"))
    }

    @Test
    @DisplayName("Kodiranje i dekodiranje čuva vježbe i vrstu")
    fun roundTrip() {
        val original = ExerciseCatalog.decode(catalogJson())
        val decoded = ExerciseCatalog.decode(original.encode())
        assertEquals(original.exercises, decoded.exercises)
        assertEquals(original.source, decoded.source)
    }
}

@DisplayName("Tekst licence")
class LicenseTextTest {

    @Test
    @DisplayName("Prijelomi unutar odlomka se spajaju, a odlomci i stavke ostaju odvojeni")
    fun reflow() {
        val raw = "MIT License\n\nPermission is hereby granted,\nfree of charge.\n- first item\n- second item\n"
        val expected = "MIT License\n\nPermission is hereby granted, free of charge.\n\n- first item\n\n- second item"
        assertEquals(expected, LicenseText.reflowed(raw))
    }

    @Test
    @DisplayName("Prazan tekst daje prazan rezultat")
    fun empty() {
        assertTrue(LicenseText.reflowed("").isEmpty())
    }
}
