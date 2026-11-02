import Catalog
import Foundation
import Models

public enum PRKind: String, CaseIterable, Hashable, Sendable {
    case maxWeight
    case maxVolume
    case maxReps
    case lowestAssistance
    case longestDuration
    case longestDistance

    /// Tipovi koje korisnik uključuje u Postavkama (`UserSettings.trackedPRKinds`):
    /// "maxWeight", "maxVolume" i "maxReps" pokrivaju i srodne tipove za potpomognute vježbe i trajanje.
    public static func kinds(fromSettings raw: [String]) -> Set<PRKind> {
        var result = Set<PRKind>()
        for item in raw {
            switch item {
            case "maxWeight": result.formUnion([.maxWeight, .lowestAssistance])
            case "maxVolume": result.insert(.maxVolume)
            case "maxReps": result.formUnion([.maxReps, .longestDuration, .longestDistance])
            default: break
            }
        }
        return result
    }
}

public struct PersonalRecord: Equatable, Sendable {
    public let kind: PRKind
    /// kg, ponavljanja, sekunde ili metri, ovisno o vrsti. Volumen je kg.
    public let value: Double
    /// nil kad za usporedbu nema ničega (npr. prvi put s tom težinom).
    public let previousBest: Double?
}

/// Prepoznavanje osobnih rekorda (samo radne serije). Pravila:
/// * bez ranije povijesti nema rekorda (inače bi prvi trening bio sam po sebi rekord);
/// * težina: najveća težina s barem jednim ponavljanjem; volumen: ukupni volumen vježbe u jednom treningu;
/// * ponavljanja: serija je rekord ako ranije nije bilo serije s istom ili većom težinom i barem toliko ponavljanja;
/// * potpomognuta: rekord je manja pomoć, a ponavljanja se gledaju uz istu ili manju pomoć;
/// * trajanje i udaljenost: najdulje u jednoj seriji.
public enum PersonalRecordDetector {
    private static let epsilon = 1e-9

    /// - Parameters:
    ///   - current: završene serije vježbe u ovom treningu
    ///   - history: završene serije iste vježbe u ranijim treninzima (jedan niz po treningu)
    public static func records(
        current: [SetValues],
        history: [[SetValues]],
        inputType: ExerciseInputType,
        kinds: Set<PRKind> = Set(PRKind.allCases)
    ) -> [PersonalRecord] {
        let now = current.filter { $0.kind == .working }
        let sessions = history.map { $0.filter { $0.kind == .working } }.filter { !$0.isEmpty }
        let past = sessions.flatMap { $0 }
        guard !now.isEmpty, !past.isEmpty else { return [] }

        var result: [PersonalRecord] = []
        switch inputType {
        case .weightReps:
            result += weightRecord(now.map { ($0.weightKg ?? 0, $0.reps ?? 0) }, past.map { ($0.weightKg ?? 0, $0.reps ?? 0) })
            result += volumeRecord(now, sessions, inputType)
            result += repsRecord(now.map { ($0.weightKg ?? 0, $0.reps ?? 0) }, past.map { ($0.weightKg ?? 0, $0.reps ?? 0) }, heavierIsBetter: true)
        case .weightedBodyweight:
            result += weightRecord(now.map { ($0.extraWeightKg ?? 0, $0.reps ?? 0) }, past.map { ($0.extraWeightKg ?? 0, $0.reps ?? 0) })
            result += volumeRecord(now, sessions, inputType)
            result += repsRecord(now.map { ($0.extraWeightKg ?? 0, $0.reps ?? 0) }, past.map { ($0.extraWeightKg ?? 0, $0.reps ?? 0) }, heavierIsBetter: true)
        case .bodyweight:
            result += repsRecord(now.map { (0, $0.reps ?? 0) }, past.map { (0, $0.reps ?? 0) }, heavierIsBetter: true)
        case .assisted:
            result += assistanceRecord(now, past)
            result += repsRecord(now.map { ($0.extraWeightKg ?? 0, $0.reps ?? 0) }, past.map { ($0.extraWeightKg ?? 0, $0.reps ?? 0) }, heavierIsBetter: false)
        case .duration:
            result += longestRecord(.longestDuration, now.map { Double($0.durationSeconds ?? 0) }, past.map { Double($0.durationSeconds ?? 0) })
        case .durationDistance:
            result += longestRecord(.longestDuration, now.map { Double($0.durationSeconds ?? 0) }, past.map { Double($0.durationSeconds ?? 0) })
            result += longestRecord(.longestDistance, now.map { $0.distanceMeters ?? 0 }, past.map { $0.distanceMeters ?? 0 })
        }
        return result.filter { kinds.contains($0.kind) }
    }

    private static func weightRecord(_ now: [(Double, Int)], _ past: [(Double, Int)]) -> [PersonalRecord] {
        let best = now.filter { $0.1 >= 1 }.map(\.0).max() ?? 0
        let before = past.filter { $0.1 >= 1 }.map(\.0).max() ?? 0
        guard best > before + epsilon else { return [] }
        return [PersonalRecord(kind: .maxWeight, value: best, previousBest: before)]
    }

    private static func volumeRecord(_ now: [SetValues], _ sessions: [[SetValues]], _ type: ExerciseInputType) -> [PersonalRecord] {
        let total = now.reduce(0) { $0 + SetMetrics.volume($1, inputType: type) }
        let before = sessions.map { $0.reduce(0) { $0 + SetMetrics.volume($1, inputType: type) } }.max() ?? 0
        guard total > before + epsilon else { return [] }
        return [PersonalRecord(kind: .maxVolume, value: total, previousBest: before)]
    }

    /// `heavierIsBetter`: veća težina je bolja (teret); inače je bolja manja (pomoć).
    private static func repsRecord(_ now: [(Double, Int)], _ past: [(Double, Int)], heavierIsBetter: Bool) -> [PersonalRecord] {
        var best: (reps: Int, previous: Int)?
        for (load, reps) in now where reps >= 1 {
            let comparable = past.filter { heavierIsBetter ? $0.0 >= load - epsilon : $0.0 <= load + epsilon }
            let previous = comparable.map(\.1).max() ?? 0
            if reps > previous, reps > (best?.reps ?? 0) {
                best = (reps, previous)
            }
        }
        guard let best else { return [] }
        return [PersonalRecord(kind: .maxReps, value: Double(best.reps), previousBest: best.previous > 0 ? Double(best.previous) : nil)]
    }

    private static func assistanceRecord(_ now: [SetValues], _ past: [SetValues]) -> [PersonalRecord] {
        let best = now.filter { ($0.reps ?? 0) >= 1 }.map { $0.extraWeightKg ?? 0 }.min()
        let before = past.filter { ($0.reps ?? 0) >= 1 }.map { $0.extraWeightKg ?? 0 }.min()
        guard let best, let before, best < before - epsilon else { return [] }
        return [PersonalRecord(kind: .lowestAssistance, value: best, previousBest: before)]
    }

    private static func longestRecord(_ kind: PRKind, _ now: [Double], _ past: [Double]) -> [PersonalRecord] {
        let best = now.max() ?? 0
        let before = past.max() ?? 0
        guard best > before + epsilon else { return [] }
        return [PersonalRecord(kind: kind, value: best, previousBest: before > 0 ? before : nil)]
    }
}
