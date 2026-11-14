package com.brunodobric.gymapp.model

import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * Trajne bilješke vježbi: postavka sprave, hvat, širina stava. Vrijede za vježbu gdje god se radi, za razliku od
 * bilješke uz vježbu u predlošku. Spremaju se u postavkama ([UserSettings.exerciseNotesRaw]) kao JSON
 * `{ključ vježbe: tekst}`, isto kao `ExerciseNotes` na iOS-u.
 */
class ExerciseNotes(raw: String = "") {
    private val notes: MutableMap<String, String> =
        runCatching { Json.decodeFromString(serializer, raw).toMutableMap() }.getOrDefault(mutableMapOf())

    /** Bilješka vježbe ([ExerciseRef.key]), null bez bilješke. */
    fun note(key: String): String? = notes[key]?.takeIf { it.isNotEmpty() }

    /** Postavlja bilješku; prazan tekst je briše. */
    fun setNote(text: String, key: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) notes.remove(key) else notes[key] = trimmed
    }

    /** JSON s ključevima abecedno (kao `JSONEncoder` sa `.sortedKeys`). */
    val raw: String
        get() = if (notes.isEmpty()) "" else Json.encodeToString(serializer, notes.toSortedMap())

    private companion object {
        val serializer = MapSerializer(String.serializer(), String.serializer())
    }
}

/** Trajne bilješke vježbi ([ExerciseNotes]). */
var UserSettings.exerciseNotes: ExerciseNotes
    get() = ExerciseNotes(exerciseNotesRaw)
    set(value) { exerciseNotesRaw = value.raw }
