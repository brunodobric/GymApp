package com.brunodobric.gymapp.units

import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/UnitsTests/WheelOptionsTests.swift.
@DisplayName("Kotačić za unos serije")
class WheelOptionsTest {
    private val kg = WeightUnit.KILOGRAMS
    private val lbs = WeightUnit.POUNDS

    @Test
    @DisplayName("Kilogrami idu od 0 do 500 u koracima od 2,5")
    fun kilogramSteps() {
        val values = WheelOptions.weights(kg)
        assertEquals(0.0, values.first())
        assertEquals(2.5, values[1])
        assertEquals(500.0, values.last())
        assertEquals(201, values.size)
    }

    @Test
    @DisplayName("Funte idu od 0 do 1100 u koracima od 5")
    fun poundSteps() {
        val values = WheelOptions.weights(lbs)
        assertEquals(5.0, values[1])
        assertEquals(1100.0, values.last())
        assertEquals(221, values.size)
    }

    @Test
    @DisplayName("Korak vježbe mijenja razmak, a najveća težina ostaje")
    fun customStep() {
        val dumbbells = WheelOptions.weights(kg, step = 2.0)
        assertEquals(listOf(0.0, 2.0, 4.0, 6.0), dumbbells.take(4))
        assertEquals(500.0, dumbbells.last())
        assertEquals(251, dumbbells.size)

        val micro = WheelOptions.weights(kg, step = 1.25)
        assertEquals(1.25, micro[1])
        assertTrue(81.25 in micro)
        assertEquals(500.0, micro.last())

        // Korak koji ne dijeli najveću težinu staje ispod nje.
        assertEquals(1095.0, WheelOptions.weights(lbs, step = 15.0).last())
        // Nevaljan korak vraća korak jedinice.
        assertEquals(2.5, WheelOptions.weights(kg, step = 0.0)[1])
        assertTrue(13.0 in WheelOptions.weights(kg, step = 2.0, including = 13.0))
    }

    @Test
    @DisplayName("Težina izvan koraka dodaje se na svoje mjesto")
    fun offStepWeight() {
        val values = WheelOptions.weights(kg, including = 83.0)
        assertEquals(202, values.size)
        val index = values.indexOf(83.0)
        assertTrue(index > 0)
        assertEquals(82.5, values[index - 1])
        assertEquals(85.0, values[index + 1])
    }

    @Test
    @DisplayName("Težina na koraku se ne dodaje dvaput")
    fun onStepWeight() {
        assertEquals(201, WheelOptions.weights(kg, including = 82.5).size)
        assertEquals(201, WheelOptions.weights(kg, including = 82.5004).size)
    }

    @Test
    @DisplayName("Težina veća od najveće dodaje se na kraj")
    fun weightAboveMaximum() {
        assertEquals(520.0, WheelOptions.weights(kg, including = 520.0).last())
    }

    @Test
    @DisplayName("Ponavljanja idu od 1 do 50")
    fun repsRange() {
        val values = WheelOptions.reps()
        assertEquals(1, values.first())
        assertEquals(50, values.last())
        assertEquals(50, values.size)
    }

    @Test
    @DisplayName("Ponavljanja izvan raspona dodaju se na svoje mjesto")
    fun repsOutsideRange() {
        assertEquals(60, WheelOptions.reps(including = 60).last())
        assertEquals(0, WheelOptions.reps(including = 0).first())
        assertEquals(50, WheelOptions.reps(including = 8).size)
    }

    @Test
    @DisplayName("Kotačić se postavlja na najbližu vrijednost")
    fun nearestValue() {
        val values = WheelOptions.weights(kg)
        assertEquals(80.0, WheelOptions.nearest(81.0, values))
        assertEquals(82.5, WheelOptions.nearest(81.6, values))
        assertEquals(500.0, WheelOptions.nearest(900.0, values))
        assertNull(WheelOptions.nearest(1.0, emptyList()))
    }

    @Test
    @DisplayName("Početne vrijednosti")
    fun defaults() {
        assertEquals(20.0, WheelOptions.defaultWeight(kg, isExtraLoad = false))
        assertEquals(45.0, WheelOptions.defaultWeight(lbs, isExtraLoad = false))
        assertEquals(0.0, WheelOptions.defaultWeight(kg, isExtraLoad = true))
        assertEquals(10, WheelOptions.DEFAULT_REPS)
    }
}
