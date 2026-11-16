package com.brunodobric.gymapp.watch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.concurrent.futures.await
import androidx.core.content.ContextCompat
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import com.brunodobric.gymapp.wear.HealthResult
import com.brunodobric.gymapp.wear.WatchHealth
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Mjerenje treninga snage preko Health Services (`WorkoutSessionManager` na iOS-u): puls i kalorije uživo, a na kraju
 * prosječni puls i ukupne kalorije za mobitel, koji trening upisuje u Health Connect. Dok mjerenje traje, [WorkoutService]
 * drži aplikaciju u prvom planu. Bez dozvole za puls trening ide dalje bez mjerenja.
 */
class HealthTracker(private val context: Context, private val scope: CoroutineScope) : WatchHealth {
    private val client = HealthServices.getClient(context).exerciseClient

    private val mutableHeartRate = MutableStateFlow<Double?>(null)
    private val mutableEnergy = MutableStateFlow<Double?>(null)
    val heartRate: StateFlow<Double?> = mutableHeartRate.asStateFlow()
    val activeEnergyKilocalories: StateFlow<Double?> = mutableEnergy.asStateFlow()

    /** Prosjek pulsa za cijeli trening (Health Services) i, ako ga nema, prosjek primljenih uzoraka. */
    private var averageHeartRate: Double? = null
    private var sampleSum = 0.0
    private var sampleCount = 0

    /** Mjerenje se nije moglo pokrenuti jer aplikacija nije na zaslonu (npr. zahtjev s mobitela u pozadini). */
    var onBackgroundStartBlocked: () -> Unit = {}

    override var isRunning: Boolean = false
        private set

    private val callback = object : ExerciseUpdateCallback {
        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            val metrics = update.latestMetrics
            metrics.getData(DataType.HEART_RATE_BPM).forEach { point ->
                if (point.value > 0) {
                    mutableHeartRate.value = point.value
                    sampleSum += point.value
                    sampleCount++
                }
            }
            metrics.getData(DataType.HEART_RATE_BPM_STATS)?.average?.takeIf { it > 0 }?.let { averageHeartRate = it }
            metrics.getData(DataType.CALORIES_TOTAL)?.total?.let { mutableEnergy.value = it }
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) {}

        override fun onRegistered() {}

        override fun onRegistrationFailed(throwable: Throwable) {}

        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {}
    }

    /** Dozvole koje mjerenje traži: puls (BODY_SENSORS do Androida 15, na 16+ zasebna) i tjelesna aktivnost. */
    val permissions: Array<String>
        get() = buildList {
            add(if (Build.VERSION.SDK_INT >= 36) HEART_RATE_PERMISSION else Manifest.permission.BODY_SENSORS)
            add(Manifest.permission.ACTIVITY_RECOGNITION)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }.toTypedArray()

    private val canMeasureHeartRate: Boolean
        get() {
            val permission = if (Build.VERSION.SDK_INT >= 36) HEART_RATE_PERMISSION else Manifest.permission.BODY_SENSORS
            return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        }

    override suspend fun start(sessionId: UUID, at: Instant): Boolean {
        if (isRunning || !canMeasureHeartRate) return false
        // Usluga u prvom planu prije mjerenja: iz pozadine je sustav ne dopušta, pa se korisnika obavijesti.
        if (!WorkoutService.start(context)) {
            onBackgroundStartBlocked()
            return false
        }
        return try {
            val capabilities = client.getCapabilitiesAsync().await()
            if (ExerciseType.STRENGTH_TRAINING !in capabilities.supportedExerciseTypes) throw IllegalStateException()
            val supported = capabilities.getExerciseTypeCapabilities(ExerciseType.STRENGTH_TRAINING).supportedDataTypes
            val wanted = setOf<DataType<*, *>>(DataType.HEART_RATE_BPM, DataType.HEART_RATE_BPM_STATS, DataType.CALORIES_TOTAL)
            val config = ExerciseConfig.builder(ExerciseType.STRENGTH_TRAINING)
                .setDataTypes(wanted.filter { it in supported }.toSet())
                .setIsAutoPauseAndResumeEnabled(false)
                .setIsGpsEnabled(false)
                .build()
            reset()
            client.setUpdateCallback(callback)
            client.startExerciseAsync(config).await()
            isRunning = true
            true
        } catch (_: Exception) {
            WorkoutService.stop(context)
            false
        }
    }

    override suspend fun end(at: Instant): HealthResult {
        if (!isRunning) return HealthResult()
        runCatching { client.endExerciseAsync().await() }
        val result = HealthResult(
            activeEnergyKilocalories = mutableEnergy.value?.takeIf { it > 0 },
            averageHeartRate = averageHeartRate ?: sampleCount.takeIf { it > 0 }?.let { sampleSum / it },
        )
        finish()
        return result
    }

    override fun discard() {
        if (!isRunning) return
        scope.launch { runCatching { client.endExerciseAsync().await() } }
        finish()
    }

    override fun recover() {
        if (isRunning) return
        scope.launch {
            val info = runCatching { client.getCurrentExerciseInfoAsync().await() }.getOrNull() ?: return@launch
            if (info.exerciseTrackedStatus != OWNED_EXERCISE_IN_PROGRESS) return@launch
            client.setUpdateCallback(callback)
            isRunning = true
            WorkoutService.start(context)
        }
    }

    private fun finish() {
        runCatching { client.clearUpdateCallbackAsync(callback) }
        isRunning = false
        WorkoutService.stop(context)
        reset()
    }

    private fun reset() {
        mutableHeartRate.value = null
        mutableEnergy.value = null
        averageHeartRate = null
        sampleSum = 0.0
        sampleCount = 0
    }

    private companion object {
        const val HEART_RATE_PERMISSION = "android.permission.health.READ_HEART_RATE"

        /** `ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS`: konstanta je u biblioteci označena kao interna. */
        const val OWNED_EXERCISE_IN_PROGRESS = 2
    }
}
