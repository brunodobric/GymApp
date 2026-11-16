package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.InstantSerializer
import com.brunodobric.gymapp.model.UUIDSerializer
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.util.UUID
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Događaj koji se tijekom treninga razmjenjuje između mobitela i sata preko Wearable Data Layera (`WorkoutEvent` na
 * iOS-u, specifikacija, odjeljak 6). Svaki događaj ima UUID i vrijeme nastanka, pa primatelj prepoznaje duplikate
 * (isti događaj stigne porukom i kao podatak) i rješava sukob zadnjom promjenom.
 */
@Serializable
data class WorkoutEvent(
    @Serializable(UUIDSerializer::class) val id: UUID = UUID.randomUUID(),
    @Serializable(UUIDSerializer::class) val sessionId: UUID? = null,
    @Serializable(InstantSerializer::class) val createdAt: Instant = Instant.now(),
    @Serializable(DeviceRoleSerializer::class) val origin: DeviceRole,
    val kind: Kind,
) {
    @Serializable
    sealed class Kind {
        /** Cijelo stanje treninga s uređaja koji ga vodi. */
        @Serializable
        @SerialName("snapshot")
        data class Snapshot(val snapshot: SessionSnapshot) : Kind()

        /** Izmjene s uređaja koji trening zrcali, za uređaj koji ga vodi. */
        @Serializable
        @SerialName("commands")
        data class Commands(val commands: List<WorkoutCommand>) : Kind()
    }

    fun encode(): ByteArray = WearCoding.encode(serializer(), this)

    companion object {
        /** null za neispravan ili nepoznat sadržaj (npr. nakon nadogradnje samo jednog uređaja). */
        fun decode(bytes: ByteArray): WorkoutEvent? = WearCoding.decode(serializer(), bytes)
    }
}

/** Pamti već obrađene događaje i propušta svaki samo jednom (`WorkoutEventDeduplicator` na iOS-u). */
class WorkoutEventDeduplicator(private val capacity: Int = 500) {
    private val seen = LinkedHashSet<UUID>()

    /** true ako je događaj nov i treba ga obraditi. */
    @Synchronized
    fun accept(event: WorkoutEvent): Boolean {
        if (!seen.add(event.id)) return false
        if (seen.size > capacity) seen.remove(seen.first())
        return true
    }
}

/**
 * Stanje koje se drži kao podatak u Data Layeru (`ApplicationContextPayload` na iOS-u): mobitel šalje kontekst za sat
 * i, dok mobitel vodi trening, njegovu snimku. Sat šalje snimku treninga koji vodi. Dio koji nedostaje znači "nema"
 * (npr. nema treninga).
 */
object WearPaths {
    /** Kontekst za sat ([WatchContextPayload]), podatak s mobitela. */
    const val CONTEXT = "/apolon/context"

    /** Snimka treninga koji vodi mobitel, podatak s mobitela. */
    const val PHONE_SESSION = "/apolon/session/phone"

    /** Snimka treninga koji vodi sat, podatak sa sata. */
    const val WATCH_SESSION = "/apolon/session/watch"

    /**
     * Događaji ([WorkoutEvent]) u oba smjera: kao poruka na ovom putu kad je drugi uređaj dostupan, a zajamčeni kao
     * podatak na `EVENT/<id>` (Data Layer ga dostavi kad se uređaji spoje, a primatelj ga obriše nakon obrade).
     */
    const val EVENT = "/apolon/event"

    /** Poruka s mobitela: trening je pokrenut na mobitelu, sat neka mjeri puls i kalorije. */
    const val HEALTH_REQUEST = "/apolon/health/request"

    /** Put zajamčenog događaja. */
    fun eventItem(id: UUID): String = "$EVENT/$id"

    /** Mogućnost kojom se aplikacije na satu i mobitelu pronalaze (`wear.xml`). */
    const val PHONE_CAPABILITY = "apolon_phone"
    const val WATCH_CAPABILITY = "apolon_watch"
}

/** Pakiranje za Data Layer: JSON sažet GZIP-om, jer podatak ima ograničenje veličine (100 KB). */
object WearCoding {
    val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
        explicitNulls = false
        classDiscriminator = "type"
    }

    fun <T> encode(serializer: kotlinx.serialization.KSerializer<T>, value: T): ByteArray {
        val raw = json.encodeToString(serializer, value).toByteArray(Charsets.UTF_8)
        val output = ByteArrayOutputStream()
        GZIPOutputStream(output).use { it.write(raw) }
        return output.toByteArray()
    }

    fun <T> decode(serializer: kotlinx.serialization.KSerializer<T>, bytes: ByteArray): T? = runCatching {
        val raw = GZIPInputStream(ByteArrayInputStream(bytes)).use { it.readBytes() }
        json.decodeFromString(serializer, raw.toString(Charsets.UTF_8))
    }.getOrNull()

    fun encodeContext(context: WatchContextPayload): ByteArray = encode(WatchContextPayload.serializer(), context)

    fun decodeContext(bytes: ByteArray): WatchContextPayload? = decode(WatchContextPayload.serializer(), bytes)

    fun encodeSnapshot(snapshot: SessionSnapshot): ByteArray = encode(SessionSnapshot.serializer(), snapshot)

    fun decodeSnapshot(bytes: ByteArray): SessionSnapshot? = decode(SessionSnapshot.serializer(), bytes)
}
