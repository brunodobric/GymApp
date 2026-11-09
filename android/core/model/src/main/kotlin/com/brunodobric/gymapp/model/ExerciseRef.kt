package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.catalog.uppercaseString
import java.util.UUID

/**
 * Ugrađena vrijednost (ne zaseban model): upućuje na vježbu iz kataloga ili na vlastitu vježbu.
 * Sprema i naziv za prikaz, pa povijest ostaje čitljiva i ako vježba nestane.
 */
data class ExerciseRef(
    val catalogId: String? = null,
    val customExerciseId: UUID? = null,
    val name: String,
) {
    /** Stabilan ključ za upite: "c:<id kataloga>" ili "u:<UUID vlastite vježbe>" (UUID velikim slovima). */
    val key: String
        get() = when {
            catalogId != null -> "c:$catalogId"
            customExerciseId != null -> "u:${customExerciseId.uppercaseString}"
            else -> ""
        }

    /** Vježba na koju referenca upućuje. Nil kad referenca nema ni katalog ni vlastitu vježbu. */
    val source: ExerciseSummary.Source?
        get() = when {
            catalogId != null -> ExerciseSummary.Source.Catalog(catalogId)
            customExerciseId != null -> ExerciseSummary.Source.Custom(customExerciseId)
            else -> null
        }

    companion object {
        fun catalog(id: String, name: String) = ExerciseRef(catalogId = id, name = name)

        fun custom(id: UUID, name: String) = ExerciseRef(customExerciseId = id, name = name)

        /** Obnavlja referencu iz ključa (`c:<id>` ili `u:<UUID>`). Nil za neispravan ključ. */
        fun fromKey(key: String, name: String): ExerciseRef? = when {
            key.startsWith("c:") && key.length > 2 -> catalog(key.drop(2), name)
            key.startsWith("u:") -> runCatching { UUID.fromString(key.drop(2)) }.getOrNull()?.let { custom(it, name) }
            else -> null
        }
    }
}

/** Referenca koju spremaju predlošci i treninzi. */
val ExerciseSummary.ref: ExerciseRef
    get() = when (val source = source) {
        is ExerciseSummary.Source.Catalog -> ExerciseRef.catalog(source.id, name)
        is ExerciseSummary.Source.Custom -> ExerciseRef.custom(source.id, name)
    }
