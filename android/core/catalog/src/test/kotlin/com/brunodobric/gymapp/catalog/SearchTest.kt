package com.brunodobric.gymapp.catalog

import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import java.util.Locale
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// Port GymKit/Tests/CatalogTests/CatalogTests.swift (pretraga).
private fun exercise(
    id: String,
    hr: String?,
    en: String,
    category: ExerciseCategory = ExerciseCategory.CHEST,
    muscles: List<Muscle> = listOf(Muscle.CHEST),
    equipment: Equipment = Equipment.BARBELL,
) = ExerciseSummary(
    source = ExerciseSummary.Source.Catalog(id),
    name = hr ?: en,
    alternativeNames = listOf(en),
    category = category,
    muscles = muscles,
    equipment = equipment,
    isArchived = false,
)

private val sample = listOf(
    exercise("squat", "Čučanj sa šipkom", "Barbell Squat", ExerciseCategory.LEGS, listOf(Muscle.QUADRICEPS)),
    exercise("bench", "Potisak šipkom s klupe", "Barbell Bench Press"),
    exercise("curl", "Pregib bučicama", "Dumbbell Curl", ExerciseCategory.ARMS, listOf(Muscle.BICEPS), Equipment.DUMBBELL),
    exercise("row", "Veslanje šipkom", "Barbell Row", ExerciseCategory.BACK, listOf(Muscle.LATS)),
    exercise("dead", "Mrtvo dizanje", "Deadlift", ExerciseCategory.BACK, listOf(Muscle.LOWER_BACK)),
)

private fun ids(filter: ExerciseFilter, items: List<ExerciseSummary> = sample, labels: ExerciseSearchLabels = ExerciseSearchLabels.NONE) =
    ExerciseSearch.apply(filter, items, labels).map { it.id }

@DisplayName("Pretraga kataloga")
class SearchTest {

    @Test
    @DisplayName("Pretraga ne razlikuje velika slova ni dijakritike")
    fun diacritics() {
        assertEquals(listOf("c:squat"), ids(ExerciseFilter(query = "cucanj")))
        assertEquals(listOf("c:squat"), ids(ExerciseFilter(query = "ČUČANJ")))
    }

    @Test
    @DisplayName("Đ se pretražuje kao d")
    fun crossedD() {
        assertEquals("durdica", ExerciseSearch.normalize("Đurđica"))
    }

    @Test
    @DisplayName("Pronalazi i po engleskom nazivu")
    fun englishName() {
        assertEquals(listOf("c:bench"), ids(ExerciseFilter(query = "bench")))
    }

    @Test
    @DisplayName("Sve riječi upita moraju postojati, bilo kojim redoslijedom")
    fun allTokens() {
        assertEquals(listOf("c:bench"), ids(ExerciseFilter(query = "šipkom potisak")))
        assertTrue(ids(ExerciseFilter(query = "šipkom xyz")).isEmpty())
    }

    @Test
    @DisplayName("Pronalazi po opremi, mišiću i kategoriji, a vježbe s upitom u nazivu idu prve")
    fun labels() {
        val labels = ExerciseSearchLabels(
            category = { if (it == ExerciseCategory.BACK) "Leđa" else "Kategorija" },
            muscle = { if (it == Muscle.BICEPS) "Biceps" else "Mišić" },
            equipment = { if (it == Equipment.DUMBBELL) "Bučice" else "Šipka" },
        )
        assertEquals(listOf("c:curl"), ids(ExerciseFilter(query = "bucice"), labels = labels))
        assertEquals(listOf("c:curl"), ids(ExerciseFilter(query = "biceps"), labels = labels))
        assertEquals(listOf("c:dead", "c:row"), ids(ExerciseFilter(query = "leđa šipka"), labels = labels))
        // "Šipka" je oprema svih osim pregiba, ali vježbe sa "šipkom" u nazivu idu ispred mrtvog dizanja.
        assertEquals("c:dead", ids(ExerciseFilter(query = "sipk"), labels = labels).last())
        // Bez naziva pretraga ostaje samo po nazivu vježbe.
        assertTrue(ids(ExerciseFilter(query = "bucice")).isEmpty())
    }

    @Test
    @DisplayName("Nazivi koji počinju upitom idu prvi")
    fun relevanceOrder() {
        assertEquals(setOf("c:squat", "c:bench", "c:row"), ids(ExerciseFilter(query = "sip")).toSet())
        assertEquals(listOf("c:dead"), ids(ExerciseFilter(query = "mrtvo")))
    }

    @Test
    @DisplayName("Bez upita rezultat je abecedni")
    fun alphabetical() {
        val names = ExerciseSearch.apply(ExerciseFilter(), sample, locale = Locale.forLanguageTag("hr")).map { it.name }
        assertEquals(names.sortedWith(NaturalOrder(Locale.forLanguageTag("hr"))), names)
        assertEquals(sample.size, names.size)
        assertEquals("Čučanj sa šipkom", names.first())
    }

    @Test
    @DisplayName("Brojevi u nazivu idu po vrijednosti")
    fun naturalNumbers() {
        val order = NaturalOrder(Locale.forLanguageTag("hr"))
        assertEquals(listOf("Vježba 2", "Vježba 10", "vježba 11"), listOf("Vježba 10", "vježba 11", "Vježba 2").sortedWith(order))
    }

    @Test
    @DisplayName("Filteri se kombiniraju")
    fun filters() {
        assertEquals(setOf("c:row", "c:dead"), ids(ExerciseFilter(categories = setOf(ExerciseCategory.BACK))).toSet())
        assertEquals(
            listOf("c:row"),
            ids(ExerciseFilter(categories = setOf(ExerciseCategory.BACK), muscles = setOf(Muscle.LATS))),
        )
        val equipment = ExerciseFilter(equipment = setOf(Equipment.DUMBBELL))
        assertEquals(listOf("c:curl"), ids(equipment))
        assertTrue(equipment.isActive)
    }

    @Test
    @DisplayName("Vlastite i službene vježbe te arhiva")
    fun originAndArchive() {
        val custom = ExerciseSummary(
            ExerciseSummary.Source.Custom(UUID.randomUUID()), "Moja vježba", category = ExerciseCategory.CORE,
            muscles = listOf(Muscle.ABDOMINALS), equipment = Equipment.BODYWEIGHT, isArchived = false,
        )
        val archived = ExerciseSummary(
            ExerciseSummary.Source.Custom(UUID.randomUUID()), "Stara vježba", category = ExerciseCategory.CORE,
            muscles = listOf(Muscle.ABDOMINALS), equipment = Equipment.BODYWEIGHT, isArchived = true,
        )
        val all = sample + listOf(custom, archived)
        assertFalse(archived.id in ids(ExerciseFilter(), all))
        assertTrue(archived.id in ids(ExerciseFilter(includeArchived = true), all))
        assertEquals(listOf(custom.id), ids(ExerciseFilter(origin = ExerciseFilter.Origin.CUSTOM), all))
        assertEquals(sample.size, ids(ExerciseFilter(origin = ExerciseFilter.Origin.OFFICIAL), all).size)
    }

    @Test
    @DisplayName("Id vlastite vježbe ima UUID velikim slovima, kao na iOS-u")
    fun customIdUppercase() {
        val uuid = UUID.fromString("0f8fad5b-d9cb-469f-a165-70867728950e")
        val custom = ExerciseSummary(
            ExerciseSummary.Source.Custom(uuid), "X", category = null, muscles = emptyList(), equipment = null, isArchived = false,
        )
        assertEquals("u:0F8FAD5B-D9CB-469F-A165-70867728950E", custom.id)
    }

    @Test
    @DisplayName("Odabrane vježbe idu na vrh pretrage redom odabira, i kad ne odgovaraju upitu")
    fun pinnedSelection() {
        val results = ExerciseSearch.apply(ExerciseFilter(query = "sipk"), sample)
        val (selected, others) = ExerciseSearch.pinningSelected(listOf("c:curl", "c:row", "c:nepostoji"), results, sample)
        assertEquals(listOf("c:curl", "c:row"), selected.map { it.id })
        assertFalse(others.any { it.id == "c:row" })
        assertEquals(results.map { it.id }.filter { it != "c:row" }, others.map { it.id })
    }

    @Test
    @DisplayName("Bez odabira rezultati ostaju isti")
    fun pinnedEmptySelection() {
        val (selected, others) = ExerciseSearch.pinningSelected(emptyList(), sample, sample)
        assertTrue(selected.isEmpty())
        assertEquals(sample.map { it.id }, others.map { it.id })
    }

    @Test
    @DisplayName("Zamjene imaju isti glavni mišić, a oprema iz profila ide prva")
    fun alternatives() {
        val items = sample + listOf(
            exercise("db-bench", "Potisak bučicama", "Dumbbell Bench Press", equipment = Equipment.DUMBBELL),
            exercise("machine-press", "Potisak na spravi", "Machine Chest Press", equipment = Equipment.MACHINE),
            exercise("dips", "Propadanja", "Dips", muscles = listOf(Muscle.TRICEPS, Muscle.CHEST), equipment = Equipment.BODYWEIGHT),
        )
        val bench = items[1]
        val hr = Locale.forLanguageTag("hr")
        assertEquals(listOf("c:db-bench", "c:machine-press", "c:dips"), ExerciseSearch.alternatives(bench, items, locale = hr).map { it.id })
        assertEquals(
            listOf("c:machine-press", "c:db-bench", "c:dips"),
            ExerciseSearch.alternatives(bench, items, setOf(Equipment.MACHINE), locale = hr).map { it.id },
        )
        assertEquals(1, ExerciseSearch.alternatives(bench, items, limit = 1).size)
    }

    @Test
    @DisplayName("Nedavne vježbe idu redom, bez ponavljanja, nepoznatih i onih već u treningu")
    fun recent() {
        val recent = ExerciseSearch.recent(listOf("c:row", "c:bench", "c:row", "c:nepostoji", "c:curl"), sample, setOf("c:bench"))
        assertEquals(listOf("c:row", "c:curl"), recent.map { it.id })
        assertEquals(listOf("c:row"), ExerciseSearch.recent(listOf("c:row", "c:curl"), sample, limit = 1).map { it.id })
    }
}
