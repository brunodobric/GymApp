package com.brunodobric.gymapp.training

import org.junit.jupiter.api.Test
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertNull

// Port CardioText (iOS): isti tekstovi u sažetku treninga.
class CardioTextTest {
    private val hr = Locale.forLanguageTag("hr")

    @Test
    fun `trajanje i udaljenost`() {
        assertEquals("45 s", CardioText.duration(45.0))
        assertEquals("15 min", CardioText.duration(900.0))
        assertEquals("15 min 30 s", CardioText.duration(930.0))
        assertEquals("3,2 km", CardioText.distance(3_200.0, hr))
        assertEquals("850 m", CardioText.distance(850.0, hr))
    }

    @Test
    fun `tempo i brzina`() {
        val part = CardioPart(seconds = 1_650, meters = 5_000.0)
        assertEquals("5:30 /km", CardioText.pace(part))
        assertEquals("10,9 km/h", CardioText.speed(part, hr))
        assertNull(CardioText.pace(CardioPart(seconds = 600, meters = 50.0)))
        assertNull(CardioText.speed(CardioPart(seconds = 0, meters = 5_000.0), hr))
    }
}
