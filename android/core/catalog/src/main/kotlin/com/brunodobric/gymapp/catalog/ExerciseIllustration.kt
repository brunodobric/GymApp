package com.brunodobric.gymapp.catalog

/** Kako se prikazuje službena vježba: MoveKit klip u petlji s posterom, samo poster ili ništa. */
sealed interface ExerciseIllustration {
    /** Klip u petlji. Poster se prikazuje dok se klip učitava i uz isključene animacije. */
    data class Video(val path: String, val poster: String?) : ExerciseIllustration

    /** Samo mirna slika. */
    data class Poster(val path: String) : ExerciseIllustration

    data object Unavailable : ExerciseIllustration
}

/**
 * Ilustracija iz putanja u katalogu. [isAvailable] kaže postoji li datoteka u buildu: build bez
 * MoveKit paketa (CI, klon repozitorija) nema medije, pa vježba nema ni klip ni poster.
 */
fun CatalogExercise.illustration(isAvailable: (String) -> Boolean): ExerciseIllustration {
    val availablePoster = poster?.takeIf(isAvailable)
    val availableVideo = video?.takeIf(isAvailable)
    return when {
        availableVideo != null -> ExerciseIllustration.Video(availableVideo, availablePoster)
        availablePoster != null -> ExerciseIllustration.Poster(availablePoster)
        else -> ExerciseIllustration.Unavailable
    }
}
