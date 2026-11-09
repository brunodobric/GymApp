package com.brunodobric.gymapp.units

import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.util.Locale
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// Port GymKit/Tests/UnitsTests/WeightTests.swift.
@DisplayName("Pretvorba težine")
class WeightConversionTest {

    @Test
    @DisplayName("Kilogrami se ne mijenjaju")
    fun kilogramsRoundTrip() {
        assertEquals(82.5, WeightConversion.kilograms(82.5, WeightUnit.KILOGRAMS))
        assertEquals(82.5, WeightConversion.value(82.5, WeightUnit.KILOGRAMS))
    }

    @Test
    @DisplayName("Unos u funtama sprema se u kilogramima s punom preciznošću")
    fun poundsToKilograms() {
        val kg = WeightConversion.kilograms(100.0, WeightUnit.POUNDS)
        assertTrue(abs(kg - 45.359237) < 1e-9)
    }

    @ParameterizedTest
    @ValueSource(doubles = [45.0, 100.0, 135.0, 225.0, 315.0, 405.0])
    @DisplayName("Spremljena vrijednost vraća isti prikaz u funtama")
    fun poundsRoundTripDisplay(pounds: Double) {
        val stored = WeightConversion.kilograms(pounds, WeightUnit.POUNDS)
        assertTrue(abs(WeightConversion.displayValue(stored, WeightUnit.POUNDS) - pounds) < 1e-9)
    }

    @Test
    @DisplayName("Prikaz se zaokružuje na zadani korak")
    fun displayRounding() {
        assertTrue(abs(WeightConversion.displayValue(82.49, WeightUnit.KILOGRAMS, step = 0.25) - 82.5) < 1e-9)
        assertEquals(82.49, WeightConversion.displayValue(82.49, WeightUnit.KILOGRAMS, step = 0.0))
    }

    @Test
    @DisplayName("Polovica se zaokružuje od nule, kao na iOS-u")
    fun halfAwayFromZero() {
        assertEquals(3.0, 2.5.roundedHalfAwayFromZero())
        assertEquals(-3.0, (-2.5).roundedHalfAwayFromZero())
        assertEquals(2.0, 2.4.roundedHalfAwayFromZero())
    }
}

@DisplayName("Formatiranje težine")
class WeightFormatterTest {

    @Test
    @DisplayName("Hrvatski format koristi decimalni zarez")
    fun croatianFormat() {
        val formatter = WeightFormatter(WeightUnit.KILOGRAMS, Locale.forLanguageTag("hr-HR"))
        assertEquals("82,5 kg", formatter.string(82.5))
        assertEquals("80 kg", formatter.string(80.0))
    }

    @Test
    @DisplayName("Engleski format u funtama")
    fun englishPounds() {
        val formatter = WeightFormatter(WeightUnit.POUNDS, Locale.US)
        val stored = WeightConversion.kilograms(225.0, WeightUnit.POUNDS)
        assertEquals("225 lbs", formatter.string(stored))
    }
}
