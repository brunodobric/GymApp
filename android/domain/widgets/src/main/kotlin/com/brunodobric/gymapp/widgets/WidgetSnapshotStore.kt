package com.brunodobric.gymapp.widgets

import kotlinx.serialization.json.Json
import java.io.File

/**
 * Snimka za widgete u datoteci aplikacije (`WidgetSnapshotStore` na iOS-u, ondje u App Groupu).
 * Aplikacija piše nakon spremanja baze, a widget čita, pa ne mora učitavati cijelu bazu.
 */
class WidgetSnapshotStore(private val directory: File?) {
    private val file: File? get() = directory?.resolve(FILE_NAME)

    fun load(): WidgetSnapshot? {
        val file = file?.takeIf { it.exists() } ?: return null
        return runCatching { json.decodeFromString(WidgetSnapshot.serializer(), file.readText()) }.getOrNull()
    }

    /**
     * Sprema snimku. Vraća true kad se sadržaj promijenio (tada treba osvježiti widgete). Vrijeme izrade se ne
     * uspoređuje, inače bi se widgeti osvježavali pri svakom spremanju baze.
     */
    fun save(snapshot: WidgetSnapshot): Boolean {
        val directory = directory ?: return false
        val file = file ?: return false
        val old = load()
        if (old != null && old.copy(generatedAt = snapshot.generatedAt) == snapshot) return false
        directory.mkdirs()
        val temporary = File(directory, "$FILE_NAME.tmp")
        temporary.writeText(json.encodeToString(WidgetSnapshot.serializer(), snapshot))
        if (!temporary.renameTo(file)) {
            file.delete()
            temporary.renameTo(file)
        }
        return true
    }

    companion object {
        internal const val FILE_NAME = "widget-snapshot.json"
        private val json = Json { ignoreUnknownKeys = true }
    }
}
