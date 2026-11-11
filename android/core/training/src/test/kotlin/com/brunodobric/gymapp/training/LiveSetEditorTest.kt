package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightUnit
import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.Locale
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Isti slučajevi kao `WatchSetFieldTests` i `LiveSetEditorTests` u GymKitu. */
class LiveSetEditorTest {
    private val hr = Locale.forLanguageTag("hr-HR")
    private val kg = WeightUnit.KILOGRAMS
    private val lbs = WeightUnit.POUNDS
    private val start = Instant.ofEpochSecond(1_800_000_000)

    private fun makeSet(inputType: ExerciseInputType = ExerciseInputType.WEIGHT_REPS): SetLog {
        val engine = WorkoutEngine(GymStore())
        val session = engine.startSession("A", now = start)
        val exercise = engine.addExercise(ExerciseRef.catalog("bench", "Potisak s klupe"), inputType, session, now = start)
        return exercise.orderedSets.first()
    }

    @Test
    fun `polja prema vrsti unosa`() {
        assertEquals(listOf(SetField.WEIGHT, SetField.REPS), SetField.fields(ExerciseInputType.WEIGHT_REPS))
        assertEquals(listOf(SetField.EXTRA_WEIGHT, SetField.REPS), SetField.fields(ExerciseInputType.ASSISTED))
        assertEquals(listOf(SetField.REPS), SetField.fields(ExerciseInputType.BODYWEIGHT))
        assertEquals(listOf(SetField.DURATION, SetField.DISTANCE), SetField.fields(ExerciseInputType.DURATION_DISTANCE))
    }

    @Test
    fun `tezina se upisuje u kilogramima i ne zaokruzuje na korak`() {
        val values = SetFieldValues()
        SetField.WEIGHT.apply(100.01, values, lbs)
        assertTrue(abs((values.weightKg ?: 0.0) - 100 * WeightConversion.KILOGRAMS_PER_POUND) < 1e-9)
        assertEquals(100.0, SetField.WEIGHT.value(values, lbs))
        assertEquals("100", SetField.WEIGHT.text(values, lbs, hr))

        SetField.WEIGHT.apply(83.0, values, kg)
        assertEquals(83.0, values.weightKg)
        SetField.WEIGHT.apply(81.24, values, kg)
        assertEquals(81.25, values.weightKg)
        assertEquals("81,25", SetField.WEIGHT.text(values, kg, hr))

        SetField.REPS.apply(-3.0, values, kg)
        assertEquals(0, values.reps)
    }

    @Test
    fun `ista vrijednost ne biljezi promjenu, a prazno polje se popunjava i nulom`() {
        val values = SetFieldValues(weightKg = 80.0, reps = 8, durationSeconds = 95)
        assertTrue(SetField.WEIGHT.matches(80.0, values, kg))
        assertFalse(SetField.WEIGHT.matches(81.25, values, kg))
        assertTrue(SetField.WEIGHT.matches(80.01, values, kg))
        assertTrue(SetField.REPS.matches(8.0, values, kg))
        assertFalse(SetField.DISTANCE.matches(0.0, values, kg))
        assertEquals("1:35", SetField.DURATION.text(values, kg))
    }

    @Test
    fun `korak tezine je korak vjezbe, a bez njega korak jedinice`() {
        assertEquals(2.5, SetField.WEIGHT.step(kg))
        assertEquals(5.0, SetField.WEIGHT.step(lbs))
        assertEquals(2.0, SetField.WEIGHT.step(kg, 2.0))
        assertEquals(1.25, SetField.EXTRA_WEIGHT.step(kg, 1.25))
        assertEquals(2.5, SetField.WEIGHT.step(kg, 0.0))
        assertEquals(1.0, SetField.REPS.step(kg, 2.0))
    }

    @Test
    fun `tezina ide na sljedecu vrijednost na koraku`() {
        val weight = SetField.WEIGHT
        assertEquals(82.5, weight.moved(80.0, 1, 2.5))
        assertEquals(77.5, weight.moved(80.0, -1, 2.5))
        assertEquals(85.0, weight.moved(83.0, 1, 2.5))
        assertEquals(82.5, weight.moved(83.0, -1, 2.5))
        assertEquals(12.0, weight.moved(11.0, 1, 2.0))
        assertEquals(2.0, weight.moved(0.0, 1, 2.0))
        assertEquals(7.0, SetField.REPS.moved(8.0, -1, 1.0))
        assertEquals(98.0, SetField.DURATION.moved(93.0, 1, 5.0))
    }

    @Test
    fun `vrijednosti s jedinicom, prazno polje kao crtica`() {
        val set = makeSet()
        set.weightKg = 82.5
        set.reps = null
        val values = LiveSetEditor.values(set, ExerciseInputType.WEIGHT_REPS, kg, hr)
        assertEquals(listOf(SetField.WEIGHT, SetField.REPS), values.map { it.field })
        assertEquals("82,5", values[0].text)
        assertEquals("kg", values[0].unitSymbol)
        assertTrue(values[0].canDecrease && values[0].canIncrease)
        assertEquals("–", values[1].text)
        assertEquals("", values[1].unitSymbol)
        assertFalse(values[1].canDecrease)
        assertTrue(values[1].canIncrease)
    }

    @Test
    fun `plus i minus mijenjaju za jedan korak, tezina ostaje u kilogramima`() {
        val set = makeSet()
        set.weightKg = 80.0
        set.reps = 8
        assertTrue(LiveSetEditor.adjust(set, SetField.WEIGHT, 1, kg))
        assertEquals(82.5, set.weightKg)
        assertTrue(LiveSetEditor.adjust(set, SetField.REPS, -1, kg))
        assertEquals(7, set.reps)

        set.weightKg = 10.0
        assertTrue(LiveSetEditor.adjust(set, SetField.WEIGHT, 1, kg, 2.0))
        assertEquals(12.0, set.weightKg)

        set.weightKg = 100 * WeightConversion.KILOGRAMS_PER_POUND
        assertTrue(LiveSetEditor.adjust(set, SetField.WEIGHT, 1, lbs))
        assertTrue(abs((set.weightKg ?: 0.0) - 105 * WeightConversion.KILOGRAMS_PER_POUND) < 1e-9)

        set.weightKg = 83.0
        assertTrue(LiveSetEditor.adjust(set, SetField.WEIGHT, -1, kg, 2.5))
        assertEquals(82.5, set.weightKg)
    }

    @Test
    fun `na rubu raspona i u praznom polju minus ne mijenja nista`() {
        val set = makeSet()
        set.reps = 0
        assertFalse(LiveSetEditor.adjust(set, SetField.REPS, -1, kg))
        assertEquals(0, set.reps)
        set.weightKg = null
        assertFalse(LiveSetEditor.adjust(set, SetField.WEIGHT, -1, kg))
        assertNull(set.weightKg)
        assertTrue(LiveSetEditor.adjust(set, SetField.WEIGHT, 1, kg))
        assertEquals(2.5, set.weightKg)
    }

    @Test
    fun `trajanje i udaljenost`() {
        val set = makeSet(ExerciseInputType.DURATION_DISTANCE)
        set.durationSeconds = 90
        set.distanceMeters = 400.0
        val values = LiveSetEditor.values(set, ExerciseInputType.DURATION_DISTANCE, kg, hr)
        assertEquals(listOf("1:30", "400"), values.map { it.text })
        assertEquals(listOf("", "m"), values.map { it.unitSymbol })
        assertTrue(LiveSetEditor.adjust(set, SetField.DURATION, 1, kg))
        assertEquals(95, set.durationSeconds)
        assertTrue(LiveSetEditor.adjust(set, SetField.DISTANCE, -1, kg))
        assertEquals(350.0, set.distanceMeters)
    }

    @Test
    fun `prosli put prema mjestu serije`() {
        val engine = WorkoutEngine(GymStore())
        val session = engine.startSession("A", now = start)
        val exercise = engine.addExercise(ExerciseRef.catalog("bench", "Potisak s klupe"), ExerciseInputType.WEIGHT_REPS, session, now = start)
        val previous = listOf(SetValues(weightKg = 30.0, reps = 12), SetValues(weightKg = 32.5, reps = 10))
        val sets = exercise.orderedSets
        assertEquals("30 kg\n12 ×", LiveSetEditor.previousText(sets[0], ExerciseInputType.WEIGHT_REPS, previous, kg, hr))
        assertEquals("32,5 kg\n10 ×", LiveSetEditor.previousText(sets[1], ExerciseInputType.WEIGHT_REPS, previous, kg, hr))
        assertEquals("32,5 kg\n10 ×", LiveSetEditor.previousText(sets[2], ExerciseInputType.WEIGHT_REPS, previous, kg, hr))
        assertNull(LiveSetEditor.previousText(sets[0], ExerciseInputType.WEIGHT_REPS, emptyList(), kg))
    }

    @Test
    fun `prosli put za vlastitu tezinu i kardio`() {
        val engine = WorkoutEngine(GymStore())
        val session = engine.startSession("A", now = start)
        val pullUps = engine.addExercise(ExerciseRef.catalog("row", "Veslanje"), ExerciseInputType.BODYWEIGHT, session, now = start)
        val run = engine.addExercise(ExerciseRef.catalog("bench", "Potisak s klupe"), ExerciseInputType.DURATION_DISTANCE, session, now = start)
        assertEquals("8 ×", LiveSetEditor.previousText(pullUps.orderedSets[0], ExerciseInputType.BODYWEIGHT, listOf(SetValues(reps = 8)), kg))
        assertEquals(
            "1:30\n400 m",
            LiveSetEditor.previousText(
                run.orderedSets[0], ExerciseInputType.DURATION_DISTANCE,
                listOf(SetValues(durationSeconds = 90, distanceMeters = 400.0)), kg, hr,
            ),
        )
    }
}
