package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.units.WeightUnit
import org.junit.jupiter.api.Test
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Katalog s jednom vježbom s bučicama i jednom na spravi. */
private fun makeCatalog() = ExerciseCatalog.decode(
    """
    {
      "version": 2,
      "source": {"name": "MoveKit", "url": "https://movekit.com", "license": "MoveKit License Agreement v1.0"},
      "exercises": [{
        "id": "dumbbell-curl", "name": {"en": "Dumbbell Curl", "hr": "Pregib s bučicama"}, "category": "arms",
        "primaryMuscles": ["biceps"], "secondaryMuscles": [], "equipment": "dumbbell", "level": "beginner",
        "mechanic": "isolation", "movement": "pull", "inputType": "weightReps",
        "primaryRegions": [], "secondaryRegions": []
      }, {
        "id": "leg-press", "name": {"en": "Leg Press", "hr": "Nožna preša"}, "category": "legs",
        "primaryMuscles": ["quadriceps"], "secondaryMuscles": [], "equipment": "machine", "level": "beginner",
        "mechanic": "compound", "movement": "legs", "inputType": "weightReps",
        "primaryRegions": [], "secondaryRegions": []
      }]
    }
    """.trimIndent(),
)

class WeightStepsTest {
    private val kg = WeightUnit.KILOGRAMS
    private val lbs = WeightUnit.POUNDS

    @Test
    fun `zadani koraci po opremi`() {
        val steps = WeightStepSettings()
        assertEquals(2.5, steps.step(Equipment.BARBELL, kg))
        assertEquals(2.5, steps.step(Equipment.EZ_BAR, kg))
        assertEquals(2.0, steps.step(Equipment.DUMBBELL, kg))
        assertEquals(5.0, steps.step(Equipment.MACHINE, kg))
        assertEquals(5.0, steps.step(Equipment.CABLE, kg))
        assertEquals(4.0, steps.step(Equipment.KETTLEBELL, kg))
        assertEquals(2.5, steps.step(null, kg))
        assertEquals(5.0, steps.step(Equipment.BARBELL, lbs))
        assertEquals(5.0, steps.step(Equipment.DUMBBELL, lbs))
        assertEquals(10.0, steps.step(Equipment.MACHINE, lbs))
    }

    @Test
    fun `zadani korak je uvijek među ponuđenima`() {
        for (unit in WeightUnit.entries) {
            for (equipment in Equipment.entries) {
                assertTrue(WeightStepSettings.defaultStep(equipment, unit) in WeightStepSettings.choices(unit))
            }
        }
    }

    @Test
    fun `korak opreme vrijedi samo za svoju jedinicu, a zadani korak briše postavku`() {
        val steps = WeightStepSettings()
        steps.setStep(2.5, Equipment.DUMBBELL, kg)
        assertEquals(2.5, steps.step(Equipment.DUMBBELL, kg))
        assertEquals(5.0, steps.step(Equipment.DUMBBELL, lbs))
        assertEquals("dumbbell@kilograms=2.5", steps.equipmentRaw)

        steps.setStep(2.0, Equipment.DUMBBELL, kg)
        assertTrue(steps.equipmentRaw.isEmpty())
        steps.setStep(1.0, Equipment.BARBELL, kg)
        steps.setStep(null, Equipment.BARBELL, kg)
        assertTrue(steps.equipmentRaw.isEmpty())
    }

    @Test
    fun `korak vježbe vrijedi umjesto koraka opreme`() {
        val steps = WeightStepSettings()
        steps.setOverride(7.0, "c:leg-press", kg)
        assertEquals(7.0, steps.step("c:leg-press", Equipment.MACHINE, kg))
        assertEquals(10.0, steps.step("c:leg-press", Equipment.MACHINE, lbs))
        assertEquals(5.0, steps.step("c:other", Equipment.MACHINE, kg))

        steps.setOverride(null, "c:leg-press", kg)
        assertNull(steps.override("c:leg-press", kg))
        assertTrue(steps.exercisesRaw.isEmpty())
    }

    @Test
    fun `zapis se čita natrag, a neispravni unosi se preskaču`() {
        val steps = WeightStepSettings()
        steps.setStep(1.25, Equipment.BARBELL, kg)
        steps.setStep(2.5, Equipment.DUMBBELL, lbs)
        steps.setOverride(4.0, "u:${UUID.randomUUID().toString().uppercase()}", kg)
        assertEquals(steps, WeightStepSettings(steps.equipmentRaw, steps.exercisesRaw))

        val broken = WeightStepSettings(
            equipmentRaw = "barbell@kilograms=abc,=2,dumbbell@stone=2,machine@kilograms=-5,cable@kilograms=10",
            exercisesRaw = "c:x=2",
        )
        assertEquals(2.5, broken.step(Equipment.BARBELL, kg))
        assertEquals(5.0, broken.step(Equipment.MACHINE, kg))
        assertEquals(10.0, broken.step(Equipment.CABLE, kg))
        assertTrue(broken.exercisesRaw.isEmpty())
    }

    @Test
    fun `postavke spremaju korake u tekstualna polja`() {
        val settings = UserSettings()
        val steps = settings.weightSteps
        steps.setStep(2.5, Equipment.DUMBBELL, kg)
        steps.setOverride(7.0, "c:leg-press", kg)
        settings.weightSteps = steps

        assertEquals("dumbbell@kilograms=2.5", settings.equipmentWeightStepsRaw)
        assertEquals("c:leg-press@kilograms=7.0", settings.exerciseWeightStepsRaw)
        assertEquals(steps, settings.weightSteps)
    }

    @Test
    fun `korak vježbe iz kataloga, vlastite vježbe i nepoznate vježbe`() {
        val catalog = makeCatalog()
        val custom = CustomExercise("Girja").apply { equipment = Equipment.KETTLEBELL }
        val settings = UserSettings()
        settings.weightSteps = settings.weightSteps.apply { setOverride(7.0, "c:leg-press", kg) }

        val curl = ExerciseRef.catalog("dumbbell-curl", "Pregib")
        val press = ExerciseRef.catalog("leg-press", "Preša")
        val unknown = ExerciseRef.catalog("nema", "Nema")
        val step = WeightStepSettings.resolver(settings, catalog, listOf(custom))
        assertEquals(2.0, step(curl))
        assertEquals(7.0, step(press))
        assertEquals(4.0, step(custom.ref))
        assertEquals(2.5, step(unknown))
        assertEquals(2.0, settings.weightStep(curl, catalog, emptyList()))
        assertEquals(Equipment.KETTLEBELL, WeightStepSettings.equipment(custom.ref, catalog, listOf(custom)))

        settings.weightUnit = lbs
        val pounds = WeightStepSettings.resolver(settings, catalog, listOf(custom))
        assertEquals(5.0, pounds(curl))
        assertEquals(10.0, pounds(press))
        assertEquals(2.5, WeightStepSettings.resolver(null, null, emptyList())(curl))
    }
}
