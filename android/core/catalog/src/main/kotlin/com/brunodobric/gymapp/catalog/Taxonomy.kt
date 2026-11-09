package com.brunodobric.gymapp.catalog

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Pojmovi kataloga. Vrijednosti (raw) su stabilni ključevi u catalog.json, u korisničkoj bazi i u
// sigurnosnoj kopiji, isti kao na iOS-u. Nazivi za prikaz dolaze iz lokalizacije u aplikaciji.

/** Zajedničko sučelje enuma kataloga: tekst koji se sprema. */
interface RawValued {
    val raw: String
}

inline fun <reified T> rawValueOf(raw: String?): T? where T : Enum<T>, T : RawValued =
    raw?.let { value -> enumValues<T>().firstOrNull { it.raw == value } }

/** Naše kategorije (specifikacija, odjeljak 1). */
@Serializable
enum class ExerciseCategory(override val raw: String) : RawValued {
    @SerialName("chest") CHEST("chest"),
    @SerialName("back") BACK("back"),
    @SerialName("shoulders") SHOULDERS("shoulders"),
    @SerialName("arms") ARMS("arms"),
    @SerialName("legs") LEGS("legs"),
    @SerialName("core") CORE("core"),
    @SerialName("cardio") CARDIO("cardio"),
}

/**
 * Vrsta vježbe, neovisno o dijelu tijela. Početna kataloga grupira vježbe po vrsti.
 * Kardio vježbe su uvijek i u kategoriji [ExerciseCategory.CARDIO]. Redoslijed je redoslijed prikaza.
 */
@Serializable
enum class ExerciseKind(override val raw: String) : RawValued {
    /** Dinamične vježbe pokretljivosti prije treninga (MoveKit obrazac Mobility). */
    @SerialName("warmUp") WARM_UP("warmUp"),

    /** Vježbe snage (sve što nije kardio, zagrijavanje ni istezanje). */
    @SerialName("strength") STRENGTH("strength"),

    /** Statično istezanje (MoveKit obrazac Stretch). */
    @SerialName("stretching") STRETCHING("stretching"),
    @SerialName("cardio") CARDIO("cardio");

    companion object {
        /** Vrsta kad je izvor ne navodi (stariji catalog.json, vlastite vježbe): kardio po kategoriji, inače snaga. */
        fun fallback(category: ExerciseCategory?): ExerciseKind =
            if (category == ExerciseCategory.CARDIO) CARDIO else STRENGTH
    }
}

/** Naši mišići. MoveKit nazive mišića prevodi CatalogBuilder (Tools/CatalogBuilder/mapping.json). */
@Serializable
enum class Muscle(override val raw: String) : RawValued {
    @SerialName("chest") CHEST("chest"),
    @SerialName("shoulders") SHOULDERS("shoulders"),
    @SerialName("triceps") TRICEPS("triceps"),
    @SerialName("biceps") BICEPS("biceps"),
    @SerialName("forearms") FOREARMS("forearms"),
    @SerialName("lats") LATS("lats"),
    @SerialName("middle back") MIDDLE_BACK("middle back"),
    @SerialName("lower back") LOWER_BACK("lower back"),
    @SerialName("traps") TRAPS("traps"),
    @SerialName("neck") NECK("neck"),
    @SerialName("quadriceps") QUADRICEPS("quadriceps"),
    @SerialName("hamstrings") HAMSTRINGS("hamstrings"),
    @SerialName("glutes") GLUTES("glutes"),
    @SerialName("calves") CALVES("calves"),
    @SerialName("adductors") ADDUCTORS("adductors"),
    @SerialName("abductors") ABDUCTORS("abductors"),
    @SerialName("abdominals") ABDOMINALS("abdominals"),
}

@Serializable
enum class Equipment(override val raw: String) : RawValued {
    @SerialName("barbell") BARBELL("barbell"),
    @SerialName("ezBar") EZ_BAR("ezBar"),
    @SerialName("dumbbell") DUMBBELL("dumbbell"),
    @SerialName("cable") CABLE("cable"),
    @SerialName("machine") MACHINE("machine"),
    @SerialName("bodyweight") BODYWEIGHT("bodyweight"),
    @SerialName("kettlebell") KETTLEBELL("kettlebell"),
    @SerialName("bands") BANDS("bands"),
    @SerialName("other") OTHER("other"),
}

@Serializable
enum class Level(override val raw: String) : RawValued {
    @SerialName("beginner") BEGINNER("beginner"),
    @SerialName("intermediate") INTERMEDIATE("intermediate"),
    @SerialName("advanced") ADVANCED("advanced"),
}

@Serializable
enum class Mechanic(override val raw: String) : RawValued {
    @SerialName("compound") COMPOUND("compound"),
    @SerialName("isolation") ISOLATION("isolation"),
}

@Serializable
enum class MovementType(override val raw: String) : RawValued {
    @SerialName("push") PUSH("push"),
    @SerialName("pull") PULL("pull"),
    @SerialName("legs") LEGS("legs"),
}

/** Vrsta unosa vježbe: određuje polja u retku serije i način računanja volumena (specifikacija, odjeljak 2). */
@Serializable
enum class ExerciseInputType(override val raw: String) : RawValued {
    @SerialName("weightReps") WEIGHT_REPS("weightReps"),
    @SerialName("bodyweight") BODYWEIGHT("bodyweight"),
    @SerialName("weightedBodyweight") WEIGHTED_BODYWEIGHT("weightedBodyweight"),
    @SerialName("assisted") ASSISTED("assisted"),
    @SerialName("duration") DURATION("duration"),
    @SerialName("durationDistance") DURATION_DISTANCE("durationDistance"),
}
