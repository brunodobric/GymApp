package com.brunodobric.gymapp.catalog

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Jedna službena vježba iz kataloga (samo za čitanje).
 *
 * Javni dio (`Resources/Catalog/catalog.json`) nosi naše podatke o vježbi. Upute, česte greške,
 * klipovi i posteri su MoveKit sadržaj: nisu u repozitoriju nego u privatnom dodatku
 * (docs/movekit.md), pa ih build bez paketa nema.
 */
@Serializable
data class CatalogExercise(
    val id: String,
    val name: Map<String, String>,
    val instructions: Map<String, List<String>> = emptyMap(),
    val commonMistakes: Map<String, List<String>> = emptyMap(),
    val category: ExerciseCategory,
    /** Vrsta vježbe (zagrijavanje, snaga, istezanje, kardio), računa je CatalogBuilder. Stariji katalog je nema. */
    @SerialName("kind") private val storedKind: ExerciseKind? = null,
    val primaryMuscles: List<Muscle>,
    val secondaryMuscles: List<Muscle>,
    val equipment: Equipment,
    val level: Level,
    val mechanic: Mechanic? = null,
    val movement: MovementType? = null,
    val inputType: ExerciseInputType,
    /** Regije body heatmapa (za statistiku). */
    val primaryRegions: List<String>,
    val secondaryRegions: List<String>,
    /** Klip u petlji i poster, putanje unutar mape MoveKit dodatka, npr. "Media/barbell-squat.mp4". */
    val video: String? = null,
    val poster: String? = null,
) {
    val kind: ExerciseKind get() = storedKind ?: ExerciseKind.fallback(category)

    /** Naziv na traženom jeziku ("hr", "en"). Ako prijevoda nema, vraća engleski. */
    fun displayName(language: String): String = name[language] ?: name["en"] ?: id

    /** Upute na traženom jeziku, inače engleske. Prazno kad MoveKit tekstova nema u buildu. */
    fun displayInstructions(language: String): List<String> = instructions[language] ?: instructions["en"] ?: emptyList()

    fun displayCommonMistakes(language: String): List<String> =
        commonMistakes[language] ?: commonMistakes["en"] ?: emptyList()
}

@Serializable
data class CatalogSource(val name: String, val url: String, val license: String)

/** Privatni MoveKit tekstovi jedne vježbe (`MoveKit/texts.json`): upute i česte greške po jeziku. */
@Serializable
data class CatalogTexts(
    val instructions: Map<String, List<String>> = emptyMap(),
    val commonMistakes: Map<String, List<String>> = emptyMap(),
) {
    companion object {
        /** Čita `texts.json`: rječnik id vježbe -> tekstovi. */
        fun decode(json: String): Map<String, CatalogTexts> = CatalogJson.decodeFromString(json)
    }
}

/** JSON postavke kataloga: nepoznata polja se preskaču, pa noviji katalog ne ruši stariju aplikaciju. */
val CatalogJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
}

/**
 * Službeni katalog vježbi. Učitava se iz `catalog.json` koji generira `Tools/CatalogBuilder`.
 * Nije u bazi podataka: nepromjenjiv je i ne sinkronizira se.
 */
class ExerciseCatalog(
    val version: Int,
    val source: CatalogSource,
    val exercises: List<CatalogExercise>,
) {
    private val index: Map<String, Int> = buildMap {
        exercises.forEachIndexed { position, exercise -> putIfAbsent(exercise.id, position) }
    }

    /** Vježba po id-ju. */
    fun exercise(id: String): CatalogExercise? = index[id]?.let(exercises::get)

    /** Spaja privatne MoveKit tekstove (upute i česte greške) s javnim katalogom. */
    fun merging(texts: Map<String, CatalogTexts>): ExerciseCatalog = ExerciseCatalog(
        version,
        source,
        exercises.map { exercise ->
            texts[exercise.id]?.let { exercise.copy(instructions = it.instructions, commonMistakes = it.commonMistakes) }
                ?: exercise
        },
    )

    /** Sažeci za popis i pretragu. */
    fun summaries(language: String): List<ExerciseSummary> = exercises.map { exercise ->
        ExerciseSummary(
            source = ExerciseSummary.Source.Catalog(exercise.id),
            name = exercise.displayName(language),
            alternativeNames = exercise.name.values.toList(),
            category = exercise.category,
            kind = exercise.kind,
            muscles = exercise.primaryMuscles,
            equipment = exercise.equipment,
            isArchived = false,
        )
    }

    fun encode(): String = CatalogJson.encodeToString(Stored.serializer(), Stored(version, source, exercises))

    @Serializable
    private class Stored(val version: Int, val source: CatalogSource, val exercises: List<CatalogExercise>)

    companion object {
        fun decode(json: String): ExerciseCatalog {
            val stored = CatalogJson.decodeFromString(Stored.serializer(), json)
            return ExerciseCatalog(stored.version, stored.source, stored.exercises)
        }
    }
}
