package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCatalog
import java.text.Normalizer
import java.util.Locale

/**
 * Povezuje vježbu iz datoteke druge aplikacije (naziv i oprema) s vježbom iz kataloga.
 * Vježba koja se ne poveže uvozi se kao vlastita vježba.
 */
object ForeignExerciseMatcher {

    /** Poznati nazivi iz izvoza druge aplikacije: (naziv, oprema) → id u katalogu. */
    internal class KnownName(val name: String, val equipment: String, val catalogId: String)

    /**
     * Vježbe koje u katalogu nemaju pravi par (npr. veslanje s trakama) namjerno nisu ovdje:
     * bolje vlastita vježba nego pogrešna povijest i rekordi druge vježbe. Popis je isti kao na iOS-u.
     */
    internal val knownNames: List<KnownName> = listOf(
        KnownName("Bench Press", "Barbell", "barbell-bench-press"),
        KnownName("Incline Bench Press", "Barbell", "barbell-incline-bench-press"),
        KnownName("Bench Press", "Dumbbells", "dumbbell-bench-press"),
        KnownName("Incline Bench Press", "Dumbbells", "dumbbell-incline-bench-press"),
        KnownName("Chest Press", "Machine", "machine-chest-press"),
        KnownName("Butterfly", "Machine", "machine-pec-fly"),
        KnownName("Butterfly with Wide Grip", "Machine", "machine-pec-fly"),
        KnownName("High Cable Flys", "Cable", "cable-high-to-low-fly"),
        KnownName("Cable Flys", "Cable", "cable-high-to-low-fly"),
        KnownName("Low Cable Flys", "Cable", "cable-low-to-high-fly"),
        KnownName("Flys", "Dumbbells", "dumbbell-chest-fly"),
        KnownName("Incline Flys", "Dumbbells", "dumbbell-incline-chest-fly"),
        KnownName("Push-Ups", "Bodyweight", "push-up"),
        KnownName("Pull-Ups", "Bodyweight", "pull-ups"),
        KnownName("Chin-Ups", "Bodyweight", "chin-ups"),
        KnownName("Lat Pulldowns with Wide Overhand Grip", "Cable", "wide-grip-lat-pulldown"),
        KnownName("Lat Pulldowns with Close Neutral Grip", "Cable", "neutral-grip-lat-pulldown"),
        KnownName("Lat Pulldowns with Reverse Grip", "Cable", "lat-pulldown"),
        KnownName("Lat Pulldowns", "Cable", "wide-grip-lat-pulldown"),
        KnownName("Rows with Close Grip", "Cable", "machine-seated-cable-row"),
        KnownName("Rows", "Cable", "machine-seated-cable-row"),
        KnownName("Rows", "Barbell", "barbell-bent-over-row"),
        KnownName("Incline Rows", "Dumbbells", "dumbbell-incline-row"),
        KnownName("One-Arm Rows", "Dumbbells", "dumbbell-single-arm-row"),
        KnownName("Deadlifts", "Barbell", "barbell-deadlift"),
        KnownName("Romanian Deadlifts", "Barbell", "barbell-romanian-deadlift"),
        KnownName("Romanian Deadlifts", "Dumbbells", "dumbbell-stiff-leg-deadlift"),
        KnownName("Shrugs", "Dumbbells", "dumbbell-shrug"),
        KnownName("Shrugs", "Barbell", "barbell-shrug"),
        KnownName("Shoulder Press", "Dumbbells", "dumbbell-seated-overhead-press"),
        KnownName("Seated Shoulder Press", "Dumbbells", "dumbbell-seated-overhead-press"),
        KnownName("Shoulder Press", "Machine", "selectorized-overhead-press-machine"),
        KnownName("Overhead Press", "Barbell", "barbell-overhead-press"),
        KnownName("Arnold Press", "Dumbbells", "arnold-press"),
        KnownName("Lateral Raises", "Dumbbells", "dumbbell-lateral-raise"),
        KnownName("Lateral Raises", "Cable", "cable-low-single-arm-lateral-raise"),
        KnownName("Front Raises", "Dumbbells", "dumbbell-front-raise"),
        KnownName("Reverse Flys", "Dumbbells", "dumbbell-rear-delt-fly"),
        KnownName("Incline Reverse Flys", "Dumbbells", "dumbbell-rear-delt-fly"),
        KnownName("Reverse Flys", "Machine", "reverse-pec-deck"),
        KnownName("Face Pulls", "Cable", "machine-face-pulls"),
        KnownName("Curls", "Dumbbells", "dumbbell-curl"),
        KnownName("Curls", "Barbell", "barbell-curl"),
        KnownName("Curls", "EZ bar", "barbell-curl"),
        KnownName("Curls", "Cable", "cable-bar-curl"),
        KnownName("Hammer Curls", "Dumbbells", "dumbbell-hammer-curl"),
        KnownName("Incline Curls", "Dumbbells", "dumbbell-incline-curl"),
        KnownName("Concentration Curls", "Dumbbells", "dumbbell-concentration-curl"),
        KnownName("Preacher Curls", "EZ bar", "ez-bar-preacher-curl"),
        KnownName("Preacher Curls", "Barbell", "ez-bar-preacher-curl"),
        KnownName("Preacher Curls", "Machine", "machine-preacher-curl"),
        KnownName("Triceps Pushdowns", "Cable", "cable-bar-pushdown"),
        KnownName("Triceps Pushdowns with Rope", "Cable", "cable-rope-pushdown"),
        KnownName("Overhead Triceps Extensions", "Dumbbells", "dumbbell-seated-overhead-tricep-extension"),
        KnownName("Overhead Triceps Extensions", "Cable", "cable-rope-overhead-tricep-extension"),
        KnownName("Skull Crushers", "EZ bar", "ez-bar-skullcrusher"),
        KnownName("Triceps Kickbacks", "Dumbbells", "dumbbell-tricep-kickback"),
        KnownName("Dips", "Bodyweight", "parralel-bar-dips"),
        KnownName("Squats", "Barbell", "barbell-squat"),
        KnownName("Front Squats", "Barbell", "front-squat"),
        KnownName("Goblet Squats", "Dumbbells", "kettlebell-goblet-squat"),
        KnownName("Goblet Squats", "Kettlebell", "kettlebell-goblet-squat"),
        KnownName("Hack Squats", "Machine", "machine-hack-squat"),
        KnownName("Leg Press", "Machine", "machine-leg-press"),
        KnownName("Leg Extensions", "Machine", "machine-leg-extension"),
        KnownName("Lying Leg Curls", "Machine", "lying-leg-curl"),
        KnownName("Seated Leg Curls", "Machine", "seated-leg-curl"),
        KnownName("Lunges", "Dumbbells", "dumbbell-alternating-forward-lunge"),
        KnownName("Bulgarian Split Squats", "Dumbbells", "dumbbell-bulgarian-split-squat"),
        KnownName("Hip Thrusts", "Barbell", "barbell-hip-thrust"),
        KnownName("Standing Calf Raises", "Machine", "standing-calf-raise-machine"),
        KnownName("Seated Calf Raises", "Machine", "seated-calf-raise"),
        KnownName("Crunches", "Bodyweight", "crunches"),
        KnownName("Cable Crunches", "Cable", "kneeling-cable-crunch"),
        KnownName("Plank", "Bodyweight", "front-plank"),
        KnownName("Side Plank", "Bodyweight", "elbow-side-plank"),
        KnownName("Hanging Leg Raises", "Bodyweight", "toes-to-bar"),
        KnownName("Seated Curls", "Dumbbells", "seated-dumbbell-curl"),
        KnownName("Drag Curls", "Barbell", "barbell-drag-curl"),
        KnownName("Drag Hammer Curls", "Dumbbells", "barbell-drag-curl"),
        KnownName("Incline Chest Press", "Machine", "incline-machine-chest-press"),
        // Isti pokret: u katalogu je na spravi, a u izvozu s vlastitom težinom i teretom.
        KnownName("Standing Calf Raises", "Bodyweight", "standing-calf-raise-machine"),
        KnownName("Russian Twists", "Bodyweight", "bodyweight-russian-twist"),
    )

    /** Oprema iz datoteke → oprema u katalogu. */
    fun equipment(text: String): Equipment? = when (normalized(text)) {
        "" -> null
        "barbell", "barbells" -> Equipment.BARBELL
        "ez bar", "ezbar", "ez-bar" -> Equipment.EZ_BAR
        "dumbbell", "dumbbells" -> Equipment.DUMBBELL
        "cable", "cables" -> Equipment.CABLE
        "machine", "machines", "smith machine" -> Equipment.MACHINE
        "bodyweight", "body weight", "none" -> Equipment.BODYWEIGHT
        "kettlebell", "kettlebells" -> Equipment.KETTLEBELL
        "band", "bands", "resistance band", "resistance bands" -> Equipment.BANDS
        else -> Equipment.OTHER
    }

    /** Id vježbe u katalogu ili null ako je treba uvesti kao vlastitu vježbu. */
    fun catalogId(name: String, equipment: String, catalog: ExerciseCatalog): String? {
        val key = normalized(name)
        val equipmentKey = normalized(equipment)
        val known = knownNames.firstOrNull { normalized(it.name) == key && normalized(it.equipment) == equipmentKey }
        if (known != null && catalog.exercise(known.catalogId) != null) return known.catalogId
        // Isti naziv kao u katalogu (engleski ili hrvatski) i ista oprema.
        val wanted = equipment(equipment)
        val wantedName = nameKey(name)
        return catalog.exercises.firstOrNull { exercise ->
            exercise.name.values.any { nameKey(it) == wantedName } && (wanted == null || wanted == exercise.equipment)
        }?.id
    }

    private val combiningMarks = Regex("\\p{Mn}+")
    private val whitespace = Regex("\\s+")

    /** Mala slova, bez dijakritika i s jednim razmakom između riječi. */
    fun normalized(text: String): String {
        val folded = combiningMarks.replace(Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFD), "")
        return folded.split(whitespace).filter { it.isNotEmpty() }.joinToString(" ")
    }

    /** Za usporedbu s katalogom: bez interpunkcije i bez množine na kraju riječi ("Leg Curls" = "Leg Curl"). */
    private fun nameKey(text: String): String =
        normalized(text).split { !it.isLetter() && !it.isDigit() }
            .filter { it.isNotEmpty() }
            .joinToString(" ") { word -> if (word.length > 3 && word.endsWith("s")) word.dropLast(1) else word }

    private fun String.split(predicate: (Char) -> Boolean): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        for (character in this) {
            if (predicate(character)) {
                result += current.toString()
                current.setLength(0)
            } else {
                current.append(character)
            }
        }
        result += current.toString()
        return result
    }
}
