import Foundation

extension ExerciseCatalog {
    /// Prepoznatljive vježbe za sličice na kartici vrste (početna kataloga), redom prikaza.
    static let featuredIDs: [ExerciseKind: [String]] = [
        .warmUp: ["arm-circles-front-back", "leg-swings-front-to-back", "hip-circles", "cat-camel"],
        .strength: ["barbell-squat", "barbell-bench-press", "barbell-deadlift", "dumbbell-curl"],
        .stretching: ["worlds-greatest-stretch", "spiderman-stretch", "adductor-groin-stretch", "standing-wall-shoulder-opening-stretch"],
        .cardio: ["treadmill-run", "rowing-machine-steady-state", "jump-rope", "indoor-cycling-spin"]
    ]

    /// Vježbe za sličice na kartici vrste: najprije odabrane, zatim ostale te vrste redom kataloga.
    /// Preskače vježbe bez slike (`hasImage`), pa build bez MoveKit dodatka dobiva prazan popis.
    public func featured(
        _ kind: ExerciseKind, count: Int = 4, hasImage: (CatalogExercise) -> Bool
    ) -> [CatalogExercise] {
        let preferred = (Self.featuredIDs[kind] ?? []).compactMap { exercise(withID: $0) }
        let others = exercises.filter { $0.kind == kind }
        var seen = Set<String>()
        var result: [CatalogExercise] = []
        for exercise in preferred + others where exercise.kind == kind && hasImage(exercise) {
            guard seen.insert(exercise.id).inserted else { continue }
            result.append(exercise)
            if result.count == count { break }
        }
        return result
    }
}
