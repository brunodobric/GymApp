package com.brunodobric.gymapp.health

import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.HealthMeasurement
import com.brunodobric.gymapp.model.HealthWorkout
import java.time.Instant
import java.util.UUID

/** Kardio vrste iz Health Connecta koje se uvoze u povijest (`HealthActivity.isCardio` na iOS-u). */
enum class HealthCardioActivity {
    RUNNING, WALKING, HIKING, CYCLING, SWIMMING, ROWING, ELLIPTICAL, STAIRS, HIIT, DANCE, SKIING, OTHER_CARDIO,
}

/** Trening pročitan iz Health Connecta. [activity] je null za vrste koje nisu kardio (snaga se vodi u aplikaciji). */
data class HealthWorkoutRecord(
    val recordId: String,
    val activity: HealthCardioActivity?,
    val start: Instant,
    val end: Instant,
    /** Aplikacija koja je zapisala trening. */
    val packageName: String,
    val activeEnergyKilocalories: Double? = null,
    val distanceMeters: Double? = null,
    val averageHeartRate: Double? = null,
)

/** Težina (kg) ili visina (cm) pročitana iz Health Connecta. */
data class HealthBodySample(
    val recordId: String,
    val kind: BodyMeasurementKind,
    val value: Double,
    val date: Instant,
    val packageName: String,
)

/**
 * Upisuje podatke iz Health Connecta u lokalnu bazu bez duplikata (`HealthImporter` na iOS-u). Duplikat se
 * prepoznaje po id-ju zapisa u Health Connectu. Zapisi ove aplikacije se ne uvoze (već su u povijesti), a
 * zapis koji je korisnik obrisao iz lokalne baze ne vraća se sljedećim čitanjem.
 */
object HealthImporter {
    /** Id za prikaz: stalan za isti zapis u Health Connectu. */
    fun localId(recordId: String): UUID = UUID.nameUUIDFromBytes("health-connect:$recordId".toByteArray())

    /** Vraća novu lokalnu bazu i broj novih treninga. */
    fun importWorkouts(
        local: HealthLocalData,
        records: List<HealthWorkoutRecord>,
        ownPackage: String,
        name: (HealthCardioActivity) -> String,
    ): Pair<HealthLocalData, Int> {
        val known = local.workouts.map { it.recordId }.toMutableSet()
        val added = mutableListOf<HealthWorkout>()
        for (record in records.sortedBy { it.start }) {
            val activity = record.activity ?: continue
            if (record.packageName == ownPackage || record.end <= record.start) continue
            if (record.recordId in known || record.recordId in local.deletedRecordIds) continue
            added += HealthWorkout(
                id = localId(record.recordId),
                recordId = record.recordId,
                name = name(activity),
                startedAt = record.start,
                endedAt = record.end,
                activeEnergyKilocalories = record.activeEnergyKilocalories?.takeIf { it > 0 },
                distanceMeters = record.distanceMeters?.takeIf { it > 0 },
                averageHeartRate = record.averageHeartRate?.takeIf { it > 0 },
            )
            known += record.recordId
        }
        return local.copy(workouts = local.workouts + added) to added.size
    }

    /** Vraća novu lokalnu bazu i broj novih mjerenja. Uvoze se samo težina i visina. */
    fun importBodySamples(local: HealthLocalData, samples: List<HealthBodySample>, ownPackage: String): Pair<HealthLocalData, Int> {
        val known = local.measurements.map { it.recordId }.toMutableSet()
        val added = mutableListOf<HealthMeasurement>()
        for (sample in samples.sortedBy { it.date }) {
            if (sample.kind != BodyMeasurementKind.WEIGHT && sample.kind != BodyMeasurementKind.HEIGHT) continue
            if (sample.packageName == ownPackage || !(sample.value > 0) || !sample.value.isFinite()) continue
            if (sample.recordId in known || sample.recordId in local.deletedRecordIds) continue
            added += HealthMeasurement(localId(sample.recordId), sample.recordId, sample.kind, sample.value, sample.date)
            known += sample.recordId
        }
        return local.copy(measurements = local.measurements + added) to added.size
    }

    /** Zapisi koji su već u lokalnoj bazi ili obrisani iz nje: za njih ne treba čitati kalorije, udaljenost i puls. */
    fun knownRecordIds(local: HealthLocalData): Set<String> =
        local.workouts.map { it.recordId }.toSet() + local.deletedRecordIds
}
