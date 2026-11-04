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

    /// Tipovi koji se stvarno prate: prazno kad su PR-ovi isključeni u Postavkama.
    public static func tracked(by settings: UserSettings?) -> Set<PRKind> {
        guard let settings else { return Set(PRKind.allCases) }
        return settings.prEnabled ? kinds(fromSettings: settings.trackedPRKinds) : []
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
/// * težina: najveća težina s barem jednim ponavljanjem; volumen: najveći volumen jedne serije;
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

    /// Sažima povijest na serije koje mogu odlučiti o rekordu, za bilo koju vrstu unosa: Pareto granicu
    /// (opterećenje, ponavljanja) za težinu i dodatnu težinu u oba smjera te seriju s najvećim volumenom,
    /// trajanjem i udaljenošću. `records(current:history:)` sa sažetom poviješću daje iste rekorde kao s punom,
    /// pa statistika ne mora za svaki trening ponovno prolaziti cijelu raniju povijest.
    public static func condensed(_ history: [[SetValues]]) -> [[SetValues]] {
        let sets = history.flatMap { $0 }.filter { $0.kind == .working }
        guard !sets.isEmpty else { return [] }
        var keep = Set<Int>()
        let loads: [(SetValues) -> Double] = [{ $0.weightKg ?? 0 }, { $0.extraWeightKg ?? 0 }]
        for load in loads {
            keep.formUnion(frontier(of: sets, load: load, heavierIsBetter: true))
            keep.formUnion(frontier(of: sets, load: load, heavierIsBetter: false))
        }
        var measures: [(SetValues) -> Double] = ExerciseInputType.allCases.map { type -> (SetValues) -> Double in
            { set in SetMetrics.volume(set, inputType: type) }
        }
        measures.append { Double($0.durationSeconds ?? 0) }
        measures.append { $0.distanceMeters ?? 0 }
        for measure in measures {
            if let best = sets.indices.max(by: { measure(sets[$0]) < measure(sets[$1]) }) {
                keep.insert(best)
            }
        }
        return [keep.sorted().map { sets[$0] }]
    }

    /// Indeksi serija koje nijedna druga ne nadmašuje i opterećenjem i ponavljanjima.
    private static func frontier(
        of sets: [SetValues], load: (SetValues) -> Double, heavierIsBetter: Bool
    ) -> [Int] {
        let order = sets.indices.sorted { lhs, rhs in
            let left = load(sets[lhs])
            let right = load(sets[rhs])
            if left != right { return heavierIsBetter ? left > right : left < right }
            return (sets[lhs].reps ?? 0) > (sets[rhs].reps ?? 0)
        }
        var result: [Int] = []
        var bestReps = Int.min
        for index in order {
            let reps = sets[index].reps ?? 0
            if reps > bestReps {
                result.append(index)
                bestReps = reps
            }
        }
        return result
    }

    private static func weightRecord(_ now: [(Double, Int)], _ past: [(Double, Int)]) -> [PersonalRecord] {
        let best = now.filter { $0.1 >= 1 }.map(\.0).max() ?? 0
        let before = past.filter { $0.1 >= 1 }.map(\.0).max() ?? 0
        guard best > before + epsilon else { return [] }
        return [PersonalRecord(kind: .maxWeight, value: best, previousBest: before)]
    }

    private static func volumeRecord(_ now: [SetValues], _ sessions: [[SetValues]], _ type: ExerciseInputType) -> [PersonalRecord] {
        let total = now.map { SetMetrics.volume($0, inputType: type) }.max() ?? 0
        let before = sessions.flatMap { $0 }.map { SetMetrics.volume($0, inputType: type) }.max() ?? 0
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
