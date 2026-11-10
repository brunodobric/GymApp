package com.brunodobric.gymapp.health

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ExerciseSegment
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Mass
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Upisuje završene treninge i ručno unesenu težinu u Health Connect (`HealthService` na iOS-u, smjer prema Zdravlju).
 * Nakon spremanja baze (s odgodom od dvije sekunde) uspoređuje bazu sa zapisom već upisanog ([HealthLedger]) i šalje
 * samo razliku. Zapisi imaju `clientRecordId` = id treninga ili mjerenja, pa ponovni upis zamjenjuje stari zapis.
 * Zapis o upisanom je datoteka u mapi aplikacije koja ne ide u sigurnosnu kopiju (data_extraction_rules.xml).
 */
class HealthConnectExporter(context: Context, private val services: AppServices) {
    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val ledgerFile = File(File(appContext.filesDir, "health"), "exported.txt")
    private val pending = Runnable { sync() }
    private var running: Job? = null
    private var again = false

    fun start() {
        services.store.addListener { schedule() }
        schedule()
    }

    private fun schedule() {
        handler.removeCallbacks(pending)
        handler.postDelayed(pending, DELAY_MILLIS)
    }

    /** Usklađuje odmah (npr. nakon davanja dozvola). Bez uključene postavke ili dozvola ne radi ništa. */
    fun sync() {
        if (running?.isActive == true) {
            again = true
            return
        }
        if (!services.store.settings().wantsHealthKit || !HealthConnect.isAvailable(appContext)) return
        running = scope.launch {
            runCatching { export() }
            if (again) {
                again = false
                schedule()
            }
        }
    }

    private suspend fun export() {
        val client = HealthConnectClient.getOrCreate(appContext)
        if (!client.permissionController.getGrantedPermissions().containsAll(HealthConnect.PERMISSIONS)) return
        val ledger = withContext(Dispatchers.IO) { readLedger() }
        // Baza se čita na glavnoj niti, a Health Connect i datoteka u pozadini.
        val store = services.store
        val info = ExerciseInfoBuilder.provider(services.catalog, store.customExercises)
        val plan = HealthExportPlanner.plan(
            store.sessions.toList(),
            store.bodyMeasurements.toList(),
            ledger,
            isCardio = ExerciseInfoBuilder.isCardio(info),
        )
        if (plan.isEmpty) return
        withContext(Dispatchers.IO) {
            if (plan.deletedWorkouts.isNotEmpty()) {
                client.deleteRecords(ExerciseSessionRecord::class, emptyList(), plan.deletedWorkouts.map { it.toString() })
            }
            if (plan.deletedWeights.isNotEmpty()) {
                client.deleteRecords(WeightRecord::class, emptyList(), plan.deletedWeights.map { it.toString() })
            }
            // Novija verzija zamjenjuje stariji zapis s istim clientRecordId.
            val version = System.currentTimeMillis()
            val records: List<Record> = plan.workouts.map { exerciseRecord(it, version) } + plan.weights.map { weightRecord(it, version) }
            records.chunked(BATCH).forEach { client.insertRecords(it) }
            writeLedger(plan.ledger)
        }
    }

    private fun readLedger(): HealthLedger =
        runCatching { HealthLedger.decode(ledgerFile.readText()) }.getOrDefault(HealthLedger())

    private fun writeLedger(ledger: HealthLedger) {
        ledgerFile.parentFile?.mkdirs()
        val temporary = File(ledgerFile.parentFile, "${ledgerFile.name}.tmp")
        temporary.writeText(ledger.encode())
        temporary.renameTo(ledgerFile)
    }

    private companion object {
        const val DELAY_MILLIS = 2_000L
        const val BATCH = 100

        fun offset(instant: Instant): ZoneOffset = ZoneId.systemDefault().rules.getOffset(instant)

        /**
         * Jedan trening s dijelovima. Trening samo snage je `STRENGTH_TRAINING` bez dijelova; trening s kardijem
         * je `OTHER_WORKOUT` (prima sve vrste dijelova) s dijelovima snage i kardija. Ako Health Connect dijelove
         * ne prihvati, trening ide bez njih.
         */
        fun exerciseRecord(export: HealthWorkoutExport, version: Long): ExerciseSessionRecord {
            val metadata = Metadata.activelyRecorded(
                device = Device(type = Device.TYPE_PHONE),
                clientRecordId = export.sessionId.toString(),
                clientRecordVersion = version,
            )
            val mixed = export.segments.size > 1
            val type = if (mixed || export.activity.isCardio) {
                ExerciseSessionRecord.EXERCISE_TYPE_OTHER_WORKOUT
            } else {
                ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING
            }
            fun record(segments: List<ExerciseSegment>) = ExerciseSessionRecord(
                startTime = export.start,
                startZoneOffset = offset(export.start),
                endTime = export.end,
                endZoneOffset = offset(export.end),
                metadata = metadata,
                exerciseType = type,
                title = export.name.ifBlank { null },
                segments = segments,
            )
            if (!mixed) return record(emptyList())
            return runCatching {
                record(
                    export.segments.map {
                        ExerciseSegment(
                            startTime = it.start,
                            endTime = it.end,
                            segmentType = if (it.activity.isCardio) {
                                ExerciseSegment.EXERCISE_SEGMENT_TYPE_OTHER_WORKOUT
                            } else {
                                ExerciseSegment.EXERCISE_SEGMENT_TYPE_WEIGHTLIFTING
                            },
                        )
                    },
                )
            }.getOrElse { record(emptyList()) }
        }

        fun weightRecord(export: HealthWeightExport, version: Long) = WeightRecord(
            time = export.time,
            zoneOffset = offset(export.time),
            weight = Mass.kilograms(export.kilograms),
            metadata = Metadata.manualEntry(clientRecordId = export.id.toString(), clientRecordVersion = version),
        )
    }
}
