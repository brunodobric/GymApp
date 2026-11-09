package com.brunodobric.gymapp.units

import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/UnitsTests/InputParsingTests.swift.
@DisplayName("Unos brojeva i trajanja u poljima")
class InputParsingTest {
    private val croatian = Locale.forLanguageTag("hr-HR")
    private val english = Locale.US

    @Test
    @DisplayName("Zarez i točka su decimalni znak")
    fun decimalSeparators() {
        assertEquals(82.5, NumberInput.parse("82,5", croatian))
        assertEquals(82.5, NumberInput.parse("82.5", english))
        assertEquals(100.0, NumberInput.parse(" 100 ", croatian))
        assertNull(NumberInput.parse("", croatian))
    }

    @ParameterizedTest
    @ValueSource(strings = ["inf", "-inf", "nan", "infinity", "-20", "1e400", "200000", "0x1p3", "10f", "Infinity", "NaN"])
    @DisplayName("Beskonačno, NaN, negativno i preveliko se odbija")
    fun rejectsInvalid(text: String) {
        assertNull(NumberInput.parse(text, english))
        assertNull(NumberInput.parse(text, croatian))
    }

    @Test
    @DisplayName("Prihvatljiv broj je konačan i između 0 i najvećeg")
    fun acceptable() {
        assertTrue(NumberInput.isAcceptable(0.0))
        assertTrue(NumberInput.isAcceptable(NumberInput.MAXIMUM))
        assertFalse(NumberInput.isAcceptable(-0.5))
        assertFalse(NumberInput.isAcceptable(Double.POSITIVE_INFINITY))
        assertFalse(NumberInput.isAcceptable(Double.NaN))
    }

    @Test
    @DisplayName("Prikaz broja nema više od dvije decimale, a beskonačno je prazno")
    fun format() {
        assertEquals("82,5", NumberInput.format(82.5, croatian))
        assertEquals("100", NumberInput.format(100.0, english))
        assertEquals("1000,25", NumberInput.format(1000.25, croatian))
        assertEquals("", NumberInput.format(null))
        assertEquals("", NumberInput.format(Double.POSITIVE_INFINITY))
    }

    @Test
    @DisplayName("Trajanje u sekundama, minutama i satima")
    fun durations() {
        assertEquals(90, DurationInput.parse("90"))
        assertEquals(90, DurationInput.parse("1:30"))
        assertEquals(3605, DurationInput.parse("1:00:05"))
        assertNull(DurationInput.parse(""))
    }

    @ParameterizedTest
    @ValueSource(strings = ["-5", "1:-30", "1:2:3:4", "abc", "1:", "9999999999999999999", "99999999:00"])
    @DisplayName("Neispravno ili predugo trajanje se odbija")
    fun rejectsInvalidDurations(text: String) {
        assertNull(DurationInput.parse(text))
    }

    @Test
    @DisplayName("Prikaz trajanja")
    fun durationFormat() {
        assertEquals("1:30", DurationInput.format(90))
        assertEquals("1:00:05", DurationInput.format(3605))
        assertEquals("", DurationInput.format(null))
    }
}
