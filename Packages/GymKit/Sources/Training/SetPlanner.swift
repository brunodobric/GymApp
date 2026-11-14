import Catalog
import Foundation
import Models
import Units

/// Cilj serije iz predloška (`TemplateSet`) bez veze s bazom.
public struct SetTarget: Equatable, Sendable {
    public var kind: SetKind
    public var weightKg: Double?
    public var reps: Int?
    /// Gornja granica raspona ponavljanja (dvostruka progresija, npr. 8–12). Nil znači fiksni cilj `reps`.
    public var repsMax: Int?

    public init(kind: SetKind, weightKg: Double? = nil, reps: Int? = nil, repsMax: Int? = nil) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.repsMax = repsMax
    }

    /// Gornja granica cilja: kraj raspona, inače sam cilj.
    var upperReps: Int? {
        guard let reps else { return nil }
        guard let repsMax, repsMax > reps else { return reps }
        return repsMax
    }
}

extension TemplateSet {
    public var target: SetTarget {
        SetTarget(kind: kind, weightKg: targetWeightKg, reps: targetReps, repsMax: targetRepsMax)
    }
}

/// Raspon ponavljanja radnih serija (npr. 8–12). Kod fiksnog cilja su granice iste.
public struct RepRange: Equatable, Sendable {
    public var lower: Int
    public var upper: Int

    public init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = max(lower, upper)
    }
}

/// Serije nove vježbe u treningu, s prijedlogom veće težine.
public struct SetPlan: Equatable, Sendable {
    public var sets: [SetValues]
    /// Promjena tereta radnih serija prema prošlom izvođenju, u kilogramima (dvostruka progresija):
    /// pozitivna je veća težina ili dodatni teret, negativna manja pomoć. Nil kad se teret ne mijenja.
    public var loadChangeKg: Double?
    /// Raspon ponavljanja radnih serija iz predloška, nil bez cilja ponavljanja.
    public var repRange: RepRange?

    public init(sets: [SetValues], loadChangeKg: Double? = nil, repRange: RepRange? = nil) {
        self.sets = sets
        self.loadChangeKg = loadChangeKg
        self.repRange = repRange
    }
}

/// Slaže serije vježbe koja se dodaje u trening: `WorkoutEngine.addExercise`, `TemplateStarter`,
/// plan treninga za sat i widgete. Jedno mjesto za pravila, da iPhone, sat i Android pretpopune isto.
///
/// * Bez ciljeva: onoliko zagrijavanja koliko je bilo prošli put, a radnih serija koliko ih je bilo
///   najčešće u zadnja tri izvođenja (jedan prekinut trening ne smanjuje plan), inače tri.
/// * Vrijednosti dolaze iz zadnjeg izvođenja po poziciji serije (`SmartDefaults`).
/// * Težina uvijek dolazi iz prošlog puta. Cilj težine iz predloška je samo početna vrijednost dok vježba
///   nema prošlih serija te vrste, inače bi zastarjela težina iz predloška zauvijek nadjačala napredak.
/// * Raspon ponavljanja (8–12) zadržava prošla ponavljanja unutar raspona, a fiksni cilj ih upisuje.
/// * Dvostruka progresija: kad su prošli put sve radne serije dosegle gornju granicu raspona, teret ide
///   jedan korak gore (potpomognuta vježba: pomoć jedan korak dolje), a ponavljanja na donju granicu.
public enum SetPlanner {

    public static func plan(
        previous: [SetValues],
        recentWorkingCounts: [Int] = [],
        targets: [SetTarget] = [],
        inputType: ExerciseInputType,
        weightStep: Double? = nil,
        unit: WeightUnit = .kilograms
    ) -> SetPlan {
        let kinds: [SetKind]
        if targets.isEmpty {
            let warmUps = previous.filter { $0.kind == .warmUp }.count
            let lastWorking = previous.filter { $0.kind == .working }.count
            let working = SmartDefaults.workingSetCount(recent: recentWorkingCounts)
                ?? (lastWorking > 0 ? lastWorking : WorkoutEngine.defaultWorkingSets)
            kinds = Array(repeating: .warmUp, count: warmUps) + Array(repeating: .working, count: working)
        } else {
            kinds = targets.map(\.kind)
        }

        var sets: [SetValues] = []
        for (index, kind) in kinds.enumerated() {
            let position = sets.filter { $0.kind == kind }.count
            var values = SmartDefaults.defaults(forPosition: position, kind: kind, previous: previous)
                ?? sets.last(where: { $0.kind == kind }).flatMap {
                    SmartDefaults.defaults(forPosition: 0, kind: kind, previous: [$0])
                }
                ?? SetValues(kind: kind)
            if index < targets.count {
                let hasHistory = previous.contains { $0.kind == kind }
                apply(targets[index], to: &values, inputType: inputType, weight: !hasHistory)
            }
            sets.append(values)
        }

        var plan = SetPlan(sets: sets, repRange: repRange(of: targets, inputType: inputType))
        if let weightStep, weightStep > 0,
           shouldIncreaseLoad(targets: targets, previous: previous, inputType: inputType) {
            plan.loadChangeKg = increaseLoad(of: &plan.sets, targets: targets, inputType: inputType, step: weightStep, unit: unit)
        }
        return plan
    }

    /// Raspon ponavljanja prve radne serije s ciljem ponavljanja.
    public static func repRange(of targets: [SetTarget], inputType: ExerciseInputType) -> RepRange? {
        guard inputType.hasReps,
              let first = targets.first(where: { $0.kind == .working && $0.reps != nil }),
              let lower = first.reps, let upper = first.upperReps else { return nil }
        return RepRange(lower: lower, upper: upper)
    }

    /// Jesu li prošli put sve planirane radne serije dosegle gornju granicu cilja ponavljanja.
    public static func shouldIncreaseLoad(targets: [SetTarget], previous: [SetValues], inputType: ExerciseInputType) -> Bool {
        guard inputType.progressesByLoad else { return false }
        let working = targets.filter { $0.kind == .working }
        guard !working.isEmpty, working.allSatisfy({ $0.reps != nil }) else { return false }
        let done = previous.filter { $0.kind == .working }
        guard done.count >= working.count else { return false }
        return zip(working, done).allSatisfy { target, set in
            guard let upper = target.upperReps, let reps = set.reps else { return false }
            return reps >= upper
        }
    }

    /// Pomiče teret radnih serija za jedan korak i vraća promjenu prve pomaknute serije u kilogramima.
    private static func increaseLoad(
        of sets: inout [SetValues], targets: [SetTarget], inputType: ExerciseInputType, step: Double, unit: WeightUnit
    ) -> Double? {
        var change: Double?
        for index in sets.indices where sets[index].kind == .working {
            let reps = index < targets.count ? targets[index].reps : nil
            switch inputType {
            case .weightReps:
                guard let weight = sets[index].weightKg, weight > 0 else { continue }
                let moved = stepped(weight, by: 1, step: step, unit: unit)
                sets[index].weightKg = moved
                change = change ?? moved - weight
            case .weightedBodyweight:
                let extra = sets[index].extraWeightKg ?? 0
                let moved = stepped(extra, by: 1, step: step, unit: unit)
                sets[index].extraWeightKg = moved
                change = change ?? moved - extra
            case .assisted:
                guard let help = sets[index].extraWeightKg, help > 0 else { continue }
                let moved = stepped(help, by: -1, step: step, unit: unit)
                sets[index].extraWeightKg = moved
                change = change ?? moved - help
            case .bodyweight, .duration, .durationDistance:
                continue
            }
            if let reps { sets[index].reps = reps }
        }
        guard let change, abs(change) > 0.0001 else { return nil }
        return change
    }

    /// Težina nakon `steps` koraka, na sljedećoj vrijednosti na koraku (83 kg s korakom 2,5 ide na 85).
    /// Korak je u jedinici prikaza, kao na kotačiću i na satu.
    public static func stepped(_ kilograms: Double, by steps: Int, step: Double, unit: WeightUnit) -> Double {
        guard step > 0, steps != 0 else { return kilograms }
        let display = WeightConversion.value(fromKilograms: kilograms, in: unit)
        let position = display / step
        let tolerance = 1e-6
        let target = steps > 0
            ? (position + tolerance).rounded(.down) + Double(steps)
            : (position - tolerance).rounded(.up) + Double(steps)
        let moved = (max(0, target * step) * 1_000_000).rounded() / 1_000_000
        return WeightConversion.kilograms(from: moved, in: unit)
    }

    /// Upisuje ciljeve serije. Cilj težine samo kad je `weight` (vježba bez povijesti).
    private static func apply(_ target: SetTarget, to values: inout SetValues, inputType: ExerciseInputType, weight useWeight: Bool) {
        if useWeight, let weight = target.weightKg {
            switch inputType {
            case .weightReps: values.weightKg = weight
            case .weightedBodyweight, .assisted: values.extraWeightKg = weight
            case .bodyweight, .duration, .durationDistance: break
            }
        }
        guard inputType.hasReps, let reps = target.reps else { return }
        if target.kind == .working, let upper = target.upperReps, upper > reps {
            values.reps = min(max(values.reps ?? reps, reps), upper)
        } else {
            values.reps = reps
        }
    }
}

extension ExerciseInputType {
    /// Vrsta unosa s ponavljanjima.
    public var hasReps: Bool {
        switch self {
        case .weightReps, .bodyweight, .weightedBodyweight, .assisted: true
        case .duration, .durationDistance: false
        }
    }

    /// Vrsta unosa kod koje se napreduje teretom (težina, dodatni teret ili manja pomoć).
    public var progressesByLoad: Bool {
        switch self {
        case .weightReps, .weightedBodyweight, .assisted: true
        case .bodyweight, .duration, .durationDistance: false
        }
    }
}
