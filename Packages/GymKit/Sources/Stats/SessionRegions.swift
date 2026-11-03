import Foundation
import Models
import Training

/// Regije tijela koje je opteretio jedan trening (za prikaz u sažetku).
public enum SessionRegions {
    /// Intenzitet regije koja je bila samo sekundarna u svim vježbama treninga.
    public static let secondaryIntensity = 0.45

    /// Regije koje su rađene: primarne s intenzitetom 1, a one koje su samo pomagale s manjim.
    /// Broje se vježbe s barem jednom završenom radnom serijom; warm-up se ne računa.
    public static func worked(in session: Session, info: ExerciseInfoProvider) -> [String: RegionLoad] {
        var result: [String: RegionLoad] = [:]
        for exercise in session.orderedExercises where !exercise.isRemoved {
            guard let details = info(exercise.exerciseKey) else { continue }
            let done = exercise.orderedSets.filter(\.isCompleted).map(\.values).filter { $0.kind == .working }
            guard !done.isEmpty else { continue }
            let volume = done.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }
            for region in details.primaryRegions {
                var load = result[region] ?? RegionLoad(sessions: 1, volumeKg: 0, intensity: 0)
                load.volumeKg += volume
                load.intensity = 1
                result[region] = load
            }
            for region in details.secondaryRegions where result[region] == nil {
                result[region] = RegionLoad(sessions: 1, volumeKg: volume / 2, intensity: secondaryIntensity)
            }
        }
        return result
    }
}
