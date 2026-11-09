package com.brunodobric.gymapp.units

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sign

/**
 * Zaokruživanje na najbliži cijeli broj, a polovica od nule (2,5 → 3, −2,5 → −3).
 *
 * Isto kao Swiftov `rounded()`. Kotlinov `round` zaokružuje polovicu na parni broj (2,5 → 2), pa bi ista
 * vrijednost na iOS-u i Androidu dala različit prikaz ili različit rekord.
 */
fun Double.roundedHalfAwayFromZero(): Double {
    if (!isFinite()) return this
    return sign * floor(abs(this) + 0.5)
}
