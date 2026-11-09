package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.ScheduleItemKind
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.WorkoutError
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private val squat = ExerciseRef.catalog("squat", "Čučanj")
private val bench = ExerciseRef.catalog("bench", "Potisak s klupe")
private val row = ExerciseRef.catalog("row", "Veslanje")
private val curl = ExerciseRef.catalog("curl", "Pregib")
private val WR = ExerciseInputType.WEIGHT_REPS

/** Petak 15. 1. 2027., 08:00 UTC. */
private val base = Instant.ofEpochSecond(1_800_000_000)
private const val DAY = 86_400L

private fun newStore() = GymStore(InMemoryPersistence())

private fun GymStore.template(name: String, exercises: List<ExerciseRef> = listOf(squat)): WorkoutTemplate {
    val engine = TemplateEngine(this)
    val result = engine.createTemplate(name)
    exercises.forEach { engine.addExercise(it, WR, result) }
    return result
}

/** Završi trening s jednom odrađenom serijom. */
private fun GymStore.finish(session: Session, at: Instant) {
    val engine = WorkoutEngine(this)
    val set = assertNotNull(session.orderedExercises.firstOrNull()?.orderedSets?.firstOrNull())
    set.weightKg = 50.0
    set.reps = 5
    engine.completeSet(set, 60, at)
    engine.finishSession(session, now = at.plusSeconds(1800))
}

/** Odradi i završi trening iz predloška (jedna serija) i javi to rasporedu. */
private fun GymStore.doWorkout(planned: PlannedWorkout?, at: Instant): Session {
    val session = TemplateStarter(this).start(assertNotNull(planned), at)
    finish(session, at)
    ScheduleEngine(this).sessionFinished(session)
    return session
}

/** Raspored A, odmor, B, C. */
private fun GymStore.abcSchedule(cycles: Int?): Pair<Schedule, List<WorkoutTemplate>> {
    val engine = ScheduleEngine(this)
    val templates = listOf("A", "B", "C").map { template(it) }
    val schedule = engine.createSchedule("ABC", cycles)
    engine.addWorkout(templates[0], schedule)
    engine.addRestDay(schedule)
    engine.addWorkout(templates[1], schedule)
    engine.addWorkout(templates[2], schedule)
    return schedule to templates
}

class PlanningTest {

    @Nested
    inner class TemplateEngineTests {
        @Test
        fun `nova vježba dobiva tri radne serije, a redoslijed se može mijenjati`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val result = store.template("Push", listOf(squat, bench, row))
            assertEquals(listOf("Čučanj", "Potisak s klupe", "Veslanje"), result.orderedExercises.map { it.exerciseName })
            assertEquals(TemplateEngine.DEFAULT_SET_COUNT, result.orderedExercises[0].orderedSets.size)
            engine.moveExercises(result, listOf(2), 0)
            assertEquals(listOf("Veslanje", "Čučanj", "Potisak s klupe"), result.orderedExercises.map { it.exerciseName })
        }

        @Test
        fun `superset mora imati dvije vježbe, a jedna preostala se oslobađa`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val result = store.template("T", listOf(squat, bench, row))
            val list = result.orderedExercises
            assertFailsWith<PlanningError.NeedsTwoExercises> { engine.makeSuperset(listOf(list[0]), result) }
            engine.makeSuperset(listOf(list[0], list[2]), result)
            assertEquals(listOf("Čučanj", "Veslanje", "Potisak s klupe"), result.orderedExercises.map { it.exerciseName })
            assertNotNull(list[0].supersetGroupId)
            assertEquals(list[0].supersetGroupId, list[2].supersetGroupId)
            engine.removeFromSuperset(list[0])
            assertNull(list[0].supersetGroupId)
            assertNull(list[2].supersetGroupId)
        }

        @Test
        fun `uklanjanje vježbe popravlja redoslijed i raspušta superset od jedne vježbe`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val result = store.template("T", listOf(squat, bench, row))
            val list = result.orderedExercises
            engine.makeSuperset(listOf(list[0], list[1]), result)
            engine.removeExercise(list[0])
            assertEquals(listOf(0, 1), result.orderedExercises.map { it.orderIndex })
            assertTrue(result.orderedExercises.all { it.supersetGroupId == null })
        }

        @Test
        fun `nova serija preuzima ciljeve prethodne, a brisanje popravlja redoslijed`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val exercise = store.template("T").orderedExercises.first()
            engine.setTargets(exercise.orderedSets[2], 80.0, 5)
            val added = engine.addSet(exercise)
            assertEquals(80.0, added.targetWeightKg)
            assertEquals(5, added.targetReps)
            engine.removeSet(exercise.orderedSets[0])
            assertEquals(listOf(0, 1, 2), exercise.orderedSets.map { it.orderIndex })
        }
    }

    @Nested
    inner class TemplateStarterTests {
        @Test
        fun `trening preuzima vježbe, ciljeve, pauze i superset, a brisanje predloška ne dira povijest`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val result = store.template("Push", listOf(bench, row, curl))
            val list = result.orderedExercises
            engine.setTargets(list[0].orderedSets[0], 60.0, 8)
            engine.removeSet(list[0].orderedSets[2])
            engine.setRest(120, list[0])
            engine.makeSuperset(listOf(list[1], list[2]), result)

            val session = TemplateStarter(store).start(result, base)
            assertEquals("Push", session.name)
            assertEquals(result.id, session.templateId)
            val exercises = session.orderedExercises
            assertEquals(listOf("Potisak s klupe", "Veslanje", "Pregib"), exercises.map { it.exerciseName })
            assertEquals(2, exercises[0].orderedSets.size)
            assertEquals(60.0, exercises[0].orderedSets[0].weightKg)
            assertEquals(8, exercises[0].orderedSets[0].reps)
            assertEquals(120, exercises[0].restSeconds)
            assertNotNull(exercises[1].supersetGroupId)
            assertEquals(exercises[1].supersetGroupId, exercises[2].supersetGroupId)

            engine.delete(result)
            assertEquals(3, session.orderedExercises.size)
        }

        @Test
        fun `izbor treninga bez rasporeda - samo treninzi snage s vježbama, po nazivu`() {
            val store = newStore()
            val pull = store.template("Pull")
            val legs = store.template("noge")
            val push = store.template("Push")
            val empty = store.template("Prazan", emptyList())
            val cardio = store.template("Trčanje")
            cardio.kind = WorkoutKind.CARDIO

            val result = TemplateStarter.startable(listOf(pull, empty, push, cardio, legs), Locale.forLanguageTag("hr"))
            assertEquals(listOf("noge", "Pull", "Push"), result.map { it.name })
            assertTrue(TemplateStarter.startable(emptyList()).isEmpty())
        }

        @Test
        fun `ne može se pokrenuti drugi trening dok je jedan aktivan`() {
            val store = newStore()
            val result = store.template("A")
            val starter = TemplateStarter(store)
            starter.start(result, base)
            assertFailsWith<WorkoutError.AlreadyActive> { starter.start(result, base) }
        }
    }

    @Nested
    inner class ScheduleProgressTests {
        @Test
        fun `novi trening iz rasporeda nastaje prazan i ide na kraj niza`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val schedule = engine.createSchedule("Novi")
            engine.addRestDay(schedule)

            val created = engine.addNewWorkout("Novi trening", schedule)

            assertEquals("Novi trening", created.name)
            assertEquals(WorkoutKind.STRENGTH, created.kind)
            assertTrue(created.exercises.isEmpty())
            assertEquals(1, store.templates.size)
            val items = schedule.orderedItems
            assertEquals(listOf(ScheduleItemKind.REST_DAY, ScheduleItemKind.WORKOUT), items.map { it.kind })
            assertEquals(created.id, items.last().workoutTemplateId)
        }

        @Test
        fun `rest dani se prelaze, a ciklus završava nakon zadnjeg treninga`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)

            var next = assertNotNull(engine.nextWorkout(schedule))
            assertEquals("A", next.template.name)
            assertEquals(1, next.cycle)
            store.doWorkout(next, base)
            next = assertNotNull(engine.nextWorkout(schedule))
            assertEquals("B", next.template.name)
            store.doWorkout(next, base.plusSeconds(DAY))
            next = assertNotNull(engine.nextWorkout(schedule))
            assertEquals("C", next.template.name)
            store.doWorkout(next, base.plusSeconds(2 * DAY))

            next = assertNotNull(engine.nextWorkout(schedule))
            assertEquals("A", next.template.name)
            assertEquals(2, next.cycle)
            assertTrue(schedule.isActive)
            assertEquals(0, schedule.currentPosition)
        }

        @Test
        fun `nakon zadnjeg ciklusa raspored postaje neaktivan`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(1)
            for (offset in 0 until 3) store.doWorkout(engine.nextWorkout(schedule), base.plusSeconds(offset * DAY))
            assertFalse(schedule.isActive)
            assertNull(engine.nextWorkout(schedule))
            assertTrue(engine.upcomingWorkouts().isEmpty())
            assertEquals(1, schedule.currentCycle)
        }

        @Test
        fun `propušteni dani ništa ne pomiču`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            store.doWorkout(engine.nextWorkout(schedule), base)
            // Tri tjedna bez treninga: sljedeći je i dalje B, u istom ciklusu.
            val next = assertNotNull(engine.nextWorkout(schedule))
            assertEquals("B", next.template.name)
            assertEquals(1, next.cycle)
            store.doWorkout(next, base.plusSeconds(21 * DAY))
            assertEquals("C", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `trening odrađen mimo reda bilježi se kao odrađen, a sljedeći ostaje prvi neodrađeni`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, templates) = store.abcSchedule(null)
            val session = TemplateStarter(store).start(templates[2], base)
            session.scheduleId = schedule.id
            store.finish(session, base)
            assertTrue(engine.sessionFinished(session))
            assertEquals("A", engine.nextWorkout(schedule)?.template?.name)
            store.doWorkout(engine.nextWorkout(schedule), base)
            // C je već odrađen, pa iza B ciklus završava.
            store.doWorkout(engine.nextWorkout(schedule), base)
            assertEquals(2, schedule.currentCycle)
            assertEquals("A", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `trening koji nije u rasporedu ne mijenja raspored`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            val other = store.template("D")
            val session = TemplateStarter(store).start(other, base)
            session.scheduleId = schedule.id
            store.finish(session, base)
            assertFalse(engine.sessionFinished(session))
            assertEquals("A", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `trening premješten na početak novog rasporeda postaje sljedeći`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val templates = listOf("A", "B").map { store.template(it) }
            val schedule = engine.createSchedule("Novi")
            engine.addWorkout(templates[0], schedule)
            assertEquals("A", engine.nextWorkout(schedule)?.template?.name)
            engine.addWorkout(templates[1], schedule)
            engine.moveItems(schedule, listOf(1), 0)
            assertEquals("B", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `neodrađeni trening premješten ispred odrađenog je sljedeći, a odrađeni se ne ponavlja`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            store.doWorkout(engine.nextWorkout(schedule), base)
            // A, odmor, B, C -> C, A, odmor, B
            engine.moveItems(schedule, listOf(3), 0)
            assertEquals("C", engine.nextWorkout(schedule)?.template?.name)
            store.doWorkout(engine.nextWorkout(schedule), base)
            assertEquals("B", engine.nextWorkout(schedule)?.template?.name)
            store.doWorkout(engine.nextWorkout(schedule), base)
            assertEquals(2, schedule.currentCycle)
            assertEquals("C", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `napredak iz starije verzije (samo pozicija) ostaje i nakon premještanja`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            // Starija verzija: A odrađen, zapisano samo pozicijom.
            schedule.currentPosition = 1
            store.save()
            assertEquals("B", engine.nextWorkout(schedule)?.template?.name)
            // A, odmor, B, C -> A, odmor, C, B
            engine.moveItems(schedule, listOf(3), 2)
            assertEquals("C", engine.nextWorkout(schedule)?.template?.name)
            engine.moveItems(schedule, listOf(0), 4)
            assertEquals("C", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `preskakanje trenutnog treninga i poništavanje`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            store.doWorkout(engine.nextWorkout(schedule), base)

            val skip = assertNotNull(engine.skipNextWorkout(schedule))
            assertEquals("C", engine.nextWorkout(schedule)?.template?.name)
            engine.unskip(skip, schedule)
            assertEquals("B", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `preskočeni treninzi tekućeg ciklusa imaju naziv i mogu se vratiti`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            assertTrue(engine.skippedWorkouts(schedule).isEmpty())
            engine.skipNextWorkout(schedule)
            val skipped = engine.skippedWorkouts(schedule)
            assertEquals(listOf("A"), skipped.map { it.templateName })
            engine.unskip(skipped[0].change, schedule)
            assertTrue(engine.skippedWorkouts(schedule).isEmpty())
            assertEquals("A", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `ponovno pokretanje briše izmjene starog prolaza`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(1)
            engine.skipNextWorkout(schedule)
            assertEquals("B", engine.nextWorkout(schedule)?.template?.name)
            engine.restart(schedule)
            assertEquals("A", engine.nextWorkout(schedule)?.template?.name)
            assertTrue(store.cycleOverrides.isEmpty())
        }

        @Test
        fun `izmjene prošlih ciklusa se brišu kad počne novi ciklus`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            engine.skipNextWorkout(schedule)
            assertEquals(1, store.cycleOverrides.size)
            engine.skipNextWorkout(schedule)
            engine.skipNextWorkout(schedule)
            assertEquals(2, schedule.currentCycle)
            assertTrue(store.cycleOverrides.isEmpty())
        }

        @Test
        fun `brisanje rasporeda briše i njegove izmjene, a izmjene drugog rasporeda ostaju`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, templates) = store.abcSchedule(null)
            val other = engine.createSchedule("Drugi", null)
            engine.addWorkout(templates[0], other)
            engine.addWorkout(templates[1], other)
            engine.skipNextWorkout(schedule)
            engine.skipNextWorkout(other)
            engine.delete(schedule)
            assertEquals(listOf(other.id), store.cycleOverrides.map { it.scheduleId })
            assertEquals(listOf(other.id), store.schedules.map { it.id })
        }

        @Test
        fun `preskakanje svih preostalih treninga otvara sljedeći ciklus`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            repeat(3) { engine.skipNextWorkout(schedule) }
            val next = assertNotNull(engine.nextWorkout(schedule))
            assertEquals(2, next.cycle)
            assertEquals("A", next.template.name)
        }

        @Test
        fun `obrisan predložak se prelazi`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, templates) = store.abcSchedule(null)
            TemplateEngine(store).delete(templates[1])
            store.doWorkout(engine.nextWorkout(schedule), base)
            assertEquals("C", engine.nextWorkout(schedule)?.template?.name)
        }

        @Test
        fun `raspored kojem su svi predlošci obrisani ne vrti cikluse u nedogled`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, templates) = store.abcSchedule(null)
            templates.forEach { TemplateEngine(store).delete(it) }
            engine.restart(schedule)
            assertNull(engine.nextWorkout(schedule))
            assertEquals(1, schedule.currentCycle)
        }

        @Test
        fun `sljedeći trening svakog aktivnog rasporeda`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (first, _) = store.abcSchedule(null)
            val (second, _) = store.abcSchedule(null)
            engine.setActive(false, second)
            assertEquals(1, engine.upcomingWorkouts().size)
            assertEquals(first.id, engine.upcomingWorkouts().first().schedule.id)
        }

        @Test
        fun `izbor treninga iz rasporeda - svaki trening snage jednom, redom niza, bez neaktivnog rasporeda`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, templates) = store.abcSchedule(null)
            // A se ponavlja na kraju, a trening bez vježbi se ne nudi.
            engine.addWorkout(templates[0], schedule)
            engine.addNewWorkout("Prazan", schedule)
            assertEquals(listOf("A", "B", "C"), engine.workoutChoices(schedule).map { it.template.name })

            engine.setActive(false, schedule)
            assertTrue(engine.workoutChoices(schedule).isEmpty())
        }

        @Test
        fun `ponovljeni trening u izboru je prvi neodrađeni, s izmjenama ciklusa`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, templates) = store.abcSchedule(null)
            val repeated = engine.addWorkout(templates[0], schedule)
            store.doWorkout(engine.nextWorkout(schedule), base)

            val choice = assertNotNull(engine.workoutChoices(schedule).firstOrNull())
            assertEquals(repeated.id, choice.item.id)
            engine.removeExercise(templates[0].orderedExercises.first(), choice)
            assertEquals(true, engine.workoutChoices(schedule).firstOrNull()?.exercises?.isEmpty())
        }

        @Test
        fun `odabrani trening mimo reda je odrađen, a sljedeći ostaje prvi neodrađeni`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            val choices = engine.workoutChoices(schedule)
            store.doWorkout(choices[2], base)
            assertEquals("A", engine.nextWorkout(schedule)?.template?.name)
            store.doWorkout(choices[0], base.plusSeconds(DAY))
            assertEquals("B", engine.nextWorkout(schedule)?.template?.name)
            store.doWorkout(choices[1], base.plusSeconds(2 * DAY))
            assertEquals(2, schedule.currentCycle)
        }
    }

    @Nested
    inner class CycleOverrideTests {
        private val store = newStore()
        private val engine = ScheduleEngine(store)
        private val push = store.template("Push", listOf(bench, row, curl))
        private val schedule = engine.createSchedule("Raspored").also { engine.addWorkout(push, it) }

        @Test
        fun `izbacivanje i zamjena vježbe vrijede samo za taj ciklus i mogu se poništiti`() {
            val planned = assertNotNull(engine.nextWorkout(schedule))
            val list = push.orderedExercises
            val removal = engine.removeExercise(list[0], planned)
            engine.replaceExercise(list[1], squat, WR, planned)

            val changed = assertNotNull(engine.nextWorkout(schedule))
            assertEquals(listOf("Čučanj", "Pregib"), changed.exercises.map { it.ref.name })
            assertTrue(changed.exercises[0].isReplacement)
            // Predložak ostaje netaknut.
            assertEquals(3, push.orderedExercises.size)

            engine.undo(removal)
            val restored = assertNotNull(engine.nextWorkout(schedule))
            assertEquals(listOf("Potisak s klupe", "Čučanj", "Pregib"), restored.exercises.map { it.ref.name })
        }

        @Test
        fun `druga izmjena iste vježbe zamjenjuje prvu`() {
            val planned = assertNotNull(engine.nextWorkout(schedule))
            val target = push.orderedExercises[0]
            engine.removeExercise(target, planned)
            engine.replaceExercise(target, squat, WR, planned)
            val result = assertNotNull(engine.nextWorkout(schedule))
            assertEquals(listOf("Čučanj", "Veslanje", "Pregib"), result.exercises.map { it.ref.name })
        }

        @Test
        fun `trening pokrenut nakon izmjena ne sadrži izbačenu vježbu, a sljedeći ciklus je netaknut`() {
            val planned = assertNotNull(engine.nextWorkout(schedule))
            engine.removeExercise(push.orderedExercises[0], planned)

            val session = TemplateStarter(store).start(assertNotNull(engine.nextWorkout(schedule)), base)
            assertEquals(listOf("Veslanje", "Pregib"), session.orderedExercises.map { it.exerciseName })
            store.finish(session, base)
            engine.sessionFinished(session)

            val second = assertNotNull(engine.nextWorkout(schedule))
            assertEquals(2, second.cycle)
            assertEquals(3, second.exercises.size)
        }
    }

    @Nested
    inner class BulkEditingTests {
        @Test
        fun `više vježbi odjednom ide na kraj ili na zadano mjesto, redom odabira i sa serijama`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val result = store.template("T", listOf(squat, bench))

            val appended = engine.addExercises(listOf(ExerciseChoice(row, WR), ExerciseChoice(curl, WR)), result)
            assertEquals(2, appended.size)
            assertEquals(listOf("Čučanj", "Potisak s klupe", "Veslanje", "Pregib"), result.orderedExercises.map { it.exerciseName })
            assertTrue(appended.all { it.orderedSets.size == TemplateEngine.DEFAULT_SET_COUNT })

            val pull = ExerciseRef.catalog("pullup", "Zgib")
            engine.addExercises(listOf(ExerciseChoice(pull, ExerciseInputType.BODYWEIGHT)), result, 1)
            assertEquals(
                listOf("Čučanj", "Zgib", "Potisak s klupe", "Veslanje", "Pregib"),
                result.orderedExercises.map { it.exerciseName },
            )
            assertEquals(listOf(0, 1, 2, 3, 4), result.orderedExercises.map { it.orderIndex })
            assertEquals(ExerciseInputType.BODYWEIGHT, result.orderedExercises[1].inputType)

            // Mjesto izvan raspona ide na kraj, a prazan odabir ništa ne mijenja.
            engine.addExercises(listOf(ExerciseChoice(pull, ExerciseInputType.BODYWEIGHT)), result, 99)
            assertEquals("Zgib", result.orderedExercises.last().exerciseName)
            assertTrue(engine.addExercises(emptyList(), result).isEmpty())
            assertEquals(6, result.orderedExercises.size)
        }

        @Test
        fun `umetnuti treninzi nisu odrađeni, pa je prvi od njih sljedeći`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, templates) = store.abcSchedule(null)
            val names = templates.associate { it.id to it.name }
            fun sequence() = schedule.orderedItems.map {
                if (it.kind == ScheduleItemKind.REST_DAY) "-" else names[it.workoutTemplateId] ?: "?"
            }

            // Odradi A: sljedeći je B (pozicija 2).
            store.doWorkout(engine.nextWorkout(schedule), base)
            assertEquals("B", engine.nextWorkout(schedule)?.template?.name)

            val added = engine.insertWorkouts(listOf(templates[2], templates[0]), schedule, 1)
            assertEquals(2, added.size)
            assertEquals(listOf("A", "C", "A", "-", "B", "C"), sequence())
            assertEquals(listOf(0, 1, 2, 3, 4, 5), schedule.orderedItems.map { it.orderIndex })
            assertEquals("C", engine.nextWorkout(schedule)?.template?.name)

            engine.insertWorkouts(listOf(templates[1]), schedule)
            assertEquals(listOf("A", "C", "A", "-", "B", "C", "B"), sequence())
        }
    }

    @Nested
    inner class CycleCountRangeTests {
        @Test
        fun `raspon počinje od tekućeg ciklusa i ide do 52`() {
            assertEquals(1..52, ScheduleEngine.cycleCountRange(0))
            assertEquals(1..52, ScheduleEngine.cycleCountRange(1))
            assertEquals(30..52, ScheduleEngine.cycleCountRange(30))
        }

        @Test
        fun `raspored nakon 52 ciklusa ima neprazan raspon`() {
            assertEquals(52..52, ScheduleEngine.cycleCountRange(52))
            assertEquals(60..60, ScheduleEngine.cycleCountRange(60))
        }
    }

    @Nested
    inner class TemplateFromSessionTests {
        /** Odrađeni trening: potisak (zagrijavanje + dvije radne), superset veslanja i pregiba. */
        private fun GymStore.pastSession(): Session {
            val engine = WorkoutEngine(this)
            val session = engine.startSession("Push", now = base)
            val pressing = engine.addExercise(bench, WR, session, now = base)
            pressing.orderedSets.forEach { engine.removeSet(it, base) }
            for ((kind, weight, reps) in listOf(Triple(SetKind.WARM_UP, 40.0, 10), Triple(SetKind.WORKING, 80.0, 8), Triple(SetKind.WORKING, 85.0, 6))) {
                val set = engine.addSet(pressing, kind, base)
                set.weightKg = weight
                set.reps = reps
                engine.completeSet(set, 0, base)
            }
            pressing.restSeconds = 150
            val rowing = engine.addExercise(row, WR, session, now = base)
            val curling = engine.addExercise(curl, WR, session, now = base)
            engine.makeSuperset(listOf(rowing, curling), session, base)
            for (exercise in listOf(rowing, curling)) {
                val set = exercise.orderedSets[0]
                set.weightKg = 30.0
                set.reps = 12
                engine.completeSet(set, 0, base)
            }
            engine.finishSession(session, now = base.plusSeconds(3600))
            return session
        }

        @Test
        fun `predložak ima naziv, vježbe, završene serije kao ciljeve, pauze i superset`() {
            val store = newStore()
            val session = store.pastSession()
            val template = TemplateEngine(store).createTemplate(session)

            assertEquals("Push", template.name)
            assertEquals(WorkoutKind.STRENGTH, template.kind)
            val exercises = template.orderedExercises
            assertEquals(listOf("Potisak s klupe", "Veslanje", "Pregib"), exercises.map { it.exerciseName })
            assertEquals(listOf(SetKind.WARM_UP, SetKind.WORKING, SetKind.WORKING), exercises[0].orderedSets.map { it.kind })
            assertEquals(listOf<Double?>(40.0, 80.0, 85.0), exercises[0].orderedSets.map { it.targetWeightKg })
            assertEquals(listOf<Int?>(10, 8, 6), exercises[0].orderedSets.map { it.targetReps })
            assertEquals(150, exercises[0].restSeconds)
            // Nezavršene serije iz treninga su obrisane pri završetku, pa ostaje jedna serija.
            assertEquals(1, exercises[1].orderedSets.size)
            val group = exercises[1].supersetGroupId
            assertNotNull(group)
            assertEquals(group, exercises[2].supersetGroupId)
            assertNotEquals(session.orderedExercises[1].supersetGroupId, group)
        }

        @Test
        fun `izmjene novog treninga ne diraju odrađeni trening`() {
            val store = newStore()
            val session = store.pastSession()
            val engine = TemplateEngine(store)
            val template = engine.createTemplate(session)
            template.name = "Push 2"
            engine.removeExercise(template.orderedExercises[0])
            engine.removeExercise(template.orderedExercises[0])
            assertEquals(1, template.orderedExercises.size)
            // Superset s jednom vježbom se raspušta.
            assertNull(template.orderedExercises[0].supersetGroupId)
            assertEquals("Push", session.name)
            assertEquals(3, session.orderedExercises.size)
            assertEquals(3, session.orderedExercises[0].orderedSets.size)
        }
    }

    @Nested
    inner class EditDiscardTests {
        @Test
        fun `odbačeni novi trening iz rasporeda nestaje iz niza i iz treninga`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, _) = store.abcSchedule(null)
            val created = engine.addNewWorkout("Novi", schedule)
            assertEquals(5, schedule.orderedItems.size)
            engine.discardNewWorkout(created, schedule)
            assertEquals(4, schedule.orderedItems.size)
            assertEquals(listOf(0, 1, 2, 3), schedule.orderedItems.map { it.orderIndex })
            assertEquals(listOf("A", "B", "C"), store.templates.map { it.name }.sorted())
        }
    }
}
