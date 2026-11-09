package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.catalog.uppercaseString
import com.brunodobric.gymapp.model.CustomExercise

/** Regije tijela za heatmap. Nazivi su isti kao u katalogu (`primaryRegions`). */
object BodyRegion {
    /** Sve regije, redom za prikaz: prednja strana pa stražnja. */
    val all = listOf(
        "chest", "shoulders", "biceps", "forearms", "abs", "quads", "innerThigh", "outerThigh",
        "traps", "upperBack", "lats", "triceps", "lowerBack", "glutes", "hamstrings", "calves",
    )

    /**
     * Glavne mišićne skupine za koje statistika javlja da zaostaju (ispod 5 tvrdih serija tjedno).
     * Manje regije (podlaktice, trapez, donja leđa, bedra sa strane) dobivaju dovoljno rada iz drugih vježbi.
     */
    val major = listOf("chest", "shoulders", "biceps", "triceps", "upperBack", "lats", "quads", "hamstrings", "glutes", "calves")

    /**
     * Skupina mišića koja ima svoju boju u sučelju (čipovi, graf mišića). Bliske regije dijele boju,
     * da paleta ostane mala: sva leđa su jedna boja, sve noge osim gluteusa druga.
     */
    enum class ColorGroup { CHEST, SHOULDERS, BICEPS, TRICEPS, FOREARMS, CORE, BACK, LEGS, GLUTES }

    /** Boja regije; nepoznata regija nema boju. */
    fun colorGroup(region: String): ColorGroup? = when (region) {
        "chest" -> ColorGroup.CHEST
        "shoulders" -> ColorGroup.SHOULDERS
        "biceps" -> ColorGroup.BICEPS
        "triceps" -> ColorGroup.TRICEPS
        "forearms" -> ColorGroup.FOREARMS
        "abs" -> ColorGroup.CORE
        "traps", "upperBack", "lats", "lowerBack" -> ColorGroup.BACK
        "quads", "hamstrings", "innerThigh", "outerThigh", "calves" -> ColorGroup.LEGS
        "glutes" -> ColorGroup.GLUTES
        else -> null
    }

    /** Regija za mišić. Koristi se za vlastite vježbe, koje nemaju regije iz kataloga. */
    fun region(muscle: Muscle): String = when (muscle) {
        Muscle.CHEST -> "chest"
        Muscle.SHOULDERS -> "shoulders"
        Muscle.TRICEPS -> "triceps"
        Muscle.BICEPS -> "biceps"
        Muscle.FOREARMS -> "forearms"
        Muscle.LATS -> "lats"
        Muscle.MIDDLE_BACK -> "upperBack"
        Muscle.LOWER_BACK -> "lowerBack"
        Muscle.TRAPS, Muscle.NECK -> "traps"
        Muscle.QUADRICEPS -> "quads"
        Muscle.HAMSTRINGS -> "hamstrings"
        Muscle.GLUTES -> "glutes"
        Muscle.CALVES -> "calves"
        Muscle.ADDUCTORS -> "innerThigh"
        Muscle.ABDUCTORS -> "outerThigh"
        Muscle.ABDOMINALS -> "abs"
    }

    /** Regija heatmapa za grupu mišića iz MuscleMap crteža. Null za nepoznatu grupu. */
    fun regionForBodyMapGroup(group: String): String? = when (group) {
        "CHEST" -> "chest"
        "SHOULDERS_FRONT", "SHOULDERS_SIDE", "SHOULDERS_REAR" -> "shoulders"
        "BICEPS" -> "biceps"
        "TRICEPS" -> "triceps"
        "FOREARMS" -> "forearms"
        "CORE", "OBLIQUES" -> "abs"
        "QUADS" -> "quads"
        "HAMSTRINGS" -> "hamstrings"
        "ADDUCTORS" -> "innerThigh"
        "ABDUCTORS" -> "outerThigh"
        "TRAPEZIUS" -> "traps"
        "RHOMBOIDS" -> "upperBack"
        "LATS" -> "lats"
        "BACK_LOWER" -> "lowerBack"
        "GLUTES" -> "glutes"
        "CALVES" -> "calves"
        else -> null
    }
}

/** Gradi [ExerciseInfoProvider] iz kataloga i vlastitih vježbi, po ključu `ExerciseRef.key`. */
object ExerciseInfoBuilder {
    fun provider(catalog: ExerciseCatalog?, custom: List<CustomExercise>): ExerciseInfoProvider {
        val table = HashMap<String, ExerciseInfo>()
        for (exercise in catalog?.exercises.orEmpty()) {
            table["c:${exercise.id}"] = ExerciseInfo(
                exercise.primaryMuscles, exercise.secondaryMuscles, exercise.primaryRegions, exercise.secondaryRegions,
                isCompound = exercise.mechanic?.let { it == Mechanic.COMPOUND }, isCardio = exercise.kind == ExerciseKind.CARDIO,
            )
        }
        for (exercise in custom) {
            val muscles = exercise.muscles
            val regions = muscles.map(BodyRegion::region).distinct()
            table["u:${exercise.id.uppercaseString}"] = ExerciseInfo(
                primary = muscles, primaryRegions = regions, isCardio = exercise.kind == ExerciseKind.CARDIO,
            )
        }
        return { table[it] }
    }

    /** Je li vježba kardio, za `SessionCardio` i sažetak treninga. Nepoznata vježba nije kardio. */
    fun isCardio(info: ExerciseInfoProvider): (String) -> Boolean = { info(it)?.isCardio == true }
}
