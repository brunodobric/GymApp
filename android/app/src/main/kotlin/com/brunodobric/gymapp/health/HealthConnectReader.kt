package com.brunodobric.gymapp.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.BodyMeasurementKind
import java.time.Instant
import kotlin.reflect.KClass

/**
 * Čita zapise iz Health Connecta i pretvara ih u vrijednosti bez Android API-ja ([HealthWorkoutRecord],
 * [HealthBodySample]), s kojima radi [HealthImporter]. Vrsta bez dane dozvole se ne čita.
 */
internal class HealthConnectReader(private val client: HealthConnectClient, private val granted: Set<String>) {
    private fun canRead(type: KClass<out Record>) = HealthPermission.getReadPermission(type) in granted

    /** Kardio treninzi u rasponu; za nove (nisu u [skip]) čita i udaljenost, kalorije i prosječni puls. */
    suspend fun cardioWorkouts(from: Instant, to: Instant, skip: Set<String>): List<HealthWorkoutRecord> {
        if (!canRead(ExerciseSessionRecord::class)) return emptyList()
        return readAll(ExerciseSessionRecord::class, from, to).mapNotNull { record ->
            val activity = cardioActivity(record.exerciseType) ?: return@mapNotNull null
            val id = record.metadata.id
            val packageName = record.metadata.dataOrigin.packageName
            if (id in skip) return@mapNotNull null
            val values = if (record.endTime > record.startTime) totals(record) else Totals()
            HealthWorkoutRecord(
                recordId = id,
                activity = activity,
                start = record.startTime,
                end = record.endTime,
                packageName = packageName,
                activeEnergyKilocalories = values.energy,
                distanceMeters = values.distance,
                averageHeartRate = values.heartRate,
            )
        }
    }

    /** Težina (kg) i visina (cm) u rasponu. */
    suspend fun bodySamples(from: Instant, to: Instant): List<HealthBodySample> {
        val weights = if (canRead(WeightRecord::class)) {
            readAll(WeightRecord::class, from, to).map {
                HealthBodySample(it.metadata.id, BodyMeasurementKind.WEIGHT, it.weight.inKilograms, it.time, it.metadata.dataOrigin.packageName)
            }
        } else {
            emptyList()
        }
        val heights = if (canRead(HeightRecord::class)) {
            readAll(HeightRecord::class, from, to).map {
                HealthBodySample(it.metadata.id, BodyMeasurementKind.HEIGHT, it.height.inMeters * 100, it.time, it.metadata.dataOrigin.packageName)
            }
        } else {
            emptyList()
        }
        return weights + heights
    }

    private class Totals(val energy: Double? = null, val distance: Double? = null, val heartRate: Double? = null)

    /** Zbroj iz iste aplikacije koja je zapisala trening, u vremenu treninga. */
    private suspend fun totals(record: ExerciseSessionRecord): Totals {
        val metrics = buildSet {
            if (canRead(ActiveCaloriesBurnedRecord::class)) add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
            if (canRead(DistanceRecord::class)) add(DistanceRecord.DISTANCE_TOTAL)
            if (canRead(HeartRateRecord::class)) add(HeartRateRecord.BPM_AVG)
        }
        if (metrics.isEmpty()) return Totals()
        val result = runCatching {
            client.aggregate(
                AggregateRequest(
                    metrics = metrics,
                    timeRangeFilter = TimeRangeFilter.between(record.startTime, record.endTime),
                    dataOriginFilter = setOf(record.metadata.dataOrigin),
                ),
            )
        }.getOrNull() ?: return Totals()
        return Totals(
            energy = result[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories,
            distance = result[DistanceRecord.DISTANCE_TOTAL]?.inMeters,
            heartRate = result[HeartRateRecord.BPM_AVG]?.toDouble(),
        )
    }

    private suspend fun <T : Record> readAll(type: KClass<T>, from: Instant, to: Instant): List<T> {
        val all = mutableListOf<T>()
        var token: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(type, TimeRangeFilter.between(from, to), pageSize = PAGE, pageToken = token),
            )
            all += response.records
            token = response.pageToken
        } while (token != null && all.size < LIMIT)
        return all
    }

    private companion object {
        const val PAGE = 500
        const val LIMIT = 5_000

        /** Kardio vrste koje se uvoze; snaga i ostalo ne (trening snage vodi se u aplikaciji). */
        fun cardioActivity(type: Int): HealthCardioActivity? = when (type) {
            ExerciseSessionRecord.EXERCISE_TYPE_RUNNING, ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL ->
                HealthCardioActivity.RUNNING
            ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> HealthCardioActivity.WALKING
            ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> HealthCardioActivity.HIKING
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING, ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY ->
                HealthCardioActivity.CYCLING
            ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL, ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER ->
                HealthCardioActivity.SWIMMING
            ExerciseSessionRecord.EXERCISE_TYPE_ROWING, ExerciseSessionRecord.EXERCISE_TYPE_ROWING_MACHINE -> HealthCardioActivity.ROWING
            ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL -> HealthCardioActivity.ELLIPTICAL
            ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING, ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING_MACHINE ->
                HealthCardioActivity.STAIRS
            ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING -> HealthCardioActivity.HIIT
            ExerciseSessionRecord.EXERCISE_TYPE_DANCING -> HealthCardioActivity.DANCE
            ExerciseSessionRecord.EXERCISE_TYPE_SKIING -> HealthCardioActivity.SKIING
            else -> null
        }
    }
}

/** Naziv uvezenog treninga u povijesti, na jeziku sučelja u trenutku uvoza (kao na iOS-u). */
internal class HealthActivityNames(private val context: Context) {
    fun title(activity: HealthCardioActivity): String = context.getString(
        when (activity) {
            HealthCardioActivity.RUNNING -> R.string.cardio_running
            HealthCardioActivity.WALKING -> R.string.cardio_walking
            HealthCardioActivity.HIKING -> R.string.cardio_hiking
            HealthCardioActivity.CYCLING -> R.string.cardio_cycling
            HealthCardioActivity.SWIMMING -> R.string.cardio_swimming
            HealthCardioActivity.ROWING -> R.string.cardio_rowing
            HealthCardioActivity.ELLIPTICAL -> R.string.cardio_elliptical
            HealthCardioActivity.STAIRS -> R.string.cardio_stairs
            HealthCardioActivity.HIIT -> R.string.cardio_hiit
            HealthCardioActivity.DANCE -> R.string.cardio_dance
            HealthCardioActivity.SKIING -> R.string.cardio_skiing
            HealthCardioActivity.OTHER_CARDIO -> R.string.cardio_other
        },
    )
}
