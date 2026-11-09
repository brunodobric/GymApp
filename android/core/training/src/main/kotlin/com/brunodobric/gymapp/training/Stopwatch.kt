package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.units.roundedHalfAwayFromZero
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * Štoperica za seriju s trajanjem (kardio, izdržaj): pokreni, pauziraj i nastavi. Kvačica upisuje izmjereno
 * vrijeme u seriju. Vrijeme teče iz trenutka početka, pa ne treba timer koji kuca svake sekunde.
 */
data class Stopwatch(
    /** Serija koju štoperica mjeri. */
    val setId: UUID,
    /** Početak trenutnog mjerenja; null dok je pauzirana. */
    val runningSince: Instant?,
    /** Vrijeme izmjereno prije zadnje pauze, u sekundama. */
    val accumulated: Double = 0.0,
) {
    constructor(setId: UUID, startedAt: Instant) : this(setId, startedAt, 0.0)

    val isRunning: Boolean get() = runningSince != null

    /** Izmjereno vrijeme u sekundama. */
    fun elapsed(now: Instant): Double =
        accumulated + (runningSince?.let { maxOf(0.0, seconds(it, now)) } ?: 0.0)

    /** Izmjereno vrijeme u cijelim sekundama, za upis u seriju. */
    fun elapsedSeconds(now: Instant): Int = elapsed(now).roundedHalfAwayFromZero().toInt()

    /** Trenutak od kojeg brojač koji raste pokazuje izmjereno vrijeme. */
    fun displayStart(now: Instant): Instant = now.minusNanos((elapsed(now) * 1e9).toLong())

    fun pause(now: Instant): Stopwatch = if (!isRunning) this else copy(runningSince = null, accumulated = elapsed(now))

    fun resume(now: Instant): Stopwatch = if (isRunning) this else copy(runningSince = now)

    fun toggle(now: Instant): Stopwatch = if (isRunning) pause(now) else resume(now)

    private fun seconds(from: Instant, to: Instant): Double = Duration.between(from, to).toNanos() / 1e9
}
