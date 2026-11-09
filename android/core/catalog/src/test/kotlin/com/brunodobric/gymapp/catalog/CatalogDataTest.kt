package com.brunodobric.gymapp.catalog

import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import java.io.File
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/CatalogTests/CatalogTests.swift (stvarni katalog).
@DisplayName("Katalog")
class CatalogDataTest {

    private val catalog: ExerciseCatalog by lazy {
        val directory = File(System.getProperty("catalog.dir"))
        ExerciseCatalog.decode(directory.resolve("catalog.json").readText())
    }

    @Test
    @DisplayName("catalog.json se učitava i ima sve MoveKit vježbe")
    fun loads() {
        assertEquals(582, catalog.exercises.size)
        assertEquals("MoveKit", catalog.source.name)
    }

    @Test
    @DisplayName("Id-evi su jedinstveni, svaka vježba ima hrvatski naziv, mišić, klip i poster")
    fun integrity() {
        assertEquals(catalog.exercises.size, catalog.exercises.map { it.id }.toSet().size)
        for (exercise in catalog.exercises) {
            assertNotNull(exercise.name["en"], "${exercise.id}: nema engleskog naziva")
            assertNotNull(exercise.name["hr"], "${exercise.id}: nema hrvatskog naziva")
            assertTrue(exercise.primaryMuscles.isNotEmpty(), "${exercise.id}: nema primarnog mišića")
            assertTrue(exercise.primaryRegions.isNotEmpty(), "${exercise.id}: nema regije za mapu mišića")
            assertEquals("Media/${exercise.id}.mp4", exercise.video)
            assertEquals("Media/${exercise.id}.jpg", exercise.poster)
        }
    }

    @Test
    @DisplayName("Javni katalog ne sadrži MoveKit tekstove")
    fun noLicensedTexts() {
        for (exercise in catalog.exercises) {
            assertTrue(exercise.instructions.isEmpty(), "${exercise.id}: upute ne smiju biti u javnom katalogu")
            assertTrue(exercise.commonMistakes.isEmpty(), "${exercise.id}: česte greške ne smiju biti u javnom katalogu")
        }
    }

    @Test
    @DisplayName("Svaka vježba ima vrstu: kardio točno u kategoriji kardio")
    fun kinds() {
        for (exercise in catalog.exercises) {
            assertEquals(exercise.category == ExerciseCategory.CARDIO, exercise.kind == ExerciseKind.CARDIO, exercise.id)
        }
        val counts = catalog.exercises.groupingBy { it.kind }.eachCount()
        assertEquals(
            mapOf(ExerciseKind.STRENGTH to 502, ExerciseKind.CARDIO to 38, ExerciseKind.WARM_UP to 26, ExerciseKind.STRETCHING to 16),
            counts,
        )
        assertEquals(ExerciseKind.STRETCHING, catalog.exercise("worlds-greatest-stretch")?.kind)
        assertEquals(ExerciseKind.WARM_UP, catalog.exercise("arm-circles-front-back")?.kind)
        assertEquals(ExerciseKind.STRENGTH, catalog.exercise("turkish-get-up")?.kind)
        assertEquals(ExerciseKind.CARDIO, catalog.exercise("treadmill-run")?.kind)
    }

    @Test
    @DisplayName("Stariji catalog.json bez vrste: kardio po kategoriji, inače snaga")
    fun kindFallback() {
        val json = """
            {"version": 2, "source": {"name": "MoveKit", "url": "https://movekit.com", "license": "L"}, "exercises": [
              {"id": "run", "name": {"en": "Run"}, "category": "cardio", "primaryMuscles": ["quadriceps"], "secondaryMuscles": [],
               "equipment": "bodyweight", "level": "beginner", "inputType": "durationDistance", "primaryRegions": [], "secondaryRegions": []},
              {"id": "press", "name": {"en": "Press"}, "category": "chest", "primaryMuscles": ["chest"], "secondaryMuscles": [],
               "equipment": "barbell", "level": "beginner", "inputType": "weightReps", "primaryRegions": [], "secondaryRegions": []}
            ]}
        """.trimIndent()
        val old = ExerciseCatalog.decode(json)
        assertEquals(ExerciseKind.CARDIO, old.exercise("run")?.kind)
        assertEquals(ExerciseKind.STRENGTH, old.exercise("press")?.kind)
    }

    @Test
    @DisplayName("Kartica vrste: odabrane vježbe postoje i odgovaraju vrsti, bez slike nema sličica")
    fun featured() {
        for (kind in ExerciseKind.entries) {
            assertEquals(featuredIds.getValue(kind), catalog.featured(kind) { true }.map { it.id })
            assertTrue(catalog.featured(kind) { false }.isEmpty())
        }
        val withoutSquat = catalog.featured(ExerciseKind.STRENGTH) { it.id != "barbell-squat" }
        assertEquals(4, withoutSquat.size)
        assertTrue(withoutSquat.all { it.kind == ExerciseKind.STRENGTH && it.id != "barbell-squat" })
        assertEquals(16, catalog.featured(ExerciseKind.STRETCHING, count = 20) { true }.size)
    }

    @Test
    @DisplayName("Filter po vrsti; vlastita vježba dobiva vrstu po kategoriji; poništavanje vraća početni filter")
    fun kindFilter() {
        val custom = ExerciseSummary(
            ExerciseSummary.Source.Custom(UUID.randomUUID()), "Moje trčanje", category = ExerciseCategory.CARDIO,
            muscles = emptyList(), equipment = null, isArchived = false,
        )
        assertEquals(ExerciseKind.CARDIO, custom.kind)
        val archived = ExerciseSummary(
            ExerciseSummary.Source.Custom(UUID.randomUUID()), "Stara", category = ExerciseCategory.CARDIO,
            muscles = emptyList(), equipment = null, isArchived = true,
        )
        val counts = ExerciseSearch.countsByKind(catalog.summaries("hr") + listOf(custom, archived))
        assertEquals(
            mapOf(ExerciseKind.STRENGTH to 502, ExerciseKind.CARDIO to 39, ExerciseKind.WARM_UP to 26, ExerciseKind.STRETCHING to 16),
            counts,
        )
        var filter = ExerciseFilter(kinds = setOf(ExerciseKind.CARDIO), categories = setOf(ExerciseCategory.CARDIO))
        assertFalse(ExerciseFilter(kinds = setOf(ExerciseKind.CARDIO)).isActive)
        val result = ExerciseSearch.apply(filter, catalog.summaries("hr") + custom)
        assertEquals(39, result.size)
        assertTrue(result.all { it.kind == ExerciseKind.CARDIO })
        val base = ExerciseFilter(kinds = setOf(ExerciseKind.CARDIO))
        assertTrue(filter.differs(base))
        filter = filter.copy(query = "trc").reset(base)
        assertTrue(filter.categories.isEmpty() && filter.kinds == setOf(ExerciseKind.CARDIO) && filter.query == "trc")
        assertFalse(filter.differs(base))
        val onlyCustom = ExerciseFilter(origin = ExerciseFilter.Origin.CUSTOM)
        assertTrue(!onlyCustom.differs(onlyCustom) && onlyCustom.differs(ExerciseFilter()))
    }

    @Test
    @DisplayName("Prikaz vraća engleski kad prijevoda nema")
    fun languageFallback() {
        val exercise = assertNotNull(catalog.exercise("push-up"))
        assertEquals("Push Up", exercise.displayName("en"))
        assertEquals("Sklekovi", exercise.displayName("hr"))
        assertEquals("Push Up", exercise.displayName("de"))
        assertEquals(ExerciseInputType.BODYWEIGHT, exercise.inputType)
        assertNull(catalog.exercise("ne-postoji"))
    }

    @Test
    @DisplayName("Pretraga na stvarnom katalogu pronalazi očekivane vježbe")
    fun realSearch() {
        val summaries = catalog.summaries("hr")
        assertTrue(ExerciseSearch.apply(ExerciseFilter(query = "cucanj"), summaries).any { it.id == "c:barbell-squat" })
        assertTrue(ExerciseSearch.apply(ExerciseFilter(query = "bench press"), summaries).any { it.id == "c:barbell-bench-press" })
    }
}
