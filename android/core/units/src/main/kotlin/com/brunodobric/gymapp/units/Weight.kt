package com.brunodobric.gymapp.units

import java.text.NumberFormat
import java.util.Locale

/**
 * Jedinica u kojoj korisnik vidi i unosi težinu.
 * Pravilo iz specifikacije: u bazi se težina UVIJEK sprema u kilogramima,
 * a pretvorba se radi samo za prikaz i unos.
 *
 * [raw] je isti tekst kao na iOS-u (`WeightUnit.rawValue`), jer ide u sigurnosnu kopiju.
 */
enum class WeightUnit(val raw: String, val symbol: String) {
    KILOGRAMS("kilograms", "kg"),
    POUNDS("pounds", "lbs");

    companion object {
        fun fromRaw(raw: String): WeightUnit? = entries.firstOrNull { it.raw == raw }
    }
}

object WeightConversion {
    /** Točna definicija međunarodne funte. */
    const val KILOGRAMS_PER_POUND = 0.45359237

    /** Pretvara vrijednost koju je korisnik unio u kilograme (za spremanje). */
    fun kilograms(value: Double, unit: WeightUnit): Double = when (unit) {
        WeightUnit.KILOGRAMS -> value
        WeightUnit.POUNDS -> value * KILOGRAMS_PER_POUND
    }

    /** Pretvara spremljene kilograme u jedinicu za prikaz. */
    fun value(kilograms: Double, unit: WeightUnit): Double = when (unit) {
        WeightUnit.KILOGRAMS -> kilograms
        WeightUnit.POUNDS -> kilograms / KILOGRAMS_PER_POUND
    }

    /**
     * Vrijednost za prikaz, zaokružena na korak (npr. 0,25 kg ili 0,5 lbs),
     * kako 100 lbs spremljeno kao 45,359237 kg ne bi bilo prikazano kao 99,99.
     */
    fun displayValue(kilograms: Double, unit: WeightUnit, step: Double = 0.05): Double {
        val raw = value(kilograms, unit)
        if (step <= 0) return raw
        // Množenje inverzom daje točnije rezultate od dijeljenja s 0,05.
        val stepsPerUnit = (1 / step).roundedHalfAwayFromZero()
        if (stepsPerUnit <= 0) return (raw / step).roundedHalfAwayFromZero() * step
        return (raw * stepsPerUnit).roundedHalfAwayFromZero() / stepsPerUnit
    }
}

/** Formatira težinu za prikaz u retku serije, sažetku i grafovima. */
class WeightFormatter(val unit: WeightUnit, val locale: Locale = Locale.getDefault()) {

    /** Samo broj, npr. "82,5". */
    fun number(kilograms: Double): String {
        val value = WeightConversion.displayValue(kilograms, unit)
        return NumberFormats.decimal(locale, grouping = true).format(value)
    }

    /** Broj s jedinicom, npr. "82,5 kg". */
    fun string(kilograms: Double): String = "${number(kilograms)} ${unit.symbol}"
}

/** Formatiranje brojeva s najviše dvije decimale, kao Swiftov `.precision(.fractionLength(0...2))`. */
internal object NumberFormats {
    fun decimal(locale: Locale, grouping: Boolean): NumberFormat =
        NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = 0
            maximumFractionDigits = 2
            isGroupingUsed = grouping
        }
}
