package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.model.EquipmentPreset
import com.brunodobric.gymapp.model.ExperienceLevel
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.ReminderMode
import com.brunodobric.gymapp.model.ScheduleItemKind
import com.brunodobric.gymapp.model.TrainingGoal
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/PlanningTests/ProgramTests.swift.

private val catalog: ExerciseCatalog by lazy {
    ExerciseCatalog.decode(File(System.getProperty("catalog.dir")).resolve("catalog.json").readText())
}

private fun program(id: String): Program = assertNotNull(ProgramLibrary.all.firstOrNull { it.id == id })

private fun newStore() = GymStore(InMemoryPersistence())

/** Oprema svih preseta i prazan odabir (teretana). */
private val equipmentChoices: List<Set<Equipment>> = EquipmentPreset.entries.map { it.equipment.toSet() } + listOf(emptySet())

private class WeeklyLoad(val sets: Map<Muscle, Double>, val frequency: Map<Muscle, Double>)

/**
 * Tjedne frakcijske serije po mišiću (glavni mišić 1, pomoćni 0,5; Pelland i sur. 2026) i koliko puta
 * tjedno je mišić glavni u nekoj vježbi.
 */
private fun weeklyLoad(program: Program, equipment: Set<Equipment>): WeeklyLoad {
    val available = TrainingProfile(equipment = equipment).availableEquipment
    val workouts = program.workouts.associateBy { it.key }
    val sets = mutableMapOf<Muscle, Double>()
    val frequency = mutableMapOf<Muscle, Double>()
    val weeks = program.weeks.toDouble()
    for (step in program.sequence) {
        val workout = (step as? ProgramStep.Workout)?.let { workouts[it.key] } ?: continue
        val trained = mutableSetOf<Muscle>()
        for (item in workout.exercises) {
            val choice = item.option(available) ?: (if (item.role == ExerciseRole.ISOLATION) null else item.options.first())
            val exercise = choice?.let { catalog.exercise(it.catalogId) } ?: continue
            for (muscle in exercise.primaryMuscles) {
                sets[muscle] = (sets[muscle] ?: 0.0) + item.sets / weeks
                trained += muscle
            }
            for (muscle in exercise.secondaryMuscles) sets[muscle] = (sets[muscle] ?: 0.0) + item.sets * 0.5 / weeks
        }
        for (muscle in trained) frequency[muscle] = (frequency[muscle] ?: 0.0) + 1 / weeks
    }
    return WeeklyLoad(sets, frequency)
}

class ProgramTest {

    @Nested
    inner class LibraryTests {
        @Test
        fun `svaka izvedba postoji u katalogu s istom vrstom unosa i opremom`() {
            for (program in ProgramLibrary.all) for (workout in program.workouts) for (item in workout.exercises) {
                assertTrue(item.options.isNotEmpty())
                for (option in item.options) {
                    val found = assertNotNull(catalog.exercise(option.catalogId), "${program.id}: nema ${option.catalogId}")
                    assertEquals(found.inputType, option.inputType, "${option.catalogId}: druga vrsta unosa")
                    if (found.equipment == Equipment.BODYWEIGHT) {
                        assertTrue(setOf(Equipment.OTHER).containsAll(option.equipment), "${option.catalogId}: oprema")
                    } else {
                        assertEquals(setOf(found.equipment), option.equipment, "${option.catalogId}: oprema")
                    }
                }
            }
        }

        @Test
        fun `nizovi pozivaju postojeće treninge, svaki trening je u nizu i broj treninga odgovara danima`() {
            assertEquals(ProgramLibrary.all.size, ProgramLibrary.all.map { it.id }.toSet().size)
            for (program in ProgramLibrary.all) {
                val keys = program.workouts.map { it.key }.toSet()
                assertEquals(program.workouts.size, keys.size, "${program.id}: ponovljen ključ")
                val used = program.sequence.filterIsInstance<ProgramStep.Workout>().map { it.key }
                assertTrue(keys.containsAll(used), "${program.id}: nepoznat trening")
                assertEquals(keys, used.toSet(), "${program.id}: trening nije u nizu")
                assertEquals(program.daysPerWeek * program.weeks, used.size, "${program.id}: broj treninga")
                assertEquals(7 * program.weeks, program.sequence.size, "${program.id}: niz nije cijeli broj tjedana")
                assertTrue(program.daysPerWeek in program.suitableDays)
                assertTrue(program.goals.isNotEmpty() && program.levels.isNotEmpty())
            }
        }

        @Test
        fun `svaki program može se izvesti sa svakom opremom, i bez opreme`() {
            for (equipment in equipmentChoices) {
                val available = TrainingProfile(equipment = equipment).availableEquipment
                for (program in ProgramLibrary.all) {
                    assertTrue(program.isAvailable(available), "${program.id} nije moguć s $equipment")
                    for (workout in program.workouts) {
                        val count = workout.exercises.count { it.option(available) != null }
                        assertTrue(count >= 3, "${program.id}/${workout.key}: premalo vježbi s $equipment")
                    }
                }
            }
        }

        @Test
        fun `svaki mišić dobiva dovoljno serija, ali ne previše (teretana)`() {
            val big = listOf(Muscle.CHEST, Muscle.QUADRICEPS, Muscle.GLUTES)
            for (program in ProgramLibrary.all) {
                val load = weeklyLoad(program, emptySet()).sets
                // Leđa su dva mišića u katalogu (široki leđni i srednja leđa), pa se provjerava svaki.
                val back = listOf(load[Muscle.LATS] ?: 0.0, load[Muscle.MIDDLE_BACK] ?: 0.0)
                val beginnerOnly = ExperienceLevel.BEGINNER in program.levels && ExperienceLevel.ADVANCED !in program.levels
                if (beginnerOnly || program.daysPerWeek <= 2) {
                    // Početnici i minimalna doza: barem ~5 serija tjedno (Fyfe i sur. 2022).
                    for (muscle in big) assertTrue((load[muscle] ?: 0.0) >= 4.5, "${program.id}: $muscle")
                    assertTrue(back.all { it >= 4.5 }, "${program.id}: leđa")
                } else {
                    // ~10 serija tjedno i više (ACSM 2026), ispod granice iznad koje nema razlike (~30, Pelland i sur. 2026).
                    for (muscle in big) assertTrue((load[muscle] ?: 0.0) in 9.0..30.0, "${program.id}: $muscle ${load[muscle]}")
                    assertTrue(back.all { it in 6.0..30.0 }, "${program.id}: leđa $back")
                    assertTrue((load[Muscle.HAMSTRINGS] ?: 0.0) >= 7, "${program.id}: stražnja loža")
                }
            }
        }

        @Test
        fun `uz tri i više dana tjedno prsa, leđa i noge rade se barem 1,5 puta tjedno`() {
            for (program in ProgramLibrary.all.filter { it.daysPerWeek >= 3 }) for (equipment in equipmentChoices) {
                val frequency = weeklyLoad(program, equipment).frequency
                val back = maxOf(frequency[Muscle.LATS] ?: 0.0, frequency[Muscle.MIDDLE_BACK] ?: 0.0)
                assertTrue((frequency[Muscle.CHEST] ?: 0.0) >= 1.5, "${program.id}: prsa")
                assertTrue(back >= 1.5, "${program.id}: leđa")
                assertTrue(
                    (frequency[Muscle.QUADRICEPS] ?: 0.0) >= 1.5 || (frequency[Muscle.GLUTES] ?: 0.0) >= 2,
                    "${program.id}: noge",
                )
            }
        }

        @Test
        fun `bira se prva izvedba za dostupnu opremu`() {
            val bench = program("upper-lower-4").workouts.first().exercises.first()
            assertEquals("barbell-bench-press", bench.option(Equipment.entries.toSet())?.catalogId)
            assertEquals("dumbbell-bench-press", bench.option(setOf(Equipment.DUMBBELL, Equipment.BODYWEIGHT))?.catalogId)
            assertEquals("push-up", bench.option(setOf(Equipment.BODYWEIGHT))?.catalogId)
        }

        @Test
        fun `zadani dani podsjetnika imaju odmor između treninga`() {
            assertEquals(listOf(4), ProgramLibrary.defaultWeekdays(1))
            assertEquals(listOf(2, 4, 6), ProgramLibrary.defaultWeekdays(3))
            for (days in 1..7) assertEquals(days, ProgramLibrary.defaultWeekdays(days).size)
        }
    }

    @Nested
    inner class PrescriptionTests {
        @Test
        fun `snaga - glavne vježbe 3–6 ponavljanja i duža pauza`() {
            val main = ProgramPrescription.make(ExerciseRole.MAIN, 3, TrainingGoal.STRENGTH, ExperienceLevel.INTERMEDIATE)
            assertEquals(Prescription(3, 3, 6, 180), main)
        }

        @Test
        fun `bez cilja vrijedi hipertrofija`() {
            assertEquals(
                ProgramPrescription.make(ExerciseRole.SECONDARY, 3, TrainingGoal.HYPERTROPHY, null),
                ProgramPrescription.make(ExerciseRole.SECONDARY, 3, null, null),
            )
            assertEquals(15, ProgramPrescription.make(ExerciseRole.ISOLATION, 3, null, null).repsMax)
        }

        @Test
        fun `opća kondicija i početnik rade serije manje, ali barem dvije`() {
            assertEquals(2, ProgramPrescription.make(ExerciseRole.MAIN, 3, TrainingGoal.GENERAL_FITNESS, null).sets)
            assertEquals(2, ProgramPrescription.make(ExerciseRole.ISOLATION, 3, TrainingGoal.HYPERTROPHY, ExperienceLevel.BEGINNER).sets)
            assertEquals(3, ProgramPrescription.make(ExerciseRole.MAIN, 3, TrainingGoal.HYPERTROPHY, ExperienceLevel.BEGINNER).sets)
            assertEquals(2, ProgramPrescription.make(ExerciseRole.ISOLATION, 2, TrainingGoal.GENERAL_FITNESS, ExperienceLevel.BEGINNER).sets)
        }

        @Test
        fun `svaki raspon ima donju granicu ispod gornje`() {
            for (goal in TrainingGoal.entries) for (role in ExerciseRole.entries) {
                val dose = ProgramPrescription.make(role, 3, goal, null)
                assertTrue(dose.repsMin < dose.repsMax && dose.restSeconds >= 60)
            }
        }
    }

    @Nested
    inner class InstallerTests {
        @Test
        fun `stvara predloške i raspored u istom redoslijedu, s rasponima i pauzama`() {
            val store = newStore()
            val ppl = program("ppl-6")
            val schedule = ProgramInstaller(store).install(ppl) { "Vježba $it" }
            assertEquals(ppl.name, schedule.name)
            assertTrue(schedule.isActive)
            assertEquals(7, schedule.orderedItems.size)
            assertEquals(ScheduleItemKind.REST_DAY, schedule.orderedItems.last().kind)
            assertEquals(6, store.templates.size)
            assertEquals(6, schedule.orderedItems.mapNotNull { it.workoutTemplateId }.toSet().size)

            val push = assertNotNull(store.templates.firstOrNull { it.name == "Push A" })
            val bench = push.orderedExercises.first()
            assertEquals("Vježba barbell-bench-press", bench.exerciseName)
            assertEquals(4, bench.orderedSets.size)
            assertTrue(bench.orderedSets.all { it.targetReps == 6 && it.targetRepsMax == 10 })
            assertEquals(150, bench.restSeconds)
            assertEquals(ReminderMode.FIXED_DAYS, schedule.reminderMode)
            assertEquals(listOf(2, 3, 4, 5, 6, 7), schedule.weekdays)
            assertNull(schedule.reminderMinutes)
        }

        @Test
        fun `cilj snaga mijenja ponavljanja glavnih vježbi`() {
            val store = newStore()
            ProgramInstaller(store).install(program("upper-lower-4"), TrainingProfile(goal = TrainingGoal.STRENGTH)) { it }
            val upper = assertNotNull(store.templates.firstOrNull { it.name == "Gornji dio tijela A" })
            val bench = upper.orderedExercises.first()
            assertTrue(bench.orderedSets.all { it.targetReps == 3 && it.targetRepsMax == 6 })
            assertEquals(180, bench.restSeconds)
        }

        @Test
        fun `bez opreme - vježbe s vlastitom težinom, izolacije bez opreme otpadaju`() {
            val store = newStore()
            ProgramInstaller(store).install(
                program("upper-lower-4"), TrainingProfile(equipment = EquipmentPreset.BODYWEIGHT_ONLY.equipment.toSet()),
            ) { it }
            val upper = assertNotNull(store.templates.firstOrNull { it.name == "Gornji dio tijela A" })
            val names = upper.orderedExercises.map { it.exerciseName }
            assertEquals("push-up", names.first())
            assertFalse("dumbbell-lateral-raise" in names || "band-lateral-raise" in names)
            assertEquals(ExerciseInputType.BODYWEIGHT, upper.orderedExercises.first().inputType)
        }

        @Test
        fun `dani podsjetnika prate dane iz profila kad ih program podržava`() {
            val store = newStore()
            val basic = program("basic-full-body-2")
            assertEquals(listOf(4), ProgramInstaller(store).install(basic, TrainingProfile(daysPerWeek = 1)) { it }.weekdays)
            assertEquals(listOf(3, 6), ProgramInstaller(store).install(basic, TrainingProfile(daysPerWeek = 5)) { it }.weekdays)
        }

        @Test
        fun `nazivi rasporeda i treninga na jeziku sučelja`() {
            val store = newStore()
            val schedule = ProgramInstaller(store).install(
                program("upper-lower-4"), name = "Upper/Lower (4 days)", workoutName = { "W ${it.key}" }, exerciseName = { it },
            )
            assertEquals("Upper/Lower (4 days)", schedule.name)
            assertEquals(setOf("W upperA", "W lowerA", "W upperB", "W lowerB"), store.templates.map { it.name }.toSet())
        }

        @Test
        fun `plank ima serije bez ponavljanja`() {
            val store = newStore()
            ProgramInstaller(store).install(program("basic-full-body-2")) { it }
            val plank = assertNotNull(store.templates.flatMap { it.orderedExercises }.firstOrNull { it.exerciseName == "front-plank" })
            assertEquals(ExerciseInputType.DURATION, plank.inputType)
            assertTrue(plank.orderedSets.all { it.targetReps == null && it.targetRepsMax == null })
        }

        @Test
        fun `nova serija preuzima raspon, a ručni cilj iznad raspona ga poništava`() {
            val store = newStore()
            ProgramInstaller(store).install(program("full-body-3")) { it }
            val exercise = store.templates.first().orderedExercises.first()
            val engine = TemplateEngine(store)
            val added = engine.addSet(exercise)
            assertEquals(6, added.targetReps)
            assertEquals(10, added.targetRepsMax)
            engine.setTargets(added, 60.0, 8)
            assertEquals(10, added.targetRepsMax)
            engine.setTargets(added, 60.0, 12)
            assertNull(added.targetRepsMax)
        }
    }

    @Nested
    inner class RecommenderTests {
        private fun top(profile: TrainingProfile) = ProgramRecommender.recommend(profile).firstOrNull()?.program?.id

        @Test
        fun `tipični profili dobivaju očekivani program`() {
            val h = TrainingGoal.HYPERTROPHY
            assertEquals("beginner-full-body-3", top(TrainingProfile(TrainingGoal.STRENGTH, ExperienceLevel.BEGINNER, daysPerWeek = 3)))
            assertEquals("full-body-3", top(TrainingProfile(h, ExperienceLevel.INTERMEDIATE, daysPerWeek = 3)))
            assertEquals("upper-lower-4", top(TrainingProfile(h, ExperienceLevel.BEGINNER, daysPerWeek = 4)))
            assertEquals("upper-lower-ppl-5", top(TrainingProfile(h, ExperienceLevel.INTERMEDIATE, daysPerWeek = 5)))
            assertEquals("ppl-6", top(TrainingProfile(h, ExperienceLevel.ADVANCED, daysPerWeek = 6)))
            assertEquals("ppl-6", top(TrainingProfile(h, ExperienceLevel.ADVANCED, daysPerWeek = 7)))
            assertEquals("basic-full-body-2", top(TrainingProfile(TrainingGoal.GENERAL_FITNESS, daysPerWeek = 1)))
            assertEquals("basic-full-body-2", top(TrainingProfile(TrainingGoal.GENERAL_FITNESS, daysPerWeek = 2)))
            // Bez odgovora: 3 dana, početnik.
            assertEquals("beginner-full-body-3", top(TrainingProfile()))
        }

        @Test
        fun `razlozi navode samo ono što je korisnik odgovorio`() {
            val plain = ProgramRecommender.recommend(TrainingProfile()).first()
            assertEquals(listOf<RecommendationReason>(RecommendationReason.Days(3)), plain.reasons)
            val full = ProgramRecommender.recommend(
                TrainingProfile(
                    TrainingGoal.STRENGTH, ExperienceLevel.BEGINNER, EquipmentPreset.DUMBBELLS.equipment.toSet(), 3,
                ),
            ).first()
            assertEquals(
                listOf(
                    RecommendationReason.Days(3), RecommendationReason.Level(ExperienceLevel.BEGINNER),
                    RecommendationReason.Goal(TrainingGoal.STRENGTH), RecommendationReason.EquipmentFits,
                ),
                full.reasons,
            )
        }

        @Test
        fun `svaka kombinacija odgovora dobiva prijedlog koji odgovara opremi, danima i cilju`() {
            val goals: List<TrainingGoal?> = TrainingGoal.entries + listOf(null)
            val levels: List<ExperienceLevel?> = ExperienceLevel.entries + listOf(null)
            val allDays: List<Int?> = (1..7).toList() + listOf(null)
            for (goal in goals) for (level in levels) for (day in allDays) for (equipment in equipmentChoices) {
                val profile = TrainingProfile(goal, level, equipment, day)
                val result = ProgramRecommender.recommend(profile)
                assertEquals(3, result.size)
                assertEquals(result.size, result.map { it.program.id }.toSet().size)
                val best = result.first()
                val days = day ?: ProgramRecommender.DEFAULT_DAYS
                assertTrue(days in best.program.suitableDays, "$profile")
                // Cilj se poštuje kad ga ima ijedan program za te dane (za 5 i 6 dana nema programa za opću kondiciju).
                if (goal != null && ProgramLibrary.all.any { days in it.suitableDays && goal in it.goals }) {
                    assertTrue(goal in best.program.goals, "$profile")
                }
                assertTrue(result.all { it.program.isAvailable(profile.availableEquipment) })
                assertTrue(result.zipWithNext().all { (a, b) -> a.score >= b.score })
            }
        }

        @Test
        fun `program koji se ne može izvesti s opremom ne predlaže se`() {
            val rest = ProgramStep.RestDay
            val a = ProgramStep.Workout("a")
            val gymOnly = Program(
                "gym-only", "", "", 3, 3..3, TrainingGoal.entries.toSet(), ExperienceLevel.entries.toSet(),
                listOf(
                    ProgramWorkout(
                        "a", "A",
                        listOf(
                            ProgramExercise(
                                listOf(ExerciseOption("machine-leg-press", ExerciseInputType.WEIGHT_REPS, setOf(Equipment.MACHINE))),
                                ExerciseRole.MAIN, 3,
                            ),
                        ),
                    ),
                ),
                listOf(a, rest, a, rest, a, rest, rest), 1,
            )
            val home = TrainingProfile(equipment = EquipmentPreset.HOME_GYM.equipment.toSet(), daysPerWeek = 3)
            assertTrue(ProgramRecommender.recommend(home, listOf(gymOnly)).isEmpty())
            assertEquals(1, ProgramRecommender.recommend(TrainingProfile(daysPerWeek = 3), listOf(gymOnly)).size)
        }
    }

    @Nested
    inner class DaysGoalTests {
        @Test
        fun `dani programa prema profilu - dani iz profila ako ih program podržava, inače dani programa`() {
            assertEquals(4, program("upper-lower-4").trainingDays(TrainingProfile(daysPerWeek = 4)))
            assertEquals(3, program("full-body-3").trainingDays(TrainingProfile(daysPerWeek = 4)))
            assertEquals(3, program("full-body-3").trainingDays(TrainingProfile()))
            assertEquals(1, program("basic-full-body-2").trainingDays(TrainingProfile(daysPerWeek = 1)))
            assertEquals(6, program("ppl-6").trainingDays(TrainingProfile(daysPerWeek = 7)))
        }

        @Test
        fun `smanjenje cilja nudi se samo kad program ima manje dana od cilja`() {
            assertEquals(3, TrainingProfile(daysPerWeek = 4).lowerDaysGoal(program("full-body-3")))
            assertEquals(6, TrainingProfile(daysPerWeek = 7).lowerDaysGoal(program("ppl-6")))
            assertNull(TrainingProfile(daysPerWeek = 4).lowerDaysGoal(program("upper-lower-4")))
            assertNull(TrainingProfile(daysPerWeek = 2).lowerDaysGoal(program("full-body-3")))
            assertNull(TrainingProfile().lowerDaysGoal(program("full-body-3")))
        }
    }

    @Nested
    inner class EquipmentPresetTests {
        @Test
        fun `teretana je sva oprema, a preset se prepoznaje iz spremljenog popisa`() {
            assertEquals(Equipment.entries.toSet(), EquipmentPreset.GYM.equipment.toSet())
            for (preset in EquipmentPreset.entries) {
                assertEquals(preset, EquipmentPreset.matching(preset.equipment.reversed()))
                assertTrue(Equipment.BODYWEIGHT in preset.equipment)
            }
            assertNull(EquipmentPreset.matching(listOf(Equipment.KETTLEBELL)))
            assertNull(EquipmentPreset.matching(emptyList()))
        }

        @Test
        fun `profil bez opreme znači teretanu, a vlastita težina je uvijek dostupna`() {
            assertEquals(Equipment.entries.toSet(), TrainingProfile().availableEquipment)
            assertEquals(setOf(Equipment.DUMBBELL, Equipment.BODYWEIGHT), TrainingProfile(equipment = setOf(Equipment.DUMBBELL)).availableEquipment)
            assertFalse(TrainingProfile().hasAnswers)
            assertTrue(TrainingProfile(daysPerWeek = 3).hasAnswers)
        }
    }
}
