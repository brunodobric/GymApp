package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.CustomExercise
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.SessionState
import java.io.File
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/BackupTests/ForeignImportTests.swift. Fixture je stvarni izvoz (53 treninga, UTF-8 s BOM-om, CRLF).

private val utc = ZoneOffset.UTC
private val zagreb = ZoneId.of("Europe/Zagreb")

private fun fixture(): String =
    File(System.getProperty("fixtures.dir")).resolve("workouts-druga-aplikacija.csv").readText(Charsets.UTF_8)

private val catalog: ExerciseCatalog by lazy {
    ExerciseCatalog.decode(File(System.getProperty("catalog.dir")).resolve("catalog.json").readText())
}

private fun newStore() = GymStore(InMemoryPersistence())

private fun utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int): Instant =
    LocalDateTime.of(year, month, day, hour, minute).toInstant(ZoneOffset.UTC)

/** Vježbe iz fixturea koje nemaju par u katalogu i uvoze se kao vlastite. */
private val expectedCustom = setOf("Rows with Wide Neutral Grip", "Skull Crushers with Rope")

class ForeignImportTest {

    @Nested
    inner class ForeignWorkoutsCsvTests {
        @Test
        fun `fixture - svi treninzi, vjezbe i serije`() {
            val workouts = ForeignWorkoutsCsv.parse(fixture(), utc)
            assertEquals(53, workouts.size)
            assertEquals(277, workouts.sumOf { it.exercises.size })
            val sets = workouts.flatMap { it.exercises }.flatMap { it.sets }
            assertEquals(839, sets.size)
            assertEquals(836, sets.count { it.isDone })
            assertEquals(35, workouts.flatMap { it.exercises }.map { "${it.name}|${it.equipment}" }.toSet().size)
        }

        @Test
        fun `zaglavlje - naziv, detalji, datum u lokalnom vremenu i trajanje`() {
            val first = ForeignWorkoutsCsv.parse(fixture(), utc).first()
            assertEquals("Push · Day 1 · Week 9 · Gym 2.0", first.title)
            assertEquals("Push", first.name)
            assertEquals("Day 1 · Week 9 · Gym 2.0", first.details)
            assertEquals(utcDate(2026, 11, 2, 16, 27), first.startedAt)
            assertEquals(53 * 60, first.durationSeconds)
            assertEquals(1, first.line)

            val exercise = first.exercises[0]
            assertEquals("Incline Bench Press", exercise.name)
            assertEquals("Dumbbells", exercise.equipment)
            assertEquals(ForeignWorkoutsCsv.Kind.WEIGHT_REPS, exercise.kind)
            assertEquals(
                listOf(
                    ForeignWorkoutsCsv.SetRow(weightKg = 24.0, reps = 10),
                    ForeignWorkoutsCsv.SetRow(weightKg = 24.0, reps = 10),
                    ForeignWorkoutsCsv.SetRow(weightKg = 24.0, reps = 7),
                ),
                exercise.sets,
            )
        }

        @Test
        fun `vremenska zona pomice trenutak, ali ne i identitet treninga`() {
            val inZagreb = ForeignWorkoutsCsv.parse(fixture(), zagreb)
            val inUtc = ForeignWorkoutsCsv.parse(fixture(), utc)
            assertEquals(utcDate(2026, 11, 2, 15, 27), inZagreb[0].startedAt)
            assertEquals(inUtc.map { it.stableId }, inZagreb.map { it.stableId })
            assertEquals(53, inUtc.map { it.stableId }.toSet().size)
        }

        @Test
        fun `stabilan UUID je isti kao na iOS-u`() {
            // Vrijednost izračunata neovisno, istim koracima kao StableUUID.make na iOS-u (FNV-1a, 128 bita,
            // bajtovi UTF-8). Isti trening uvezen na iPhoneu i Androidu tako ima isti id.
            val id = StableUUID.make("foreign-workouts-csv|Push · Day 1 · Week 9 · Gym 2.0|2026-11-02 4:27 pm")
            assertEquals(UUID.fromString("9907A642-AB7C-5AC3-B89F-0DCF4C5BF87A"), id)
            assertEquals(5, id.version())
            assertEquals(2, id.variant())
        }

        @Test
        fun `trajanje - minute, sati, sati s minutama`() {
            assertEquals(3180, ForeignWorkoutsCsv.parseDuration("53 min"))
            assertEquals(3600, ForeignWorkoutsCsv.parseDuration("1 hr"))
            assertEquals(4620, ForeignWorkoutsCsv.parseDuration("1:17 hr"))
            assertEquals(3900, ForeignWorkoutsCsv.parseDuration("1 hr 5 min"))
            assertEquals(45, ForeignWorkoutsCsv.parseDuration("45 sec"))
            assertNull(ForeignWorkoutsCsv.parseDuration("dugo"))
        }

        @Test
        fun `datum - 12-satni i 24-satni zapis, neispravan datum se odbija`() {
            assertEquals(utcDate(2026, 11, 2, 0, 5), ForeignWorkoutsCsv.parseDate("2026-11-02 12:05 am", utc))
            assertEquals(utcDate(2026, 11, 2, 12, 5), ForeignWorkoutsCsv.parseDate("2026-11-02 12:05 pm", utc))
            assertEquals(utcDate(2026, 11, 2, 16, 27), ForeignWorkoutsCsv.parseDate("2026-11-02 16:27", utc))
            assertNull(ForeignWorkoutsCsv.parseDate("2026-02-30 4:00 pm", utc))
            assertNull(ForeignWorkoutsCsv.parseDate("53 min", utc))
        }

        @Test
        fun `vlastita tezina + teret, prazne serije i trajanje u minutama`() {
            val exercises = ForeignWorkoutsCsv.parse(fixture(), utc).flatMap { it.exercises }

            val calves = exercises.last { it.name == "Standing Calf Raises" }
            assertEquals(ForeignWorkoutsCsv.Kind.WEIGHTED_BODYWEIGHT, calves.kind)
            assertEquals(listOf(0.0, 8.0, 12.0, 12.0), calves.sets.map { it.extraWeightKg })
            assertTrue(calves.sets.all { it.weightKg == null && it.reps == 10 })

            val empty = exercises.first { it.line == 1018 }
            assertEquals("High Cable Flys", empty.name)
            assertTrue(empty.sets.size == 3 && empty.sets.none { it.isDone })

            val plank = exercises.first { it.name == "Plank" }
            assertEquals(ForeignWorkoutsCsv.Kind.DURATION, plank.kind)
            assertEquals(listOf(60, 60), plank.sets.map { it.durationSeconds })
        }

        @Test
        fun `kratka datoteka bez BOM-a, s LF i decimalnim teretom`() {
            val text = """
                "Leđa · Day 2 · Week 1 · Plan";"2025-01-05 9:00 am";"1 hr"
                "1. Pull-Ups · Bodyweight · 8 reps"
                #;KG;REPS
                1;+12.5;8
                2;+12.5;-

                "Noge";"2025-01-07 6:30 pm";"40 min"
                "1. Squats · Barbell"
                #;KG;REPS
                1;100;5
            """.trimIndent()
            val workouts = ForeignWorkoutsCsv.parse(text, utc)
            assertEquals(listOf("Leđa", "Noge"), workouts.map { it.name })
            assertTrue(workouts[1].details.isEmpty())
            assertEquals(
                listOf(ForeignWorkoutsCsv.SetRow(extraWeightKg = 12.5, reps = 8), ForeignWorkoutsCsv.SetRow(extraWeightKg = 12.5)),
                workouts[0].exercises[0].sets,
            )
            assertEquals("Barbell", workouts[1].exercises[0].equipment)
        }

        @Test
        fun `neispravan redak javlja broj retka`() {
            val text = "\"Push · Day 1\";\"2026-11-02 4:27 pm\";\"53 min\"\n\"1. Bench Press · Barbell\"\n#;KG;REPS\n1;abc;10\n"
            assertEquals(4, assertThrows<BackupException.InvalidCsv> { ForeignWorkoutsCsv.parse(text) }.line)
            assertEquals(1, assertThrows<BackupException.InvalidCsv> { ForeignWorkoutsCsv.parse("1;24;10\n") }.line)
            val unknownColumn = "\"Push\";\"2026-11-02 4:27 pm\";\"53 min\"\n\"1. Row · Machine\"\n#;WATTS\n"
            assertEquals(3, assertThrows<BackupException.InvalidCsv> { ForeignWorkoutsCsv.parse(unknownColumn) }.line)
        }

        @ParameterizedTest
        @ValueSource(
            strings = [
                "#;KG;REPS\n1;inf;10\n", "#;KG;REPS\n1;nan;10\n", "#;MINS\n1;inf\n", "#;SECS\n1;nan\n",
                "#;MINS\n1;99999999999999:30\n", "#;KM\n1;inf\n", "#;KG;REPS\n1;Infinity;10\n", "#;KG;REPS\n1;10f;10\n",
            ],
        )
        fun `beskonacna ili ogromna vrijednost se odbija umjesto da srusi uvoz`(table: String) {
            val text = "\"Push · Day 1\";\"2026-11-02 4:27 pm\";\"53 min\"\n\"1. Bench Press · Barbell\"\n$table"
            assertEquals(4, assertThrows<BackupException.InvalidCsv> { ForeignWorkoutsCsv.parse(text) }.line)
        }

        @Test
        fun `prepoznaje format, a vlastiti CSV ne`() {
            assertTrue(ForeignWorkoutsCsv.matches(fixture()))
            assertFalse(ForeignWorkoutsCsv.matches(Csv.line(CsvBackup.historyColumns)))
            assertFalse(ForeignWorkoutsCsv.matches(""))
        }
    }

    @Nested
    inner class ForeignExerciseMatcherTests {
        @Test
        fun `svaki poznati naziv upucuje na vjezbu koja postoji u katalogu`() {
            for (entry in ForeignExerciseMatcher.knownNames) {
                assertNotNull(catalog.exercise(entry.catalogId), "${entry.name}: nema ${entry.catalogId}")
            }
        }

        @Test
        fun `vjezbe iz fixturea - 33 iz kataloga, 2 vlastite`() {
            val matched = mutableMapOf<String, String>()
            val custom = mutableSetOf<String>()
            for (exercise in ForeignWorkoutsCsv.parse(fixture(), utc).flatMap { it.exercises }) {
                val id = ForeignExerciseMatcher.catalogId(exercise.name, exercise.equipment, catalog)
                if (id != null) matched[exercise.name] = id else custom += exercise.name
            }
            assertEquals(expectedCustom, custom)
            assertEquals(33, matched.keys.size)
            assertEquals("elbow-side-plank", matched["Side Plank"])
            assertEquals("incline-machine-chest-press", matched["Incline Chest Press"])
            assertEquals("standing-calf-raise-machine", matched["Standing Calf Raises"])
            assertEquals("dumbbell-incline-bench-press", matched["Incline Bench Press"])
            assertEquals("barbell-squat", matched["Squats"])
            assertEquals("neutral-grip-lat-pulldown", matched["Lat Pulldowns with Close Neutral Grip"])
            assertEquals("front-plank", matched["Plank"])
        }

        @Test
        fun `isti naziv uz drugu opremu nije ista vjezba`() {
            assertEquals("machine-leg-extension", ForeignExerciseMatcher.catalogId("Leg Extensions", "Machine", catalog))
            assertEquals("standing-calf-raise-machine", ForeignExerciseMatcher.catalogId("Standing Calf Raises", "Machine", catalog))
            assertNull(ForeignExerciseMatcher.catalogId("Rows with Wide Neutral Grip", "Resistance bands", catalog))
            assertNull(ForeignExerciseMatcher.catalogId("Leg Extensions", "Dumbbells", catalog))
            assertEquals(Equipment.EZ_BAR, ForeignExerciseMatcher.equipment("EZ bar"))
            assertEquals(Equipment.BANDS, ForeignExerciseMatcher.equipment("Resistance bands"))
        }
    }

    @Nested
    inner class ForeignWorkoutImportTests {
        @Test
        fun `pregled prije uvoza ne mijenja bazu`() {
            val store = newStore()
            val preview = ForeignWorkoutImport.preview(fixture(), catalog, "hr", store, utc)
            assertEquals(53, preview.newWorkouts.size)
            assertEquals(0, preview.alreadyImported)
            assertEquals(35, preview.exercises.size)
            assertEquals(2, preview.newCustomCount)
            assertEquals(836, preview.setCount)
            assertEquals(utcDate(2023, 3, 16, 17, 47), preview.firstDate)
            assertEquals(utcDate(2026, 11, 2, 16, 27), preview.lastDate)
            val bench = preview.exercises.first { it.sourceName == "Incline Bench Press" }
            assertEquals(ForeignWorkoutImport.Target.Catalog("dumbbell-incline-bench-press", "Potisak bučicama s kose klupe"), bench.target)
            assertTrue(store.sessions.isEmpty() && store.customExercises.isEmpty())
            assertFalse(store.hasChanges())
        }

        @Test
        fun `uvoz sprema treninge, serije i vlastite vjezbe`() {
            val store = newStore()
            val result = ForeignWorkoutImport.apply(ForeignWorkoutImport.preview(fixture(), catalog, "hr", store, utc), store)
            assertEquals(BackupImportResult(53, 0), result)

            assertEquals(53, store.sessions.size)
            assertTrue(store.sessions.all { it.state == SessionState.FINISHED && it.endedAt != null })
            assertEquals(836, store.setLogs.size)
            assertEquals(276, store.sessionExercises.size)
            assertEquals(expectedCustom, store.customExercises.map { it.name }.toSet())

            val push = store.sessions.first { it.startedAt == utcDate(2026, 11, 2, 16, 27) }
            assertEquals("Push", push.name)
            assertEquals("Day 1 · Week 9 · Gym 2.0", push.notes)
            assertEquals(utcDate(2026, 11, 2, 17, 20), push.endedAt)
            assertEquals(
                listOf(
                    "c:dumbbell-incline-bench-press", "c:dumbbell-seated-overhead-press", "c:dumbbell-lateral-raise",
                    "c:cable-bar-pushdown", "c:cable-high-to-low-fly",
                ),
                push.orderedExercises.map { it.exerciseKey },
            )
            val sets = push.orderedExercises.flatMap { it.orderedSets }
            assertEquals(3514.0, sets.sumOf { (it.weightKg ?: 0.0) * (it.reps ?: 0) })
            // Serije su odrađene (statistika broji samo njih) i redom unutar trajanja treninga.
            val times = sets.mapNotNull { it.completedAt }
            assertEquals(sets.size, times.size)
            assertEquals(times.sorted(), times)
            assertTrue(times.all { it > push.startedAt && it <= push.endedAt!! })

            val calves = store.sessionExercises.filter { it.exerciseKey == "c:standing-calf-raise-machine" }
            assertTrue(calves.all { it.inputType == ExerciseInputType.WEIGHTED_BODYWEIGHT })
            assertTrue(calves.any { exercise -> exercise.orderedSets.map { it.extraWeightKg } == listOf(0.0, 8.0, 12.0, 12.0) })
            assertEquals(4, calves.size)
        }

        @Test
        fun `ponovni uvoz iste datoteke ne stvara duplikate`() {
            val store = newStore()
            val text = fixture()
            ForeignWorkoutImport.apply(ForeignWorkoutImport.preview(text, catalog, "hr", store, utc), store)
            val again = ForeignWorkoutImport.preview(text, catalog, "hr", store, utc)
            assertTrue(again.newWorkouts.isEmpty())
            assertEquals(53, again.alreadyImported)
            assertEquals(BackupImportResult(0, 53), ForeignWorkoutImport.apply(again, store))
            assertEquals(53, store.sessions.size)
            assertEquals(2, store.customExercises.size)

            // Novija datoteka s jednim novim treningom na vrhu dodaje samo njega, i to u drugoj vremenskoj zoni.
            val newer = "\"Pull · Day 2 · Week 9 · Gym 2.0\";\"2026-11-04 4:10 pm\";\"50 min\"\n" +
                "\"1. Rows with Wide Neutral Grip · Resistance bands · 10 reps\"\n#;KG;REPS\n1;14;10\n\n" + text
            val update = ForeignWorkoutImport.preview(newer, catalog, "hr", store, zagreb)
            assertTrue(update.newWorkouts.size == 1 && update.alreadyImported == 53)
            assertEquals(listOf(false), update.exercises.map { it.target.isNewCustom }, "postojeća vlastita vježba se ponovno koristi")
            ForeignWorkoutImport.apply(update, store)
            assertEquals(54, store.sessions.size)
            assertEquals(2, store.customExercises.size)
        }

        @Test
        fun `trening koji se u datoteci ponavlja uvozi se jednom`() {
            val block = "\"Push\";\"2026-11-02 4:27 pm\";\"53 min\"\n\"1. Bench Press · Barbell · 10 reps\"\n#;KG;REPS\n1;80;10\n\n"
            val preview = ForeignWorkoutImport.preview(block + block, catalog, "en", newStore(), utc)
            assertTrue(preview.newWorkouts.size == 1 && preview.alreadyImported == 1)
            assertEquals(ForeignWorkoutImport.Target.Catalog("barbell-bench-press", "Barbell Bench Press"), preview.exercises.first().target)
        }

        @Test
        fun `postojeca vlastita vjezba istog naziva se koristi umjesto nove`() {
            val store = newStore()
            val mine = store.insert(CustomExercise("rows with wide neutral grip"))
            store.save()
            val preview = ForeignWorkoutImport.preview(fixture(), catalog, "hr", store, utc)
            val rows = preview.exercises.first { it.sourceName == "Rows with Wide Neutral Grip" }
            assertEquals(ForeignWorkoutImport.Target.ExistingCustom(mine.id, "rows with wide neutral grip"), rows.target)
            // Druga vježba bez para u katalogu (Skull Crushers with Rope) je i dalje nova.
            assertEquals(1, preview.newCustomCount)
            ForeignWorkoutImport.apply(preview, store)
            assertEquals(2, store.customExercises.size)
        }
    }
}
