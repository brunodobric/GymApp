package com.brunodobric.gymapp.training

import org.junit.jupiter.api.Test
import java.time.Instant
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StopwatchTest {
    private val base = Instant.ofEpochSecond(1_800_000_000)

    @Test
    fun `vrijeme teče od početka, pauza ga zadržava, a nastavak dodaje`() {
        var watch = Stopwatch(UUID.randomUUID(), base)
        assertTrue(watch.isRunning)
        assertEquals(90, watch.elapsedSeconds(base.plusSeconds(90)))

        watch = watch.pause(base.plusSeconds(100))
        assertFalse(watch.isRunning)
        assertEquals(100, watch.elapsedSeconds(base.plusSeconds(500)))

        watch = watch.resume(base.plusSeconds(200))
        assertEquals(130, watch.elapsedSeconds(base.plusSeconds(230)))
        assertEquals(base.plusSeconds(100), watch.displayStart(base.plusSeconds(230)))
    }

    @Test
    fun `prekidač mijenja stanje, a dvostruka pauza ništa ne mijenja`() {
        var watch = Stopwatch(UUID.randomUUID(), base)
        watch = watch.toggle(base.plusSeconds(10))
        watch = watch.pause(base.plusSeconds(50))
        assertEquals(10, watch.elapsedSeconds(base.plusSeconds(60)))
        watch = watch.toggle(base.plusSeconds(60))
        assertTrue(watch.isRunning)
        assertEquals(15, watch.elapsedSeconds(base.plusSeconds(65)))
    }
}
