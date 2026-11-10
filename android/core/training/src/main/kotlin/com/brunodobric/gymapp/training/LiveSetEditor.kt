package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.units.WeightUnit
import com.brunodobric.gymapp.units.WheelOptions
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/** Vrijednosti serije koje mijenjaju gumbi − i + (`SetSnapshot` na iOS-u, samo polja vrijednosti). */
data class SetFieldValues(
    var weightKg: Double? = null,
    var reps: Int? = null,
    var extraWeightKg: Double? = null,
    var durationSeconds: Int? = null,
    var distanceMeters: Double? = null,
)

/**
 * Polje serije koje se mijenja jednim korakom (`WatchSetField` na iOS-u, isto kao Digital Crown na satu):
 * korak težine vježbe, 1 ponavljanje, 5 sekundi ili 50 metara.
 */
enum class SetField(val raw: String) {
    WEIGHT("weight"), EXTRA_WEIGHT("extraWeight"), REPS("reps"), DURATION("duration"), DISTANCE("distance");

    val isWeight: Boolean get() = this == WEIGHT || this == EXTRA_WEIGHT

    /** Korak u jedinici prikaza. Za težinu korak vježbe, a bez njega korak jedinice (`WheelOptions`). */
    fun step(unit: WeightUnit, weightStep: Double? = null): Double = when (this) {
        WEIGHT, EXTRA_WEIGHT -> weightStep?.takeIf { it > 0 } ?: WheelOptions.weightStep(unit)
        REPS -> 1.0
        DURATION -> 5.0
        DISTANCE -> 50.0
    }

    /**
     * Vrijednost nakon [steps] koraka. Težina ide na sljedeću vrijednost na koraku, kao na kotačiću:
     * 83 kg s korakom 2,5 ide na 85 ili 82,5.
     */
    fun moved(value: Double, steps: Int, step: Double): Double {
        if (!isWeight || steps == 0 || step <= 0) return value + steps * step
        val position = value / step
        val tolerance = 1e-6
        val target = if (steps > 0) floor(position + tolerance) + steps else ceil(position - tolerance) + steps
        return target * step
    }

    fun range(unit: WeightUnit): ClosedFloatingPointRange<Double> = when (this) {
        WEIGHT, EXTRA_WEIGHT -> 0.0..(if (unit == WeightUnit.KILOGRAMS) 500.0 else 1100.0)
        REPS -> 0.0..200.0
        DURATION -> 0.0..(4 * 3600.0)
        DISTANCE -> 0.0..100_000.0
    }

    /** Vrijednost u jedinici prikaza; prazno polje daje 0. */
    fun value(values: SetFieldValues, unit: WeightUnit): Double = when (this) {
        WEIGHT -> values.weightKg?.let { WeightConversion.displayValue(it, unit) } ?: 0.0
        EXTRA_WEIGHT -> values.extraWeightKg?.let { WeightConversion.displayValue(it, unit) } ?: 0.0
        REPS -> (values.reps ?: 0).toDouble()
        DURATION -> (values.durationSeconds ?: 0).toDouble()
        DISTANCE -> values.distanceMeters ?: 0.0
    }

    /**
     * Upisuje vrijednost u jedinici prikaza (težina se sprema u kg) i ograničava je na raspon. Težina se
     * zaokružuje samo na 0,05, ne na korak, da se težina upisana izvan koraka ne promijeni sama.
     */
    fun apply(value: Double, values: SetFieldValues, unit: WeightUnit) {
        val range = range(unit)
        val rounded = if (isWeight) {
            (value * WEIGHT_SUBDIVISIONS).roundToLong() / WEIGHT_SUBDIVISIONS
        } else {
            (value / step(unit)).roundToLong() * step(unit)
        }
        val snapped = rounded.coerceIn(range.start, range.endInclusive)
        when (this) {
            WEIGHT -> values.weightKg = WeightConversion.kilograms(snapped, unit)
            EXTRA_WEIGHT -> values.extraWeightKg = WeightConversion.kilograms(snapped, unit)
            REPS -> values.reps = snapped.roundToInt()
            DURATION -> values.durationSeconds = snapped.roundToInt()
            DISTANCE -> values.distanceMeters = snapped
        }
    }

    fun matches(value: Double, values: SetFieldValues, unit: WeightUnit): Boolean {
        val copy = values.copy()
        apply(value, copy, unit)
        return abs(value(copy, unit) - value(values, unit)) < 1e-6 && isFilled(values) == isFilled(copy)
    }

    fun isFilled(values: SetFieldValues): Boolean = when (this) {
        WEIGHT -> values.weightKg != null
        EXTRA_WEIGHT -> values.extraWeightKg != null
        REPS -> values.reps != null
        DURATION -> values.durationSeconds != null
        DISTANCE -> values.distanceMeters != null
    }

    /** Tekst za prikaz, npr. "82,5", "8", "1:30", "400"; "–" kad polje nije upisano. */
    fun text(values: SetFieldValues, unit: WeightUnit, locale: Locale = Locale.getDefault()): String = when (this) {
        WEIGHT -> values.weightKg?.let { WeightFormatter(unit, locale).number(it) } ?: "–"
        EXTRA_WEIGHT -> values.extraWeightKg?.let { WeightFormatter(unit, locale).number(it) } ?: "–"
        REPS -> values.reps?.toString() ?: "–"
        DURATION -> values.durationSeconds?.let { "%d:%02d".format(it / 60, it % 60) } ?: "–"
        DISTANCE -> values.distanceMeters?.let { NumberFormat.getIntegerInstance(locale).format(it) } ?: "–"
    }

    companion object {
        /** Težina se zaokružuje na 1/20 (0,05), kao prikaz. */
        private const val WEIGHT_SUBDIVISIONS = 20.0

        fun fromRaw(raw: String?): SetField? = entries.firstOrNull { it.raw == raw }

        /** Polja koja vrsta unosa traži, redom kako se prikazuju (prvo težina ili trajanje). */
        fun fields(inputType: ExerciseInputType): List<SetField> = when (inputType) {
            ExerciseInputType.WEIGHT_REPS -> listOf(WEIGHT, REPS)
            ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> listOf(EXTRA_WEIGHT, REPS)
            ExerciseInputType.BODYWEIGHT -> listOf(REPS)
            ExerciseInputType.DURATION -> listOf(DURATION)
            ExerciseInputType.DURATION_DISTANCE -> listOf(DURATION, DISTANCE)
        }
    }
}

/** Jedna vrijednost sljedeće serije s gumbima − i + (obavijest treninga, Live Activity na iOS-u). */
data class LiveSetValue(
    val field: SetField,
    val text: String,
    /** "kg", "lbs" ili "m"; prazno za ponavljanja i trajanje. */
    val unitSymbol: String,
    val canDecrease: Boolean,
    val canIncrease: Boolean,
)

/** Prikaz i promjena vrijednosti sljedeće serije bez ekrana treninga (`LiveSetEditor` na iOS-u). */
object LiveSetEditor {
    fun values(set: SetLog, inputType: ExerciseInputType, unit: WeightUnit, locale: Locale = Locale.getDefault()): List<LiveSetValue> {
        val values = snapshot(set)
        return SetField.fields(inputType).map { field ->
            val range = field.range(unit)
            val value = field.value(values, unit)
            LiveSetValue(
                field = field,
                text = field.text(values, unit, locale),
                unitSymbol = when (field) {
                    SetField.WEIGHT, SetField.EXTRA_WEIGHT -> unit.symbol
                    SetField.DISTANCE -> "m"
                    SetField.REPS, SetField.DURATION -> ""
                },
                canDecrease = field.isFilled(values) && value > range.start,
                canIncrease = value < range.endInclusive,
            )
        }
    }

    /**
     * Mijenja polje za [steps] koraka (+1 ili −1). Prazno polje kreće od nule i ne smanjuje se. Vraća false
     * kad se vrijednost nije promijenila (npr. na rubu raspona).
     */
    fun adjust(set: SetLog, field: SetField, steps: Int, unit: WeightUnit, weightStep: Double? = null): Boolean {
        val values = snapshot(set)
        if (steps <= 0 && !field.isFilled(values)) return false
        val step = field.step(unit, weightStep)
        val target = field.moved(field.value(values, unit), steps, step)
        if (field.matches(target, values, unit)) return false
        field.apply(target, values, unit)
        set.weightKg = values.weightKg
        set.reps = values.reps
        set.extraWeightKg = values.extraWeightKg
        set.durationSeconds = values.durationSeconds
        set.distanceMeters = values.distanceMeters
        return true
    }

    private fun snapshot(set: SetLog) =
        SetFieldValues(set.weightKg, set.reps, set.extraWeightKg, set.durationSeconds, set.distanceMeters)
}
