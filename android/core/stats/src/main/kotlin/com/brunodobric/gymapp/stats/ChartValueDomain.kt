package com.brunodobric.gymapp.stats

import kotlin.math.abs

/**
 * Raspon osi Y za graf vrijednosti (težina, 1RM, volumen, mjere tijela).
 *
 * Raspon uvijek ima širinu: oko vrijednosti se doda razmak, a za pozitivne vrijednosti donja granica ne ide
 * ispod nule. Inače bi graf jednakih vrijednosti ostao bez oznaka na osi i vidjela bi se samo ravna crta.
 */
object ChartValueDomain {
    /** Udio raspona koji se doda iznad i ispod podataka. */
    internal const val PADDING_FRACTION = 0.1

    fun domain(values: List<Double>): ClosedFloatingPointRange<Double> {
        val finite = values.filter { it.isFinite() }
        val low = finite.minOrNull() ?: return 0.0..1.0
        val high = finite.max()
        val span = high - low
        val padding = if (span > maxOf(abs(high), 1.0) * 1e-9) {
            span * PADDING_FRACTION
        } else {
            // Sve vrijednosti iste: ±10 % vrijednosti, najmanje 1 jedinica.
            maxOf(abs(high) * PADDING_FRACTION, 1.0)
        }
        val lower = if (low >= 0) maxOf(low - padding, 0.0) else low - padding
        return lower..(high + padding)
    }
}
