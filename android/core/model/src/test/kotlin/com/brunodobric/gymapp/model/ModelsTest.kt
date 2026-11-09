package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCategory
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.catalog.uppercaseString
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightUnit
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.UUID
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ModelsTest {

    @Test
    fun `predložak čuva redoslijed vježbi i serija preko orderIndex`() {
        val store = GymStore()
        val template = store.insert(WorkoutTemplate("Push"))
        listOf(squat, bench).withIndex().reversed().forEach { (index, ref) ->
            val exercise = template.add(TemplateExercise(index, ref))
            (2 downTo 0).forEach { setIndex ->
                exercise.add(TemplateSet(setIndex, targetWeightKg = 60 + setIndex * 5.0, targetReps = 8))
            }
        }
        store.save()

        val ordered = GymStore(store.persistence).templates.single().orderedExercises
        assertEquals(listOf("Squat", "Bench press"), ordered.map { it.exerciseName })
        assertEquals(listOf(0, 1, 2), ordered[0].orderedSets.map { it.orderIndex })
        assertEquals(listOf(60.0, 65.0, 70.0), ordered[0].orderedSets.map { it.targetWeightKg })
    }

    @Test
    fun `brisanje predloška ne briše odrađene treninge`() {
        val store = GymStore()
        val template = store.insert(WorkoutTemplate("Pull"))
        template.add(TemplateExercise(0, bench))
        store.makeSession(bench, Instant.now()).templateId = template.id
        store.save()

        store.delete(template)
        store.save()

        val reloaded = GymStore(store.persistence)
        assertTrue(reloaded.templates.isEmpty())
        assertTrue(reloaded.templateExercises.isEmpty())
        assertEquals(1, reloaded.sessions.size)
        assertEquals(1, reloaded.sessions[0].orderedExercises.size)
        assertEquals(1, reloaded.sessions[0].orderedExercises[0].orderedSets.size)
    }

    @Test
    fun `brisanje rasporeda ne briše treninge ni predloške`() {
        val store = GymStore()
        val template = store.insert(WorkoutTemplate("Legs"))
        val schedule = store.insert(Schedule("PPL"))
        schedule.add(ScheduleItem(0, ScheduleItemKind.WORKOUT, template.id))
        store.makeSession(squat, Instant.now())
        store.save()

        store.delete(schedule)
        store.save()

        val reloaded = GymStore(store.persistence)
        assertTrue(reloaded.scheduleItems.isEmpty())
        assertEquals(1, reloaded.templates.size)
        assertEquals(1, reloaded.sessions.size)
    }

    @Test
    fun `brisanje treninga briše njegove vježbe i serije`() {
        val store = GymStore()
        val session = store.makeSession(bench, Instant.now(), sets = listOf(80.0 to 8, 85.0 to 6))
        store.save()

        store.delete(session)
        store.save()

        val reloaded = GymStore(store.persistence)
        assertTrue(reloaded.sessionExercises.isEmpty())
        assertTrue(reloaded.setLogs.isEmpty())
        assertTrue(store.persistence.loadAll().isEmpty())
    }

    @Test
    fun `ključ vježbe razlikuje katalog i vlastite vježbe`() {
        val id = UUID.randomUUID()
        assertEquals("c:bench-press", bench.key)
        assertEquals("u:${id.toString().uppercase()}", ExerciseRef.custom(id, "Moja").key)
    }

    @Test
    fun `zamjena vježbe u treningu ažurira ključ za upite`() {
        val exercise = SessionExercise(0, bench)
        assertEquals("c:bench-press", exercise.exerciseKey)
        exercise.exercise = squat
        assertEquals("c:squat", exercise.exerciseKey)
        assertEquals("Squat", exercise.exerciseName)
    }

    @Test
    fun `RPE prihvaća samo 1 do 10 u koracima od 0,5`() {
        listOf(1.0, 1.5, 7.5, 10.0).forEach { assertTrue(RPE.isValid(it)) }
        listOf(0.0, 0.5, 7.25, 10.5, 11.0, -1.0).forEach { assertFalse(RPE.isValid(it)) }
        assertEquals(1.5, RPE.rirFromRpe(8.5))
        assertEquals(8.0, RPE.rpeFromRir(2.0))
    }

    @Test
    fun `postavke imaju tvorničke vrijednosti i pretvaraju popis ploča`() {
        val store = GymStore()
        val settings = store.settings()
        assertEquals(WeightUnit.KILOGRAMS, settings.weightUnit)
        assertEquals(90, settings.defaultRestSeconds)
        assertEquals(EffortScale.RPE, settings.effortScale)
        assertEquals(listOf(1.25, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0), settings.availablePlatesKg)

        settings.weightUnit = WeightUnit.POUNDS
        settings.availablePlatesKg = listOf(2.5, 5.0)
        assertEquals("2.5,5.0", settings.availablePlatesRaw)
        // Drugi poziv vraća isti zapis, ne stvara novi.
        assertEquals(settings.id, store.settings().id)
    }

    @Test
    fun `obavijest u tijeku prati temu i boju aplikacije dok se ne isključi`() {
        val settings = GymStore().settings()
        assertTrue(settings.liveActivityFollowsApp)
        settings.theme = AppTheme.LIGHT
        settings.accent = AccentChoice.PURPLE
        assertEquals(AppTheme.LIGHT, settings.effectiveLiveActivityTheme)
        assertEquals(AccentChoice.PURPLE, settings.effectiveLiveActivityAccent)

        settings.changeLiveActivityFollowsApp(false)
        assertEquals(AppTheme.LIGHT, settings.liveActivityTheme)
        assertEquals(AccentChoice.PURPLE, settings.liveActivityAccent)

        settings.liveActivityTheme = AppTheme.DARK
        settings.liveActivityAccent = AccentChoice.TEAL
        settings.theme = AppTheme.SYSTEM
        assertEquals(AppTheme.DARK, settings.effectiveLiveActivityTheme)
        assertEquals(AccentChoice.TEAL, settings.effectiveLiveActivityAccent)

        settings.changeLiveActivityFollowsApp(true)
        assertEquals(AppTheme.SYSTEM, settings.effectiveLiveActivityTheme)
        assertEquals(AccentChoice.PURPLE, settings.effectiveLiveActivityAccent)
        assertEquals(AccentChoice.TEAL, settings.liveActivityAccent)
    }

    @Test
    fun `težina se u bazi čuva u kilogramima`() {
        val store = GymStore()
        val session = store.makeSession(bench, Instant.now(), sets = emptyList())
        session.exercises[0].add(SetLog(0)).weightKg = WeightConversion.kilograms(225.0, WeightUnit.POUNDS)
        store.save()
        val stored = assertNotNull(GymStore(store.persistence).setLogs.first().weightKg)
        assertTrue(abs(stored - 102.0582) < 0.001)
    }

    @Test
    fun `vrijednosti s nepoznatim tekstom vraćaju sigurnu zadanu`() {
        val set = SetLog(0)
        set.kindRaw = "nepoznato"
        assertEquals(SetKind.WORKING, set.kind)
        val session = Session("x")
        session.stateRaw = "nepoznato"
        assertEquals(SessionState.FINISHED, session.state)
    }
}

class QueriesTest {

    @Test
    fun `aktivni trening je onaj u tijeku, najnoviji`() {
        val store = GymStore()
        assertNull(store.activeSession())
        store.makeSession(bench, at(1000), SessionState.FINISHED)
        store.makeSession(bench, at(2000), SessionState.ACTIVE)
        val newest = store.makeSession(bench, at(3000), SessionState.ACTIVE)
        store.makeSession(bench, at(4000), SessionState.DISCARDED)
        assertEquals(newest.id, store.activeSession()?.id)
    }

    @Test
    fun `treninzi u rasponu - samo završeni, od najnovijeg`() {
        val store = GymStore()
        val day = 86_400L
        val base = 1_800_000_000L
        store.makeSession(bench, at(base - day))
        val first = store.makeSession(bench, at(base))
        val second = store.makeSession(bench, at(base + day))
        store.makeSession(bench, at(base + 2 * day), SessionState.ACTIVE)
        store.makeSession(bench, at(base + 3 * day), SessionState.DISCARDED)
        store.makeSession(bench, at(base + 10 * day))

        val result = store.finishedSessions(at(base), at(base + 5 * day))
        assertEquals(listOf(second.id, first.id), result.map { it.id })
    }

    @Test
    fun `zadnje izvođenje vježbe preskače izbačene, nezavršene i druge vježbe`() {
        val store = GymStore()
        val base = 1_800_000_000L
        store.makeSession(bench, at(base), sets = listOf(70.0 to 8))
        store.makeSession(bench, at(base + 100), sets = listOf(80.0 to 8, 85.0 to 8))
        store.makeSession(bench, at(base + 200), sets = listOf(999.0 to 1), removed = true)
        store.makeSession(bench, at(base + 300), SessionState.ACTIVE, sets = listOf(999.0 to 1))
        store.makeSession(squat, at(base + 400), sets = listOf(999.0 to 1))

        val last = assertNotNull(store.lastPerformance(bench))
        assertEquals(listOf(80.0, 85.0), last.orderedSets.map { it.weightKg })
        assertNull(store.lastPerformance(ExerciseRef.catalog("nepoznato", "?")))
    }

    @Test
    fun `od više zapisa postavki vrijedi onaj s onboardingom, pa mijenjani, pa najmanji id`() {
        val low = UserSettings(UUID.fromString("00000000-0000-0000-0000-000000000001"))
        val high = UserSettings(UUID.fromString("00000000-0000-0000-0000-000000000002"))
        assertEquals(low, UserSettingsChoice.preferred(listOf(high, low)))
        high.defaultRestSeconds = 60
        assertEquals(high, UserSettingsChoice.preferred(listOf(low, high)))
        low.onboardingCompleted = true
        assertEquals(low, UserSettingsChoice.preferred(listOf(high, low)))
        assertNull(UserSettingsChoice.preferred(emptyList()))
        assertEquals(WeightUnit.KILOGRAMS, UserSettingsChoice.weightUnit(emptyList()))
    }
}

class CustomExerciseTest {

    @Test
    fun `vlastita vježba bez povijesti se briše`() {
        val store = GymStore()
        val exercise = store.insert(CustomExercise("Moja vježba"))
        store.save()
        assertEquals(CustomExerciseStore.RemovalResult.DELETED, CustomExerciseStore.remove(exercise, store))
        assertTrue(GymStore(store.persistence).customExercises.isEmpty())
    }

    @Test
    fun `vlastita vježba s poviješću se arhivira, a povijest ostaje`() {
        val store = GymStore()
        val exercise = store.insert(CustomExercise("Moja vježba"))
        store.makeSession(exercise.ref, Instant.now())
        store.save()
        assertEquals(CustomExerciseStore.RemovalResult.ARCHIVED, CustomExerciseStore.remove(exercise, store))
        val reloaded = GymStore(store.persistence)
        assertTrue(reloaded.customExercises.single().isArchived)
        assertEquals(1, reloaded.sessionExercises.size)
    }

    @Test
    fun `vlastita vježba u predlošku se također arhivira`() {
        val store = GymStore()
        val exercise = store.insert(CustomExercise("Moja vježba"))
        store.insert(WorkoutTemplate("Dan A")).add(TemplateExercise(0, exercise.ref))
        store.save()
        assertEquals(CustomExerciseStore.RemovalResult.ARCHIVED, CustomExerciseStore.remove(exercise, store))
    }

    @Test
    fun `svojstva vlastite vježbe i sažetak`() {
        val exercise = CustomExercise("Povlačenje užeta", ExerciseInputType.DURATION)
        exercise.category = ExerciseCategory.BACK
        exercise.equipment = Equipment.OTHER
        exercise.muscles = listOf(Muscle.LATS, Muscle.BICEPS)

        assertEquals(ExerciseInputType.DURATION, exercise.inputType)
        assertEquals(listOf(Muscle.LATS, Muscle.BICEPS), exercise.muscles)
        val summary = exercise.summary
        assertTrue(summary.isCustom)
        assertEquals(ExerciseCategory.BACK, summary.category)
        assertEquals(exercise.id, summary.ref.customExerciseId)
        assertEquals("u:${exercise.id.uppercaseString}", summary.ref.key)
    }

    @Test
    fun `vrsta vlastite vježbe - odabrana ili, za stariju vježbu, po kategoriji`() {
        val exercise = CustomExercise("Veslanje")
        assertEquals(ExerciseKind.STRENGTH, exercise.kind)
        exercise.category = ExerciseCategory.CARDIO
        assertEquals(ExerciseKind.CARDIO, exercise.kind)
        assertTrue(exercise.kindRaw.isEmpty())
        exercise.kind = ExerciseKind.WARM_UP
        assertEquals("warmUp", exercise.kindRaw)
        assertEquals(ExerciseKind.WARM_UP, exercise.summary.kind)
        exercise.kindRaw = "nepoznato"
        assertEquals(ExerciseKind.CARDIO, exercise.kind)
    }

    @Test
    fun `referenca vodi na vježbu iz kataloga ili na vlastitu vježbu`() {
        val id = UUID.randomUUID()
        assertEquals(ExerciseSummary.Source.Catalog("bench-press"), ExerciseRef.catalog("bench-press", "Bench").source)
        assertEquals(ExerciseSummary.Source.Custom(id), ExerciseRef.custom(id, "Moja").source)
        assertNull(ExerciseRef(name = "Uvezena").source)
        val exercise = CustomExercise("Povlačenje užeta")
        assertEquals(exercise.summary.source, exercise.summary.ref.source)
    }
}

class OrderingTest {

    @Test
    fun `isto kao onMove - naprijed, natrag i više elemenata`() {
        val forward = mutableListOf("a", "b", "c", "d").apply { moveElements(listOf(0), 3) }
        assertEquals(listOf("b", "c", "a", "d"), forward)
        val backward = mutableListOf("a", "b", "c", "d").apply { moveElements(listOf(3), 0) }
        assertEquals(listOf("d", "a", "b", "c"), backward)
        val several = mutableListOf("a", "b", "c", "d", "e").apply { moveElements(listOf(0, 2), 5) }
        assertEquals(listOf("b", "d", "e", "a", "c"), several)
    }

    @Test
    fun `nepostojeći indeks se preskače, a odredište se ograničava`() {
        val list = mutableListOf(1, 2, 3)
        list.moveElements(listOf(7), 0)
        assertEquals(listOf(1, 2, 3), list)
        list.moveElements(listOf(0), 99)
        assertEquals(listOf(2, 3, 1), list)
    }
}
