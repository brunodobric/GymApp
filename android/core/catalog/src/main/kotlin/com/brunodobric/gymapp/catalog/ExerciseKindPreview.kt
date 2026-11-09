package com.brunodobric.gymapp.catalog

/** Prepoznatljive vježbe za sličice na kartici vrste (početna kataloga), redom prikaza. */
internal val featuredIds: Map<ExerciseKind, List<String>> = mapOf(
    ExerciseKind.WARM_UP to listOf("arm-circles-front-back", "leg-swings-front-to-back", "hip-circles", "cat-camel"),
    ExerciseKind.STRENGTH to listOf("barbell-squat", "barbell-bench-press", "barbell-deadlift", "dumbbell-curl"),
    ExerciseKind.STRETCHING to listOf(
        "worlds-greatest-stretch", "spiderman-stretch", "adductor-groin-stretch", "standing-wall-shoulder-opening-stretch",
    ),
    ExerciseKind.CARDIO to listOf("treadmill-run", "rowing-machine-steady-state", "jump-rope", "indoor-cycling-spin"),
)

/**
 * Vježbe za sličice na kartici vrste: najprije odabrane, zatim ostale te vrste redom kataloga.
 * Preskače vježbe bez slike ([hasImage]), pa build bez MoveKit dodatka dobiva prazan popis.
 */
fun ExerciseCatalog.featured(kind: ExerciseKind, count: Int = 4, hasImage: (CatalogExercise) -> Boolean): List<CatalogExercise> {
    val preferred = featuredIds[kind].orEmpty().mapNotNull(::exercise)
    val others = exercises.filter { it.kind == kind }
    val seen = mutableSetOf<String>()
    val result = mutableListOf<CatalogExercise>()
    for (exercise in preferred + others) {
        if (exercise.kind != kind || !hasImage(exercise) || !seen.add(exercise.id)) continue
        result += exercise
        if (result.size == count) break
    }
    return result
}
