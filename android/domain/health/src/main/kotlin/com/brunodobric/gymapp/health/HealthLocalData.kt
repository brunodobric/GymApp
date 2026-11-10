package com.brunodobric.gymapp.health

import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.HealthLocalSource
import com.brunodobric.gymapp.model.HealthMeasurement
import com.brunodobric.gymapp.model.HealthWorkout
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Sadržaj lokalne baze podataka iz Health Connecta. [deletedRecordIds] su zapisi koje je korisnik obrisao. */
data class HealthLocalData(
    val workouts: List<HealthWorkout> = emptyList(),
    val measurements: List<HealthMeasurement> = emptyList(),
    val deletedRecordIds: Set<String> = emptySet(),
) {
    fun encode(): String = json.encodeToString(FileDto.serializer(), toDto())

    private fun toDto() = FileDto(
        workouts = workouts.map {
            WorkoutDto(
                it.id.toString(), it.recordId, it.name, it.startedAt.toEpochMilli(), it.endedAt.toEpochMilli(),
                it.activeEnergyKilocalories, it.distanceMeters, it.averageHeartRate,
            )
        },
        measurements = measurements.map { MeasurementDto(it.id.toString(), it.recordId, it.kind.raw, it.value, it.date.toEpochMilli()) },
        deleted = deletedRecordIds.sorted(),
    )

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Neispravan zapis se preskače; neispravna datoteka je prazna baza (sljedeće čitanje je puni iznova). */
        fun decode(text: String): HealthLocalData {
            val dto = runCatching { json.decodeFromString(FileDto.serializer(), text) }.getOrNull() ?: return HealthLocalData()
            return HealthLocalData(
                workouts = dto.workouts.mapNotNull { w ->
                    runCatching {
                        HealthWorkout(
                            UUID.fromString(w.id), w.recordId, w.name, Instant.ofEpochMilli(w.start), Instant.ofEpochMilli(w.end),
                            w.energy, w.distance, w.heartRate,
                        )
                    }.getOrNull()
                },
                measurements = dto.measurements.mapNotNull { m ->
                    val kind = BodyMeasurementKind.entries.firstOrNull { it.raw == m.kind } ?: return@mapNotNull null
                    runCatching { HealthMeasurement(UUID.fromString(m.id), m.recordId, kind, m.value, Instant.ofEpochMilli(m.date)) }.getOrNull()
                },
                deletedRecordIds = dto.deleted.toSet(),
            )
        }
    }
}

@Serializable
private data class FileDto(
    val workouts: List<WorkoutDto> = emptyList(),
    val measurements: List<MeasurementDto> = emptyList(),
    val deleted: List<String> = emptyList(),
)

@Serializable
private data class WorkoutDto(
    val id: String,
    val recordId: String,
    val name: String,
    val start: Long,
    val end: Long,
    val energy: Double? = null,
    val distance: Double? = null,
    val heartRate: Double? = null,
)

@Serializable
private data class MeasurementDto(val id: String, val recordId: String, val kind: String, val value: Double, val date: Long)

/**
 * Lokalna baza podataka iz Health Connecta u jednoj datoteci u mapi aplikacije (`HealthLocal` konfiguracija na
 * iOS-u). Datoteka ne ide u sigurnosnu kopiju ni sinkronizaciju. Bez datoteke ([file] null) radi samo u memoriji.
 * Nije za više niti: koristi se s glavne niti.
 */
class HealthLocalFile(private val file: File?) : HealthLocalSource {
    var data: HealthLocalData = file?.takeIf { it.exists() }?.let { runCatching { HealthLocalData.decode(it.readText()) }.getOrNull() }
        ?: HealthLocalData()
        private set

    override val workouts: List<HealthWorkout> get() = data.workouts
    override val measurements: List<HealthMeasurement> get() = data.measurements

    /** Zamjenjuje sadržaj i sprema ga. */
    fun replace(newData: HealthLocalData) {
        data = newData
        save()
    }

    override fun deleteWorkout(id: UUID) {
        val removed = data.workouts.filter { it.id == id }
        if (removed.isEmpty()) return
        replace(data.copy(workouts = data.workouts - removed.toSet(), deletedRecordIds = data.deletedRecordIds + removed.map { it.recordId }))
    }

    override fun deleteMeasurement(id: UUID) {
        val removed = data.measurements.filter { it.id == id }
        if (removed.isEmpty()) return
        replace(
            data.copy(measurements = data.measurements - removed.toSet(), deletedRecordIds = data.deletedRecordIds + removed.map { it.recordId }),
        )
    }

    /** Brisanje svih podataka u aplikaciji: lokalna baza je prazna, a Health Connect ostaje kakav je. */
    fun clear() = replace(HealthLocalData())

    private fun save() {
        val target = file ?: return
        target.parentFile?.mkdirs()
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.writeText(data.encode())
        temporary.renameTo(target)
    }
}
