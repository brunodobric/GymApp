import Catalog
import Foundation

/// Povezuje vježbu iz datoteke druge aplikacije (naziv i oprema) s vježbom iz kataloga.
/// Vježba koja se ne poveže uvozi se kao vlastita vježba.
public enum ForeignExerciseMatcher {

    /// Poznati nazivi iz izvoza druge aplikacije: (naziv, oprema) → id u katalogu.
    /// Vježbe koje u katalogu nemaju pravi par (npr. veslanje s trakama) namjerno nisu ovdje:
    /// bolje vlastita vježba nego pogrešna povijest i rekordi druge vježbe.
    struct KnownName {
        let name: String
        let equipment: String
        let catalogId: String

        init(_ name: String, _ equipment: String, _ catalogId: String) {
            self.name = name
            self.equipment = equipment
            self.catalogId = catalogId
        }
    }

    static let knownNames: [KnownName] = [
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
    ]

    /// Oprema iz datoteke → oprema u katalogu.
    public static func equipment(from text: String) -> Equipment? {
        switch normalized(text) {
        case "": nil
        case "barbell", "barbells": .barbell
        case "ez bar", "ezbar", "ez-bar": .ezBar
        case "dumbbell", "dumbbells": .dumbbell
        case "cable", "cables": .cable
        case "machine", "machines", "smith machine": .machine
        case "bodyweight", "body weight", "none": .bodyweight
        case "kettlebell", "kettlebells": .kettlebell
        case "band", "bands", "resistance band", "resistance bands": .bands
        default: .other
        }
    }

    /// Id vježbe u katalogu ili nil ako je treba uvesti kao vlastitu vježbu.
    public static func catalogId(name: String, equipment text: String, catalog: ExerciseCatalog) -> String? {
        let key = normalized(name)
        let equipmentKey = normalized(text)
        if let known = knownNames.first(where: { normalized($0.name) == key && normalized($0.equipment) == equipmentKey }),
           catalog.exercise(withID: known.catalogId) != nil {
            return known.catalogId
        }
        // Isti naziv kao u katalogu (engleski ili hrvatski) i ista oprema.
        let wanted = equipment(from: text)
        let byName = catalog.exercises.first { exercise in
            exercise.name.values.contains { nameKey($0) == nameKey(name) }
                && (wanted == nil || wanted == exercise.equipment)
        }
        return byName?.id
    }

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Za usporedbu s katalogom: bez interpunkcije i bez množine na kraju riječi ("Leg Curls" = "Leg Curl").
    private static func nameKey(_ text: String) -> String {
        normalized(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map { word in word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : String(word) }
            .joined(separator: " ")
    }
}
