package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.units.NumberInput
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Tekstovi za kardio na treningu (`CardioText` na iOS-u). Udaljenost je uvijek metrička (km i m), kao u unosu kardija.
 * Jedinice ("min", "s", "km", "m", "km/h", "/km") su iste na hrvatskom i engleskom.
 */
object CardioText {
    fun duration(seconds: Double): String {
        val total = seconds.roundToInt()
        val minutes = total / 60
        val rest = total % 60
        if (minutes == 0) return "$rest s"
        if (rest == 0) return "$minutes min"
        return "$minutes min $rest s"
    }

    fun distance(meters: Double, locale: Locale = Locale.getDefault()): String =
        if (meters >= 1_000) NumberInput.format(meters / 1_000, locale) + " km" else "${meters.roundToInt()} m"

    /** Prosječni tempo: "5:30 /km". Null bez vremena ili za udaljenost ispod 100 m. */
    fun pace(part: CardioPart): String? {
        val meters = part.meters ?: return null
        if (meters < 100 || part.seconds <= 0) return null
        val perKm = (part.seconds / (meters / 1_000)).roundToInt()
        return String.format(Locale.ROOT, "%d:%02d", perKm / 60, perKm % 60) + " /km"
    }

    /** Prosječna brzina: "10,9 km/h". Null bez vremena ili za udaljenost ispod 100 m. */
    fun speed(part: CardioPart, locale: Locale = Locale.getDefault()): String? {
        val meters = part.meters ?: return null
        if (meters < 100 || part.seconds <= 0) return null
        val kmh = (meters / 1_000) / (part.seconds / 3_600.0)
        val format = NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = 1
            maximumFractionDigits = 1
        }
        return format.format(kmh) + " km/h"
    }
}
