package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.ReminderMode
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
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
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
        fun `ažuriranje treninga preuzima strukturu odrađenog treninga, a ciljevi ostaju`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val template = store.template("Push", listOf(bench, row, curl))
            engine.setTargets(template.orderedExercises[0].orderedSets[0], 60.0, 8)
            template.orderedExercises[0].notes = "Sjedalo 4"
            val session = TemplateStarter(store).start(template, base)
            val workout = WorkoutEngine(store)
            val (benchDone, rowDone, curlDone) = session.orderedExercises
            // Potisak: 4 serije umjesto 3, veslanje preskočeno, pregib 2 serije, dodan čučanj.
            workout.addSet(benchDone)
            for (exercise in listOf(benchDone, curlDone)) {
                val sets = exercise.orderedSets.take(if (exercise === curlDone) 2 else 4)
                sets.forEach {
                    it.weightKg = it.weightKg ?: 20.0
                    it.reps = it.reps ?: 10
                    workout.completeSet(it, 90, base)
                }
            }
            val squatDone = workout.addExercise(squat, WR, session)
            squatDone.orderedSets.first().apply { weightKg = 100.0; reps = 5 }
            workout.completeSet(squatDone.orderedSets.first(), 90, base)
            rowDone.orderedSets.forEach { it.completedAt = null }

            val updater = TemplateUpdater(store)
            val changes = updater.changes(session, template)
            assertEquals(listOf("Čučanj"), changes.added)
            assertEquals(listOf("Veslanje"), changes.removed)
            assertEquals(
                listOf(TemplateChanges.SetCount("Potisak s klupe", 3, 4), TemplateChanges.SetCount("Pregib", 3, 2)),
                changes.setCounts,
            )
            assertFalse(changes.isEmpty)

            updater.updateTemplate(template, session)
            val updated = template.orderedExercises
            assertEquals(listOf("Potisak s klupe", "Pregib", "Čučanj"), updated.map { it.exerciseName })
            assertEquals(listOf(4, 2, 1), updated.map { it.orderedSets.size })
            assertEquals(60.0, updated[0].orderedSets[0].targetWeightKg)
            assertEquals("Sjedalo 4", updated[0].notes)
            assertEquals(5, updated[2].orderedSets[0].targetReps)
            assertNull(updated[2].orderedSets[0].targetWeightKg)
            assertTrue(updater.changes(session, template).isEmpty)
        }

        @Test
        fun `raspon iz predloška, prijedlog veće težine i bilješka idu u trening`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val result = store.template("Push", listOf(bench))
            val exercise = result.orderedExercises[0]
            exercise.notes = "  Sjedalo 4  "
            exercise.orderedSets.forEach { engine.setTargets(it, null, 8); it.targetRepsMax = 12 }

            val first = TemplateStarter(store) { 2.5 }.start(result, base)
            val started = first.orderedExercises[0]
            assertEquals(8, started.targetRepsMin)
            assertEquals(12, started.targetRepsMax)
            assertEquals("Sjedalo 4", started.notes)
            assertNull(started.loadChangeKg)
            val workout = WorkoutEngine(store)
            started.orderedSets.forEach { set ->
                set.weightKg = 80.0
                set.reps = 12
                workout.completeSet(set, 90, base)
            }
            workout.finishSession(first, now = base.plusSeconds(3600))

            val second = TemplateStarter(store) { 2.5 }.start(result, base.plusSeconds(DAY))
            val next = second.orderedExercises[0]
            assertEquals(2.5, next.loadChangeKg)
            assertTrue(next.orderedSets.all { it.weightKg == 82.5 && it.reps == 8 })

            // Isključen prijedlog veće težine: težina ostaje kao prošli put.
            workout.discardSession(second)
            store.settings().suggestsHeavierWeight = false
            val third = TemplateStarter(store) { 2.5 }.start(result, base.plusSeconds(2 * DAY))
            val plain = third.orderedExercises[0]
            assertNull(plain.loadChangeKg)
            assertTrue(plain.orderedSets.all { it.weightKg == 80.0 && it.reps == 12 })
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
    inner class ReminderTests {
        private val utc: ZoneId = ZoneOffset.UTC
        private val evening = 18 * 60
        private val today = LocalDate.of(2027, 1, 15).atStartOfDay(utc).toInstant()

        @Test
        fun `fiksni dani - odabrani dani u idućih 14 dana, u zadano vrijeme`() {
            val dates = ReminderPlanner.fixedDates(listOf(2, 4, 6), evening, base, emptySet(), utc)
            assertEquals(6, dates.size)
            assertEquals(today.plusSeconds(18 * 3600), dates.first())
            assertTrue(dates.all { it.atZone(utc).dayOfWeek.appleWeekday in listOf(2, 4, 6) })
        }

        @Test
        fun `fiksni dani - dan s već odrađenim treningom se preskače, a prošlo vrijeme ne`() {
            val dates = ReminderPlanner.fixedDates(listOf(6), evening, base, setOf(LocalDate.of(2027, 1, 15)), utc)
            assertEquals(listOf(today.plusSeconds(7 * DAY + 18 * 3600)), dates)
            val late = ReminderPlanner.fixedDates(listOf(6), evening, base.plusSeconds(11 * 3600), emptySet(), utc)
            assertEquals(today.plusSeconds(7 * DAY + 18 * 3600), late.first())
        }

        @Test
        fun `fleksibilno - razmak od zadnjeg treninga, rest dani ga produljuju`() {
            val last = base.plusSeconds(12 * 3600)
            assertEquals(today.plusSeconds(DAY + 18 * 3600), ReminderPlanner.flexibleDate(last, 1, 0, evening, base, utc))
            assertEquals(today.plusSeconds(2 * DAY + 18 * 3600), ReminderPlanner.flexibleDate(last, 1, 1, evening, base, utc))
        }

        @Test
        fun `fleksibilno - bez treninga ili uz prošao termin stiže sljedeće zadano vrijeme`() {
            assertEquals(today.plusSeconds(18 * 3600), ReminderPlanner.flexibleDate(null, 1, 0, evening, base, utc))
            assertEquals(
                today.plusSeconds(DAY + 18 * 3600),
                ReminderPlanner.flexibleDate(base.minusSeconds(5 * DAY), 1, 0, evening, base.plusSeconds(11 * 3600), utc),
            )
        }

        @Test
        fun `zakazivanje iz baze - oba načina, bez podsjetnika tijekom aktivnog treninga`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (flexible, _) = store.abcSchedule(null)
            flexible.reminderMinutes = evening
            flexible.reminderMode = ReminderMode.FLEXIBLE
            val (fixed, _) = store.abcSchedule(null)
            fixed.reminderMinutes = evening
            fixed.reminderMode = ReminderMode.FIXED_DAYS
            fixed.weekdays = listOf(6)
            val (silent, _) = store.abcSchedule(null)
            silent.reminderMinutes = null

            val builder = ReminderBuilder(store)
            val reminders = builder.reminders(base, utc)
            assertEquals(1, reminders.count { it.scheduleId == flexible.id })
            assertEquals(2, reminders.count { it.scheduleId == fixed.id })
            assertTrue(reminders.none { it.scheduleId == silent.id })
            assertTrue(reminders.all { it.workoutName == "A" })

            // Odrađen trening iz fiksnog rasporeda: današnji petak otpada.
            store.doWorkout(engine.nextWorkout(fixed), base)
            val afterWorkout = builder.reminders(base.plusSeconds(3600), utc)
            assertEquals(1, afterWorkout.count { it.scheduleId == fixed.id })
            val flexibleNext = assertNotNull(afterWorkout.firstOrNull { it.scheduleId == flexible.id })
            assertTrue(flexibleNext.fireDate > base)

            // Tijekom aktivnog treninga nema podsjetnika.
            TemplateStarter(store).start(assertNotNull(engine.nextWorkout(flexible)), base.plusSeconds(7200))
            assertTrue(builder.reminders(base.plusSeconds(7300), utc).isEmpty())
        }

        @Test
        fun `identifikator je isti kao na iOS-u`() {
            val id = java.util.UUID.fromString("0a1b2c3d-0000-4000-8000-00000000abcd")
            val reminder = PlannedReminder(id, "R", "A", base)
            assertEquals("schedule-0A1B2C3D-0000-4000-8000-00000000ABCD-1800000000", reminder.identifier)
        }
    }

    @Nested
    inner class ReminderTimeTests {
        private val zagreb = ZoneId.of("Europe/Zagreb")

        @Test
        fun `minute od ponoći u datum i natrag`() {
            for (minutes in listOf(0, 7 * 60 + 30, 18 * 60 + 5, 23 * 60 + 59)) {
                val date = ReminderTime.date(minutes, base, zagreb)
                assertEquals(minutes, ReminderTime.minutes(date, zagreb))
            }
        }

        @Test
        fun `vrijeme izvan dana se ograničava na dan`() {
            assertEquals(0, ReminderTime.minutes(ReminderTime.date(-5, base, zagreb), zagreb))
            assertEquals(1439, ReminderTime.minutes(ReminderTime.date(2000, base, zagreb), zagreb))
        }

        @Test
        fun `dan se uključuje i isključuje, a popis ostaje sortiran`() {
            assertEquals(listOf(2, 4, 6), ReminderTime.toggling(2, listOf(4, 6)))
            assertEquals(listOf(2, 6), ReminderTime.toggling(4, listOf(2, 4, 6)))
            assertEquals(listOf(1), ReminderTime.toggling(1, emptyList()))
            assertEquals(2, ReminderTime.weekdaysFromMonday.first())
            assertEquals(1, ReminderTime.weekdaysFromMonday.last())
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
        @Test
        fun `raspored se vraća na stanje prije uređivanja - polja, niz i izmjene ciklusa`() {
            val store = newStore()
            val engine = ScheduleEngine(store)
            val (schedule, templates) = store.abcSchedule(4)
            engine.skipNextWorkout(schedule)
            val before = schedule.orderedItems.map { it.id }
            val snapshot = ScheduleSnapshot(schedule, store)

            schedule.name = "Promijenjeno"
            schedule.cycleCount = null
            schedule.reminderMinutes = 7 * 60
            engine.setActive(false, schedule)
            engine.removeItem(schedule.orderedItems[2])
            engine.addWorkout(templates[0], schedule)
            engine.moveItems(schedule, listOf(0), 3)
            engine.unskip(engine.skippedWorkouts(schedule).first().change, schedule)

            snapshot.restore(schedule, store)
            assertEquals("ABC", schedule.name)
            assertEquals(4, schedule.cycleCount)
            assertNull(schedule.reminderMinutes)
            assertTrue(schedule.isActive)
            assertEquals(before, schedule.orderedItems.map { it.id })
            assertEquals(listOf("A"), engine.skippedWorkouts(schedule).map { it.templateName })
            assertEquals("B", engine.nextWorkout(schedule)?.template?.name)
            assertEquals(4, store.scheduleItems.size)
        }

        @Test
        fun `trening se vraća na stanje prije uređivanja - naziv, vježbe i serije`() {
            val store = newStore()
            val engine = TemplateEngine(store)
            val workout = store.template("Gornji dio", listOf(bench, row))
            val benchExercise = workout.orderedExercises.first()
            benchExercise.orderedSets.first().targetReps = 8
            store.save()
            val setCount = benchExercise.orderedSets.size
            val snapshot = TemplateSnapshot(workout)

            workout.name = "Drugo"
            benchExercise.orderedSets.first().targetReps = 12
            engine.addSet(benchExercise)
            engine.removeExercise(workout.orderedExercises[1])
            engine.addExercise(curl, WR, workout)
            engine.moveExercises(workout, listOf(0), 2)

            snapshot.restore(workout, store)
            assertEquals("Gornji dio", workout.name)
            assertEquals(listOf(bench.name, row.name), workout.orderedExercises.map { it.exerciseName })
            val restored = workout.orderedExercises.first()
            assertEquals(setCount, restored.orderedSets.size)
            assertEquals(8, restored.orderedSets.first().targetReps)
            assertEquals(2, store.templateExercises.size)
            // Snimka je spremljena: ponovno učitavanje iz baze daje isto stanje.
            store.rollback()
            assertEquals(listOf(bench.name, row.name), store.templates.single().orderedExercises.map { it.exerciseName })
        }
    }
}
