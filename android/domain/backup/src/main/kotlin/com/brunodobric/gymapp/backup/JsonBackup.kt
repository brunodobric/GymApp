package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.CustomExercise
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.MeasurementSource
import com.brunodobric.gymapp.model.UserSettingsChoice
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * Puna sigurnosna kopija svih korisničkih podataka u JSON-u, u istom zapisu kao na iOS-u. Katalog vježbi nije
 * uključen (dolazi s aplikacijom). Treninzi u tijeku i odbačeni treninzi se ne izvoze.
 *
 * Podaci iz zdravstvenih aplikacija na Androidu još ne postoje. Kopija s iPhonea zato može imati treninge iz
 * aplikacije Workouts i težinu ili visinu iz Zdravlja: oni se pri uvozu preskaču, jer ne smiju u korisničku bazu
 * (isto pravilo kao `HealthLocalStore` na iOS-u).
 */
object JsonBackup {
    const val FORMAT = "gymapp-backup"
    const val VERSION = 1

    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    /** [imageData] čita sliku vlastite vježbe iz njezine datoteke (`imageFile`). */
    fun export(
        store: GymStore,
        now: Instant = Instant.now(),
        imageData: (CustomExercise) -> ByteArray? = { null },
    ): String {
        val file = BackupFile(
            format = FORMAT,
            version = VERSION,
            exportedAt = now,
            settings = UserSettingsChoice.preferred(store.settingsRecords)?.let(::SettingsDTO),
            customExercises = store.customExercises.sortedBy { it.id.sortKey }.map { CustomExerciseDTO(it, imageData(it)) },
            templates = store.templates.sortedBy { it.id.sortKey }.map(::TemplateDTO),
            schedules = store.schedules.sortedBy { it.id.sortKey }.map(::ScheduleDTO),
            cycleOverrides = store.cycleOverrides.sortedBy { it.id.sortKey }.map(::CycleOverrideDTO),
            sessions = store.ownFinishedSessions().sortedWith(compareBy({ it.startedAt }, { it.id.sortKey })).map(::SessionDTO),
            measurements = store.bodyMeasurements.sortedWith(compareBy({ it.date }, { it.id.sortKey })).map(::MeasurementDTO),
            dashboardCards = store.dashboardCards.sortedWith(compareBy({ it.orderIndex }, { it.id.sortKey })).map(::DashboardCardDTO),
        )
        return SwiftJson.print(json.encodeToJsonElement(BackupFile.serializer(), file))
    }

    /**
     * Uvozi sigurnosnu kopiju. Zapisi čiji `id` već postoji se preskaču. Postavke se uvijek preuzimaju iz datoteke.
     * [saveImage] sprema sliku vlastite vježbe u datoteku i vraća njezino ime.
     */
    fun import(
        text: String,
        store: GymStore,
        saveImage: (UUID, ByteArray) -> String? = { _, _ -> null },
    ): BackupImportResult {
        val file = try {
            json.decodeFromString(BackupFile.serializer(), text)
        } catch (_: SerializationException) {
            throw BackupException.UnsupportedFormat
        } catch (_: IllegalArgumentException) {
            throw BackupException.UnsupportedFormat
        }
        if (file.format != FORMAT) throw BackupException.UnsupportedFormat
        if (file.version > VERSION) throw BackupException.NewerVersion(file.version)

        val result = BackupImportResult()
        file.settings?.apply(store.settings())

        /** Uvozi zapise čiji `id` još ne postoji; ostale preskače. */
        fun <D> importAll(items: List<D>, known: List<UUID>, itemId: (D) -> UUID, insert: (D) -> Unit) {
            val ids = known.toMutableSet()
            for (item in items) {
                if (ids.add(itemId(item))) {
                    insert(item)
                    result.added += 1
                } else {
                    result.skipped += 1
                }
            }
        }

        importAll(file.customExercises, store.customExercises.map { it.id }, { it.id }) { store.insert(it.make(saveImage)) }
        importAll(file.templates, store.templates.map { it.id }, { it.id }) { it.make(store) }
        importAll(file.schedules, store.schedules.map { it.id }, { it.id }) { it.make(store) }
        importAll(file.cycleOverrides, store.cycleOverrides.map { it.id }, { it.id }) { store.insert(it.make()) }
        val sessions = file.sessions.filter { !it.isImportedFromWorkoutsApp }
        result.skipped += file.sessions.size - sessions.size
        importAll(sessions, store.sessions.map { it.id }, { it.id }) { it.make(store) }
        val measurements = file.measurements.filter { !it.isFromHealth }
        result.skipped += file.measurements.size - measurements.size
        importAll(measurements, store.bodyMeasurements.map { it.id }, { it.id }) { store.insert(it.make()) }
        importAll(file.dashboardCards, store.dashboardCards.map { it.id }, { it.id }) { store.insert(it.make()) }
        store.save()
        return result
    }

    /** Težina i visina iz Zdravlja na iOS-u idu u lokalnu bazu zdravstvenih podataka, ne u korisničku. */
    private val MeasurementDTO.isFromHealth: Boolean
        get() = sourceRaw == MeasurementSource.HEALTH_KIT.raw &&
            (kindRaw == BodyMeasurementKind.WEIGHT.raw || kindRaw == BodyMeasurementKind.HEIGHT.raw)
}

/**
 * JSON kao `JSONEncoder` s `.prettyPrinted` i `.sortedKeys` na iOS-u: ključevi abecedno, uvlaka dva razmaka,
 * `"ključ" : vrijednost`. Cijeli brojevi u `Double` poljima pišu se bez decimala (80, ne 80.0).
 */
internal object SwiftJson {
    fun print(element: JsonElement): String = StringBuilder().also { write(element, it, 0) }.toString()

    private fun write(element: JsonElement, out: StringBuilder, depth: Int) {
        val indent = "  ".repeat(depth + 1)
        val closing = "  ".repeat(depth)
        when (element) {
            is JsonObject -> {
                if (element.isEmpty()) { out.append("{\n\n").append(closing).append('}'); return }
                out.append("{\n")
                element.entries.sortedBy { it.key }.forEachIndexed { index, (key, value) ->
                    if (index > 0) out.append(",\n")
                    out.append(indent).append(JsonPrimitive(key).toString()).append(" : ")
                    write(value, out, depth + 1)
                }
                out.append('\n').append(closing).append('}')
            }
            is JsonArray -> {
                if (element.isEmpty()) { out.append("[\n\n").append(closing).append(']'); return }
                out.append("[\n")
                element.forEachIndexed { index, value ->
                    if (index > 0) out.append(",\n")
                    out.append(indent)
                    write(value, out, depth + 1)
                }
                out.append('\n').append(closing).append(']')
            }
            is JsonNull -> out.append("null")
            is JsonPrimitive -> out.append(primitive(element))
        }
    }

    private fun primitive(value: JsonPrimitive): String {
        if (value.isString) return value.toString().replace("/", "\\/")
        val text = value.content
        if (value.booleanOrNull != null || text.toLongOrNull() != null) return text
        // Decimalni broj bez eksponenta, a cijeli bez ".0", kao Swift (815959971.17, ne 8.1595997117E8).
        val number = text.toBigDecimalOrNull() ?: return text
        return number.stripTrailingZeros().toPlainString()
    }
}
