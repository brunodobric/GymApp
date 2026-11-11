package com.brunodobric.gymapp.sync

import com.brunodobric.gymapp.model.StoredRecord
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Ključ zapisa: vrsta i id, isti kao u bazi (`StoredRecord`). */
typealias RecordKey = Pair<String, String>

/**
 * Jedan zapis u datoteci za sinkronizaciju: sadržaj kao u bazi, kada je zadnji put promijenjen i na kojem uređaju.
 * Obrisan zapis ostaje kao oznaka brisanja (`json` je null), da ga drugi uređaj ne vrati.
 */
@Serializable
data class SyncEntry(
    val type: String,
    val id: String,
    val json: String? = null,
    /** Milisekunde od 1. 1. 1970. (sat uređaja koji je promijenio zapis). */
    val modifiedAt: Long,
    val device: String,
) {
    val key: RecordKey get() = type to id
    val isDeleted: Boolean get() = json == null
}

/**
 * Datoteka za sinkronizaciju (`apolon-sync.json` u pohrani koju korisnik odabere, npr. Google Drive): svi zapisi
 * svih uređaja s vremenom promjene. Format je samo za Android; iPhone koristi iCloud.
 */
@Serializable
data class SyncFile(
    val format: Int = FORMAT,
    val app: String = APP,
    val entries: List<SyncEntry> = emptyList(),
) {
    fun encode(): String = json.encodeToString(serializer(), this)

    companion object {
        const val FORMAT = 1
        const val APP = "Apolon"

        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        /**
         * Čita datoteku. Prazna datoteka (upravo stvorena) je prazna sinkronizacija. Baca [SyncException.NotSyncFile]
         * za datoteku koja nije Apolonova i [SyncException.NewerFormat] za format novije verzije aplikacije.
         */
        fun decode(text: String): SyncFile {
            val trimmed = text.removePrefix("﻿").trim()
            if (trimmed.isEmpty()) return SyncFile()
            val file = try {
                val element = json.parseToJsonElement(trimmed).jsonObject
                // Oznaka aplikacije mora biti u datoteci: druga JSON datoteka nije prazna sinkronizacija.
                if (element["app"]?.jsonPrimitive?.contentOrNull != APP) throw SyncException.NotSyncFile
                json.decodeFromJsonElement(serializer(), element)
            } catch (_: Exception) {
                throw SyncException.NotSyncFile
            }
            if (file.format > FORMAT) throw SyncException.NewerFormat
            return file
        }
    }
}

sealed class SyncException(message: String) : Exception(message) {
    data object NotSyncFile : SyncException("Datoteka nije Apolonova datoteka za sinkronizaciju.")
    data object NewerFormat : SyncException("Datoteku je zapisala novija verzija aplikacije.")
}

/**
 * Lokalni zapis o tome što je uređaj zadnji put vidio i kada se što promijenilo. Spremljen je uz bazu, ali ne ide
 * u sigurnosnu kopiju ni na drugi uređaj.
 */
@Serializable
data class SyncLedger(
    val device: String,
    val entries: List<SyncEntry> = emptyList(),
    /** Je li uređaj već jednom spojio svoje podatke s datotekom. */
    val joined: Boolean = false,
) {
    fun encode(): String = json.encodeToString(serializer(), this)

    companion object {
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        fun decode(text: String): SyncLedger = json.decodeFromString(serializer(), text)
    }
}

/**
 * Spajanje lokalne baze i datoteke za sinkronizaciju, zapis po zapis: vrijedi novija promjena (prema vremenu
 * promjene, a za isto vrijeme prema uređaju, pa je ishod isti na svim uređajima). Brisanje je promjena kao i
 * svaka druga, pa se obrisan zapis ne vraća.
 *
 * Pravila:
 * * Lokalna promjena je svaki zapis čiji se sadržaj razlikuje od onoga u [SyncLedger]-u; dobiva trenutno vrijeme.
 *   Zapis kojeg više nema u bazi postaje oznaka brisanja.
 * * Pri prvom spajanju uređaja datoteka ima prednost za zapise koje oboje imaju (npr. baza vraćena iz stare kopije
 *   ne smije pregaziti novije promjene s drugog uređaja), a zapisi samo s ovog uređaja se dodaju.
 * * Zapisi treninga u tijeku ([excluded]) ne idu u datoteku i ne mijenjaju se iz nje dok trening ne završi.
 * * Kad promjene s drugog uređaja sada ne mogu u bazu ([canApply] je false: otvoren je uređivač ili trening),
 *   ostaju u datoteci i primjenjuju se pri sljedećoj sinkronizaciji.
 */
object SyncMerge {

    data class Result(
        /** Zapisi s drugog uređaja koje treba upisati u bazu. */
        val upserts: List<StoredRecord>,
        /** Zapisi koje je drugi uređaj obrisao. */
        val deletes: List<RecordKey>,
        /** Novi lokalni zapis stanja. */
        val ledger: SyncLedger,
        /** Sadržaj datoteke nakon spajanja. */
        val file: SyncFile,
        /** Treba li zapisati datoteku (spojeno stanje se razlikuje od pročitanog). */
        val fileChanged: Boolean,
        /** Promjene s drugog uređaja koje sada nisu primijenjene. */
        val deferred: Int,
        /** Broj lokalnih promjena poslanih u datoteku. */
        val sent: Int,
    ) {
        val received: Int get() = upserts.size + deletes.size
    }

    fun merge(
        local: List<StoredRecord>,
        ledger: SyncLedger,
        remote: SyncFile,
        now: Long,
        excluded: Set<RecordKey> = emptySet(),
        canApply: Boolean = true,
    ): Result {
        val device = ledger.device
        val remoteByKey = remote.entries.associateBy { it.key }
        val known = refresh(local, ledger, now, excluded)
        val localByKey = local.associateBy { it.type to it.id }

        val merged = LinkedHashMap<RecordKey, SyncEntry>()
        val nextLedger = LinkedHashMap<RecordKey, SyncEntry>()
        val upserts = mutableListOf<StoredRecord>()
        val deletes = mutableListOf<RecordKey>()
        var deferred = 0
        var sent = 0

        val keys = LinkedHashSet<RecordKey>().apply {
            addAll(known.keys)
            addAll(remoteByKey.keys)
        }
        for (key in keys) {
            val mine = known[key]
            val theirs = remoteByKey[key]
            if (key in excluded) {
                // Trening u tijeku: datoteka zadržava što ima, a ovaj uređaj ništa ne šalje ni prima.
                theirs?.let { merged[key] = it }
                mine?.let { nextLedger[key] = it }
                continue
            }
            val firstJoin = !ledger.joined && mine != null && theirs != null
            val winner = when {
                mine == null -> theirs!!
                theirs == null -> mine
                firstJoin -> theirs
                isNewer(mine, theirs) -> mine
                else -> theirs
            }
            merged[key] = winner
            if (winner === mine || winner == mine) {
                nextLedger[key] = winner
                if (theirs == null || theirs != winner) sent++
                continue
            }
            // Vrijedi verzija s drugog uređaja.
            val current = localByKey[key]
            if (current?.json == winner.json) {
                nextLedger[key] = winner
                continue
            }
            if (!canApply) {
                deferred++
                mine?.let { nextLedger[key] = it }
                continue
            }
            if (winner.json == null) {
                if (current != null) deletes += key
            } else {
                upserts += StoredRecord(winner.type, winner.id, winner.json)
            }
            nextLedger[key] = winner
        }

        val file = SyncFile(entries = merged.values.toList())
        val fileChanged = merged != remoteByKey || remote.format != SyncFile.FORMAT
        return Result(
            upserts = upserts,
            deletes = deletes,
            // Prvo spajanje je gotovo tek kad su sve promjene s datoteke primijenjene: do tada datoteka ima prednost.
            ledger = SyncLedger(device, nextLedger.values.toList(), joined = ledger.joined || deferred == 0),
            file = file,
            fileChanged = fileChanged,
            deferred = deferred,
            sent = sent,
        )
    }

    /**
     * Stanje baze kao zapisi s vremenom promjene: neizmijenjeni zadržavaju zapis iz [ledger]-a, a izmijenjeni,
     * novi i obrisani dobivaju [now] i ovaj uređaj.
     */
    internal fun refresh(local: List<StoredRecord>, ledger: SyncLedger, now: Long, excluded: Set<RecordKey>): Map<RecordKey, SyncEntry> {
        val previous = ledger.entries.associateBy { it.key }
        val result = LinkedHashMap<RecordKey, SyncEntry>()
        for (record in local) {
            val key = record.type to record.id
            if (key in excluded) {
                previous[key]?.let { result[key] = it }
                continue
            }
            val old = previous[key]
            result[key] = if (old != null && old.json == record.json) old else SyncEntry(record.type, record.id, record.json, now, ledger.device)
        }
        for ((key, old) in previous) {
            if (key in result) continue
            result[key] = when {
                key in excluded || old.isDeleted -> old
                else -> SyncEntry(old.type, old.id, null, now, ledger.device)
            }
        }
        return result
    }

    /** Je li [a] novija promjena od [b]. Za isto vrijeme odlučuje uređaj, pa sadržaj, da je ishod isti posvuda. */
    internal fun isNewer(a: SyncEntry, b: SyncEntry): Boolean {
        if (a.modifiedAt != b.modifiedAt) return a.modifiedAt > b.modifiedAt
        if (a.device != b.device) return a.device > b.device
        return (a.json ?: "") >= (b.json ?: "")
    }
}
