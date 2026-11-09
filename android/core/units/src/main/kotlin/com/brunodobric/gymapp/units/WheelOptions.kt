package com.brunodobric.gymapp.units

import kotlin.math.abs
import kotlin.math.floor

/**
 * Vrijednosti koje nudi kotačić za unos težine i ponavljanja u retku serije.
 * Sve vrijednosti su u jedinici za prikaz (kg ili lbs), a pretvorba u kilograme ide pri spremanju.
 */
object WheelOptions {
    /** Najmanja i najveća ponuđena ponavljanja. */
    val repsRange = 1..50

    /** Početna ponavljanja kad serija i prošli trening nemaju vrijednost. */
    const val DEFAULT_REPS = 10

    /** Razlika ispod koje se dvije težine za prikaz smatraju jednakima (prikaz se zaokružuje na 0,05). */
    internal const val TOLERANCE = 0.001

    /**
     * Korak težine kad se ne zna oprema vježbe: 2,5 kg ili 5 lbs (najmanji uobičajeni skok s parom ploča).
     * Korak po opremi i po vježbi je u `WeightStepSettings` (model).
     */
    fun weightStep(unit: WeightUnit): Double = when (unit) {
        WeightUnit.KILOGRAMS -> 2.5
        WeightUnit.POUNDS -> 5.0
    }

    /** Najveća ponuđena težina. Veća se može upisati tipkovnicom. */
    fun maximumWeight(unit: WeightUnit): Double = when (unit) {
        WeightUnit.KILOGRAMS -> 500.0
        WeightUnit.POUNDS -> 1100.0
    }

    /**
     * Početna težina kad serija i prošli trening nemaju vrijednost: prazna olimpijska šipka,
     * a za dodatnu težinu ili pomoć nula.
     */
    fun defaultWeight(unit: WeightUnit, isExtraLoad: Boolean): Double = when {
        isExtraLoad -> 0.0
        unit == WeightUnit.KILOGRAMS -> 20.0
        else -> 45.0
    }

    /**
     * Težine od 0 do najveće u zadanom koraku (bez koraka korak jedinice). Vrijednost koja nije na koraku
     * (npr. 83 kg upisano tipkovnicom) dodaje se na svoje mjesto, da je kotačić može prikazati i da se ne
     * promijeni sama.
     */
    fun weights(unit: WeightUnit, step: Double? = null, including: Double? = null): List<Double> {
        val usedStep = step?.takeIf { it > 0 } ?: weightStep(unit)
        val count = floor(maximumWeight(unit) / usedStep).toInt()
        // Množenje (a ne zbrajanje) i zaokruživanje na 0,001, da 0,1 + 0,2 ne postane 0,30000000000000004.
        val values = (0..count).map { (it * usedStep * 1000).roundedHalfAwayFromZero() / 1000 }.toMutableList()
        if (including != null && including >= 0 && values.none { abs(it - including) < TOLERANCE }) {
            val index = values.indexOfFirst { it > including }.let { if (it < 0) values.size else it }
            values.add(index, including)
        }
        return values
    }

    /** Ponavljanja od 1 do 50, uz trenutnu vrijednost ako je izvan raspona (npr. 60 upisano tipkovnicom). */
    fun reps(including: Int? = null): List<Int> {
        val values = repsRange.toMutableList()
        if (including != null && including >= 0 && including !in repsRange) {
            val index = values.indexOfFirst { it > including }.let { if (it < 0) values.size else it }
            values.add(index, including)
        }
        return values
    }

    /** Vrijednost s popisa najbliža zadanoj, na koju se kotačić postavi kad se otvori. */
    fun nearest(value: Double, options: List<Double>): Double? = options.minByOrNull { abs(it - value) }
}
