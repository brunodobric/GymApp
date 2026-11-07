import Catalog
import Foundation
import Models

/// Vrste osobnih rekorda. Glavni rekord snage je procjena 1RM; ostale vrste su dopuna za povijest i Pro prikaz
/// (`docs/SPECIFIKACIJA.md`, odjeljak o rekordima).
public enum PRKind: String, CaseIterable, Hashable, Sendable {
    /// Procjena 1RM iz pouzdane serije (s RIR-om, do 12 ponavljanja do otkaza).
    case estimatedOneRepMax
    /// Najteža serija s barem toliko ponavljanja (1, 3, 5, 8, 10, 12 ili 15), npr. "najteža petica".
    case repMax
    /// Najveća težina s barem jednim ponavljanjem: miljokaz ("prvi put 100 kg").
    case maxWeight
    /// Najveća tonaža vježbe u jednom treningu.
    case exerciseVolume
    /// Najviše ponavljanja u seriji (vlastita težina) ili uz istu ili manju pomoć (potpomognute).
    case maxReps
    case lowestAssistance
    case longestDuration
    case longestDistance

    /// Tipovi koje korisnik uključuje u Postavkama (`UserSettings.trackedPRKinds`). Zapis u postavkama ostaje
    /// isti kao u starijim verzijama: "maxWeight" je snaga (1RM, najveća težina, pomoć), "maxReps" ponavljanja
    /// (rekordi po rasponu ponavljanja, trajanje i udaljenost), a "maxVolume" tonaža vježbe u treningu.
    public static func kinds(fromSettings raw: [String]) -> Set<PRKind> {
        var result = Set<PRKind>()
        for item in raw {
            switch item {
            case "maxWeight": result.formUnion([.estimatedOneRepMax, .maxWeight, .lowestAssistance])
            case "maxVolume": result.insert(.exerciseVolume)
            case "maxReps": result.formUnion([.repMax, .maxReps, .longestDuration, .longestDistance])
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
    /// Dosadašnji najbolji rezultat. Rekord bez usporedbe ne postoji, pa je nil samo u starijim zapisima.
    public let previousBest: Double?
    /// Raspon ponavljanja za `repMax` (npr. 5 = najteža serija s barem 5 ponavljanja).
    public let reps: Int?
    /// Ide li rekord u sažetak treninga. Tonaža vježbe i najveća težina uz slabiju procjenu 1RM ostaju u povijesti.
    public let showsInSummary: Bool

    public init(kind: PRKind, value: Double, previousBest: Double?, reps: Int? = nil, showsInSummary: Bool = true) {
        self.kind = kind
        self.value = value
        self.previousBest = previousBest
        self.reps = reps
        self.showsInSummary = showsInSummary
    }
}

/// Ranija izvođenja jedne vježbe, sažeta na ono što odlučuje o rekordu. Izvođenja se dodaju od najstarijeg.
///
/// Pravila protiv "hrpe rekorda": vježba nema rekorda dok nema barem `calibrationSessions` ranijih izvođenja,
/// a nakon pauze od `pauseInterval` ni prva dva izvođenja ne daju rekord (korisnik se vraća na staro).
public struct RecordHistory: Equatable, Sendable {
    public static let calibrationSessions = 3
    public static let pauseInterval: TimeInterval = 6 * 7 * 24 * 3600

    /// Sažete radne serije (`PersonalRecordDetector.condensed`).
    public private(set) var sets: [SetValues] = []
    /// Najveća tonaža vježbe u jednom treningu.
    public private(set) var bestSessionVolume: Double = 0
    /// Broj izvođenja s barem jednom radnom serijom.
    public private(set) var sessionCount = 0
    public private(set) var lastDate: Date?
    /// Koliko još izvođenja nakon povratka s pauze ne daje rekord.
    private var cooldown = 0

    public init() {}

    /// Povijest iz izvođenja od najstarijeg prema najnovijem, bez datuma (pauza se tada ne prepoznaje).
    public init(sessions: [[SetValues]], inputType: ExerciseInputType) {
        for session in sessions { add(session, inputType: inputType, date: nil) }
    }

    /// Povijest s nesažetim serijama, za provjeru da sažimanje ne mijenja rekorde.
    init(uncondensed sets: [SetValues], bestSessionVolume: Double, sessionCount: Int) {
        self.sets = sets.filter { $0.kind == .working }
        self.bestSessionVolume = bestSessionVolume
        self.sessionCount = sessionCount
    }

    /// Smije li izvođenje na `date` dati rekord.
    public func allowsRecords(at date: Date?) -> Bool {
        sessionCount >= Self.calibrationSessions && cooldown == 0 && !isReturn(at: date)
    }

    /// Je li izvođenje na `date` prvo nakon pauze.
    public func isReturn(at date: Date?) -> Bool {
        guard let date, let lastDate else { return false }
        return date.timeIntervalSince(lastDate) >= Self.pauseInterval
    }

    public mutating func add(_ session: [SetValues], inputType: ExerciseInputType, date: Date?) {
        let working = session.filter { $0.kind == .working }
        guard !working.isEmpty else { return }
        if isReturn(at: date) {
            cooldown = 1
        } else if cooldown > 0 {
            cooldown -= 1
        }
        sessionCount += 1
        if let date { lastDate = max(lastDate ?? date, date) }
        let volume = working.reduce(0) { $0 + SetMetrics.volume($1, inputType: inputType) }
        bestSessionVolume = max(bestSessionVolume, volume)
        sets = PersonalRecordDetector.condensed(sets + working)
    }
}

/// Prepoznavanje osobnih rekorda (samo radne serije). Rekord vrijedi samo kad je napredak veći od praga
/// (`minimumRelativeGain` i najmanja apsolutna promjena), da sitni pomaci (0,5 kg na 140 kg) ne budu rekordi.
public enum PersonalRecordDetector {
    private static let epsilon = 1e-9
    /// Rasponi ponavljanja za `repMax`.
    public static let repRanges = [1, 3, 5, 8, 10, 12, 15]
    /// Najmanji relativni napredak za rekord (1 %).
    public static let minimumRelativeGain = 0.01
    /// Najmanji napredak težine za rekord.
    public static let minimumLoadGainKg = 0.5
    /// Najveća težina ide u sažetak samo ako je procjena 1RM tog treninga barem ovoliki udio najbolje.
    public static let milestoneTolerance = 0.97

    /// - Parameters:
    ///   - current: završene serije vježbe u ovom treningu
    ///   - history: ranija izvođenja iste vježbe
    ///   - date: početak ovog treninga (za pravilo povratka nakon pauze)
    public static func records(
        current: [SetValues],
        history: RecordHistory,
        inputType: ExerciseInputType,
        kinds: Set<PRKind> = Set(PRKind.allCases),
        date: Date? = nil
    ) -> [PersonalRecord] {
        let now = current.filter { $0.kind == .working }
        guard !now.isEmpty, history.allowsRecords(at: date) else { return [] }
        let past = history.sets

        var result: [PersonalRecord] = []
        switch inputType {
        case .weightReps, .weightedBodyweight:
            result += oneRepMaxRecord(now, past, inputType)
            result += repMaxRecord(now, past, inputType)
            result += weightRecord(now, past, inputType)
            result += exerciseVolumeRecord(now, history, inputType)
        case .bodyweight:
            result += bodyweightRepsRecord(now, past)
        case .assisted:
            result += assistanceRecord(now, past)
            result += assistedRepsRecord(now, past)
        case .duration:
            result += longestRecord(.longestDuration, now.map { Double($0.durationSeconds ?? 0) }, past.map { Double($0.durationSeconds ?? 0) }, 1)
        case .durationDistance:
            result += longestRecord(.longestDuration, now.map { Double($0.durationSeconds ?? 0) }, past.map { Double($0.durationSeconds ?? 0) }, 1)
            result += longestRecord(.longestDistance, now.map { $0.distanceMeters ?? 0 }, past.map { $0.distanceMeters ?? 0 }, 1)
        }
        return result.filter { kinds.contains($0.kind) }
    }

    /// Je li `new` dovoljno bolji od `old`: barem `minimumRelativeGain` i barem `minimumAbsolute`.
    public static func isSignificant(_ new: Double, over old: Double, minimumAbsolute: Double) -> Bool {
        guard old > 0 else { return false }
        return new >= old * (1 + minimumRelativeGain) - epsilon && new - old >= minimumAbsolute - epsilon
    }

    /// Sažima serije na one koje mogu odlučiti o rekordu, za bilo koju vrstu unosa: Pareto granicu
    /// (opterećenje, ponavljanja) za težinu i dodatnu težinu u oba smjera te seriju s najvećom procjenom 1RM,
    /// volumenom, trajanjem i udaljenošću. Rekordi sa sažetim serijama isti su kao s punima,
    /// pa statistika ne mora za svaki trening ponovno prolaziti cijelu raniju povijest.
    public static func condensed(_ sets: [SetValues]) -> [SetValues] {
        let sets = sets.filter { $0.kind == .working }
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
        for type in [ExerciseInputType.weightReps, .weightedBodyweight] {
            measures.append { SetMetrics.strengthEstimate($0, inputType: type) ?? 0 }
        }
        measures.append { Double($0.durationSeconds ?? 0) }
        measures.append { $0.distanceMeters ?? 0 }
        for measure in measures {
            if let best = sets.indices.max(by: { measure(sets[$0]) < measure(sets[$1]) }) {
                keep.insert(best)
            }
        }
        return keep.sorted().map { sets[$0] }
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

    private static func bestOneRepMax(_ sets: [SetValues], _ type: ExerciseInputType) -> Double {
        sets.compactMap { SetMetrics.strengthEstimate($0, inputType: type) }.max() ?? 0
    }

    private static func oneRepMaxRecord(_ now: [SetValues], _ past: [SetValues], _ type: ExerciseInputType) -> [PersonalRecord] {
        let best = bestOneRepMax(now, type)
        let before = bestOneRepMax(past, type)
        guard isSignificant(best, over: before, minimumAbsolute: minimumLoadGainKg) else { return [] }
        return [PersonalRecord(kind: .estimatedOneRepMax, value: best, previousBest: before)]
    }

    /// Najveći teret među serijama s barem `reps` ponavljanja.
    private static func heaviest(_ sets: [SetValues], _ type: ExerciseInputType, reps: Int) -> Double {
        sets.filter { ($0.reps ?? 0) >= reps }.compactMap { SetMetrics.load($0, inputType: type) }.max() ?? 0
    }

    /// Jedan rekord po rasponu ponavljanja: najviši raspon u kojem je ovaj trening nadmašio raniji najbolji.
    private static func repMaxRecord(_ now: [SetValues], _ past: [SetValues], _ type: ExerciseInputType) -> [PersonalRecord] {
        for reps in repRanges.reversed() {
            let best = heaviest(now, type, reps: reps)
            let before = heaviest(past, type, reps: reps)
            if isSignificant(best, over: before, minimumAbsolute: minimumLoadGainKg) {
                return [PersonalRecord(kind: .repMax, value: best, previousBest: before, reps: reps)]
            }
        }
        return []
    }

    private static func weightRecord(_ now: [SetValues], _ past: [SetValues], _ type: ExerciseInputType) -> [PersonalRecord] {
        let best = heaviest(now, type, reps: 1)
        let before = heaviest(past, type, reps: 1)
        guard isSignificant(best, over: before, minimumAbsolute: minimumLoadGainKg) else { return [] }
        // Teža serija s manje ponavljanja nije nužno napredak: u sažetak ide samo uz blizu najbolju procjenu 1RM.
        let strength = bestOneRepMax(now, type)
        let bestStrength = bestOneRepMax(past, type)
        let shows = bestStrength <= 0 || strength >= bestStrength * milestoneTolerance
        return [PersonalRecord(kind: .maxWeight, value: best, previousBest: before, showsInSummary: shows)]
    }

    private static func exerciseVolumeRecord(_ now: [SetValues], _ history: RecordHistory, _ type: ExerciseInputType) -> [PersonalRecord] {
        let total = now.reduce(0) { $0 + SetMetrics.volume($1, inputType: type) }
        let before = history.bestSessionVolume
        guard isSignificant(total, over: before, minimumAbsolute: 1) else { return [] }
        return [PersonalRecord(kind: .exerciseVolume, value: total, previousBest: before, showsInSummary: false)]
    }

    private static func bodyweightRepsRecord(_ now: [SetValues], _ past: [SetValues]) -> [PersonalRecord] {
        let best = now.map { $0.reps ?? 0 }.max() ?? 0
        let before = past.map { $0.reps ?? 0 }.max() ?? 0
        guard before > 0, best > before else { return [] }
        return [PersonalRecord(kind: .maxReps, value: Double(best), previousBest: Double(before))]
    }

    /// Ponavljanja uz istu ili manju pomoć od ranijih.
    private static func assistedRepsRecord(_ now: [SetValues], _ past: [SetValues]) -> [PersonalRecord] {
        var best: (reps: Int, previous: Int)?
        for set in now {
            let reps = set.reps ?? 0
            let help = set.extraWeightKg ?? 0
            guard reps >= 1 else { continue }
            let previous = past.filter { ($0.extraWeightKg ?? 0) <= help + epsilon }.map { $0.reps ?? 0 }.max() ?? 0
            if previous > 0, reps > previous, reps > (best?.reps ?? 0) {
                best = (reps, previous)
            }
        }
        guard let best else { return [] }
        return [PersonalRecord(kind: .maxReps, value: Double(best.reps), previousBest: Double(best.previous))]
    }

    private static func assistanceRecord(_ now: [SetValues], _ past: [SetValues]) -> [PersonalRecord] {
        let best = now.filter { ($0.reps ?? 0) >= 1 }.map { $0.extraWeightKg ?? 0 }.min()
        let before = past.filter { ($0.reps ?? 0) >= 1 }.map { $0.extraWeightKg ?? 0 }.min()
        guard let best, let before, best <= before - minimumLoadGainKg + epsilon else { return [] }
        return [PersonalRecord(kind: .lowestAssistance, value: best, previousBest: before)]
    }

    private static func longestRecord(_ kind: PRKind, _ now: [Double], _ past: [Double], _ minimum: Double) -> [PersonalRecord] {
        let best = now.max() ?? 0
        let before = past.max() ?? 0
        guard isSignificant(best, over: before, minimumAbsolute: minimum) else { return [] }
        return [PersonalRecord(kind: kind, value: best, previousBest: before)]
    }
}
