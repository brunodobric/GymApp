package com.brunodobric.gymapp.units

import java.util.Locale

/**
 * Pretvorba teksta iz polja u brojeve i natrag. Prihvaća i zarez i točku kao decimalni znak.
 *
 * Prihvaća samo konačne brojeve od nule do [MAXIMUM]: tekst kao "inf", "nan", "-20" ili "1e400"
 * (lijepljenje, vanjska tipkovnica) daje `null`, da u bazu ne uđe beskonačna ili negativna vrijednost.
 */
object NumberInput {
    /** Najveća vrijednost koju polje prihvaća. Dovoljno za težinu, udaljenost i mjere tijela. */
    const val MAXIMUM: Double = 100_000.0

    // Samo znamenke s jednim decimalnim znakom i po želji eksponentom. Javin parseDouble bi inače
    // prihvatio i "0x1p3", "10f" ili "Infinity".
    private val pattern = Regex("""^[+-]?(\d+([.,]\d*)?|[.,]\d+)([eE][+-]?\d+)?$""")

    @Suppress("UNUSED_PARAMETER")
    fun parse(text: String, locale: Locale = Locale.getDefault()): Double? {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || !pattern.matches(trimmed)) return null
        val value = trimmed.replace(',', '.').toDoubleOrNull() ?: return null
        return value.takeIf(::isAcceptable)
    }

    /** Broj je konačan i u dopuštenom rasponu (0 do [MAXIMUM]). Koristi ga i uvoz sigurnosne kopije. */
    fun isAcceptable(value: Double): Boolean = value.isFinite() && value >= 0 && value <= MAXIMUM

    fun format(value: Double?, locale: Locale = Locale.getDefault()): String {
        if (value == null || !value.isFinite()) return ""
        return NumberFormats.decimal(locale, grouping = false).format(value)
    }
}

/**
 * Trajanje u poljima: "1:30" ili samo sekunde ("90").
 *
 * Negativni dijelovi i trajanje dulje od [MAXIMUM_SECONDS] daju `null`.
 */
object DurationInput {
    /** Najdulje trajanje koje polje prihvaća: tjedan dana. */
    const val MAXIMUM_SECONDS = 7 * 24 * 3600

    fun parse(text: String): Int? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null
        val parts = trimmed.split(":")
        if (parts.size !in 1..3) return null
        var total = 0
        for (part in parts) {
            // Svaki dio je između 0 i najduljeg trajanja, pa množenje sa 60 ne može preliti Int.
            val value = part.toIntOrNull() ?: return null
            if (value < 0 || value > MAXIMUM_SECONDS) return null
            total = total * 60 + value
            if (total > MAXIMUM_SECONDS) return null
        }
        return total
    }

    fun format(seconds: Int?): String {
        if (seconds == null || seconds < 0) return ""
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val rest = seconds % 60
        return if (hours > 0) {
            String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, rest)
        } else {
            String.format(Locale.ROOT, "%d:%02d", minutes, rest)
        }
    }
}
