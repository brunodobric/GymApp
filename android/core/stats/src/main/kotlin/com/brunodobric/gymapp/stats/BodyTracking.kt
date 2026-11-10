package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.BodyMeasurement
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.MeasurementSource
import java.time.Instant

class BodyTrackingException : IllegalArgumentException("Neispravna vrijednost mjere")

/**
 * Praćenje tijela: mjere se spremaju u metričkim jedinicama (kg za težinu, cm za ostalo).
 * Uz ručne unose su i težina i visina iz Health Connecta ([GymStore.health]).
 */
class BodyTracking(val store: GymStore) {

    fun add(
        kind: BodyMeasurementKind,
        value: Double,
        date: Instant = Instant.now(),
        customName: String? = null,
        source: MeasurementSource = MeasurementSource.MANUAL,
    ): BodyMeasurement {
        if (!value.isFinite() || value <= 0) throw BodyTrackingException()
        val measurement = BodyMeasurement(kind, value, date, source)
        if (kind == BodyMeasurementKind.CUSTOM) measurement.customName = customName?.trim(' ')
        store.insert(measurement)
        store.save()
        return measurement
    }

    /** Tjelesna težina (kg) iz prečaca. Broj izvan raspona je gotovo sigurno krivo upisan (npr. 8 umjesto 80). */
    fun addShortcutWeight(kilograms: Double, date: Instant = Instant.now()): BodyMeasurement {
        if (!kilograms.isFinite() || kilograms !in SHORTCUT_WEIGHT_RANGE) throw BodyTrackingException()
        return add(BodyMeasurementKind.WEIGHT, kilograms, date)
    }

    /** Povijest jedne mjere, od najstarije, s mjerenjima iz Health Connecta. Za vlastitu mjeru se razlikuje po nazivu. */
    fun measurements(kind: BodyMeasurementKind, customName: String? = null): List<BodyMeasurement> {
        val manual = store.bodyMeasurements.filter { it.kindRaw == kind.raw }
        val health = store.health.measurements.filter { it.kind == kind }.map { it.makeMeasurement() }
        val found = (manual + health).sortedBy { it.date }
        if (kind != BodyMeasurementKind.CUSTOM) return found
        return found.filter { it.customName == customName }
    }

    fun latest(kind: BodyMeasurementKind, customName: String? = null): BodyMeasurement? =
        measurements(kind, customName).lastOrNull()

    /** Razlika između zadnje i prve vrijednosti; null kad ima manje od dva unosa. */
    fun change(kind: BodyMeasurementKind, customName: String? = null): Double? {
        val list = measurements(kind, customName)
        if (list.size < 2) return null
        return list.last().value - list.first().value
    }

    /**
     * Promjena zadnje vrijednosti u zadnjih [days] dana: prema zadnjem mjerenju starom barem [days] dana
     * (gledano od zadnjeg), a bez njega prema prvom mjerenju. Null kad ima manje od dva unosa.
     */
    fun recentChange(kind: BodyMeasurementKind, days: Int = 30): Double? = recentChange(measurements(kind), days)

    /** Nazivi vlastitih mjera koje korisnik prati. */
    fun customNames(): List<String> =
        store.bodyMeasurements.filter { it.kind == BodyMeasurementKind.CUSTOM }
            .mapNotNull { it.customName }.filter { it.isNotEmpty() }.toSortedSet().toList()

    /** Mjerenje iz Health Connecta briše se iz lokalne baze (u Health Connectu ostaje). */
    fun delete(measurement: BodyMeasurement) {
        if (store.health.measurements.any { it.id == measurement.id }) {
            store.health.deleteMeasurement(measurement.id)
            store.healthChanged()
            return
        }
        store.delete(measurement)
        store.save()
    }

    companion object {
        /** Tjelesna težina (kg) koju se prihvaća iz prečaca. */
        val SHORTCUT_WEIGHT_RANGE: ClosedFloatingPointRange<Double> = 20.0..400.0

        /** [measurements] od najstarijeg prema najnovijem. */
        internal fun recentChange(measurements: List<BodyMeasurement>, days: Int): Double? {
            if (measurements.size < 2) return null
            val last = measurements.last()
            val limit = last.date.minusSeconds(days.toLong() * 86_400)
            val reference = measurements.lastOrNull { it.date <= limit } ?: measurements[0]
            return last.value - reference.value
        }
    }
}
