import Catalog
import Foundation

/// Povezuje vježbu iz datoteke druge aplikacije (naziv i oprema) s vježbom iz kataloga.
/// Vježba koja se ne poveže uvozi se kao vlastita vježba.
public enum ForeignExerciseMatcher {

    /// Poznati nazivi iz izvoza druge aplikacije: (naziv, oprema) → id u katalogu.
    /// Vježbe koje u katalogu nemaju pravi par (npr. "Hanging Leg Raises", "Drag Hammer Curls")
    /// namjerno nisu ovdje: bolje vlastita vježba nego pogrešna povijest i rekordi druge vježbe.
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
        KnownName("Bench Press", "Barbell", "Barbell_Bench_Press_-_Medium_Grip"),
        KnownName("Incline Bench Press", "Barbell", "Barbell_Incline_Bench_Press_-_Medium_Grip"),
        KnownName("Bench Press", "Dumbbells", "Dumbbell_Bench_Press"),
        KnownName("Incline Bench Press", "Dumbbells", "Incline_Dumbbell_Press"),
        KnownName("Chest Press", "Machine", "Machine_Bench_Press"),
        KnownName("Butterfly", "Machine", "Butterfly"),
        KnownName("Butterfly with Wide Grip", "Machine", "Butterfly"),
        KnownName("High Cable Flys", "Cable", "Cable_Crossover"),
        KnownName("Cable Flys", "Cable", "Cable_Crossover"),
        KnownName("Low Cable Flys", "Cable", "Low_Cable_Crossover"),
        KnownName("Flys", "Dumbbells", "Dumbbell_Flyes"),
        KnownName("Incline Flys", "Dumbbells", "Incline_Dumbbell_Flyes"),
        KnownName("Push-Ups", "Bodyweight", "Pushups"),
        KnownName("Pull-Ups", "Bodyweight", "Pullups"),
        KnownName("Chin-Ups", "Bodyweight", "Chin-Up"),
        KnownName("Lat Pulldowns with Wide Overhand Grip", "Cable", "Wide-Grip_Lat_Pulldown"),
        KnownName("Lat Pulldowns with Close Neutral Grip", "Cable", "V-Bar_Pulldown"),
        KnownName("Lat Pulldowns with Reverse Grip", "Cable", "Underhand_Cable_Pulldowns"),
        KnownName("Lat Pulldowns", "Cable", "Wide-Grip_Lat_Pulldown"),
        KnownName("Rows with Close Grip", "Cable", "Seated_Cable_Rows"),
        KnownName("Rows", "Cable", "Seated_Cable_Rows"),
        KnownName("Rows", "Barbell", "Bent_Over_Barbell_Row"),
        KnownName("Incline Rows", "Dumbbells", "Dumbbell_Incline_Row"),
        KnownName("One-Arm Rows", "Dumbbells", "One-Arm_Dumbbell_Row"),
        KnownName("Deadlifts", "Barbell", "Barbell_Deadlift"),
        KnownName("Romanian Deadlifts", "Barbell", "Romanian_Deadlift"),
        KnownName("Romanian Deadlifts", "Dumbbells", "Stiff-Legged_Dumbbell_Deadlift"),
        KnownName("Shrugs", "Dumbbells", "Dumbbell_Shrug"),
        KnownName("Shrugs", "Barbell", "Barbell_Shrug"),
        KnownName("Shoulder Press", "Dumbbells", "Dumbbell_Shoulder_Press"),
        KnownName("Seated Shoulder Press", "Dumbbells", "Seated_Dumbbell_Press"),
        KnownName("Shoulder Press", "Machine", "Machine_Shoulder_Military_Press"),
        KnownName("Overhead Press", "Barbell", "Standing_Military_Press"),
        KnownName("Arnold Press", "Dumbbells", "Arnold_Dumbbell_Press"),
        KnownName("Lateral Raises", "Dumbbells", "Side_Lateral_Raise"),
        KnownName("Lateral Raises", "Cable", "Cable_Seated_Lateral_Raise"),
        KnownName("Front Raises", "Dumbbells", "Front_Dumbbell_Raise"),
        KnownName("Reverse Flys", "Dumbbells", "Reverse_Flyes"),
        KnownName("Incline Reverse Flys", "Dumbbells", "Reverse_Flyes"),
        KnownName("Reverse Flys", "Machine", "Reverse_Machine_Flyes"),
        KnownName("Face Pulls", "Cable", "Face_Pull"),
        KnownName("Curls", "Dumbbells", "Dumbbell_Bicep_Curl"),
        KnownName("Curls", "Barbell", "Barbell_Curl"),
        KnownName("Curls", "EZ bar", "EZ-Bar_Curl"),
        KnownName("Curls", "Cable", "Standing_Biceps_Cable_Curl"),
        KnownName("Hammer Curls", "Dumbbells", "Hammer_Curls"),
        KnownName("Incline Curls", "Dumbbells", "Incline_Dumbbell_Curl"),
        KnownName("Concentration Curls", "Dumbbells", "Concentration_Curls"),
        KnownName("Preacher Curls", "EZ bar", "Preacher_Curl"),
        KnownName("Preacher Curls", "Barbell", "Preacher_Curl"),
        KnownName("Preacher Curls", "Machine", "Machine_Preacher_Curls"),
        KnownName("Triceps Pushdowns", "Cable", "Triceps_Pushdown"),
        KnownName("Triceps Pushdowns with Rope", "Cable", "Triceps_Pushdown_-_Rope_Attachment"),
        KnownName("Overhead Triceps Extensions", "Dumbbells", "Standing_Dumbbell_Triceps_Extension"),
        KnownName("Overhead Triceps Extensions", "Cable", "Cable_Rope_Overhead_Triceps_Extension"),
        KnownName("Skull Crushers", "EZ bar", "EZ-Bar_Skullcrusher"),
        KnownName("Triceps Kickbacks", "Dumbbells", "Tricep_Dumbbell_Kickback"),
        KnownName("Dips", "Bodyweight", "Parallel_Bar_Dip"),
        KnownName("Squats", "Barbell", "Barbell_Squat"),
        KnownName("Front Squats", "Barbell", "Front_Squat_Clean_Grip"),
        KnownName("Goblet Squats", "Dumbbells", "Goblet_Squat"),
        KnownName("Goblet Squats", "Kettlebell", "Goblet_Squat"),
        KnownName("Hack Squats", "Machine", "Hack_Squat"),
        KnownName("Leg Press", "Machine", "Leg_Press"),
        KnownName("Leg Extensions", "Machine", "Leg_Extensions"),
        KnownName("Lying Leg Curls", "Machine", "Lying_Leg_Curls"),
        KnownName("Seated Leg Curls", "Machine", "Seated_Leg_Curl"),
        KnownName("Lunges", "Dumbbells", "Dumbbell_Lunges"),
        KnownName("Bulgarian Split Squats", "Dumbbells", "Split_Squat_with_Dumbbells"),
        KnownName("Hip Thrusts", "Barbell", "Barbell_Hip_Thrust"),
        KnownName("Standing Calf Raises", "Machine", "Standing_Calf_Raises"),
        KnownName("Seated Calf Raises", "Machine", "Seated_Calf_Raise"),
        KnownName("Crunches", "Bodyweight", "Crunches"),
        KnownName("Cable Crunches", "Cable", "Cable_Crunch"),
        KnownName("Plank", "Bodyweight", "Plank"),
        KnownName("Russian Twists", "Bodyweight", "Russian_Twist"),
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
