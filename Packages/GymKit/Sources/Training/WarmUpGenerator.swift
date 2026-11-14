import Foundation
import Models
import Units

/// Serije zagrijavanja do radne težine: prazna šipka × 10, 40 % × 5, 60 % × 3 i 80 % × 1.
/// Težine se zaokružuju na korak težine (u jedinici prikaza, kao na kotačiću), a serija koja je jednaka
/// prethodnoj ili nije lakša od radne težine se preskače. Isto kao `WarmUpGenerator` na Androidu.
public enum WarmUpGenerator {

    /// Udio radne težine i ponavljanja nakon prazne šipke.
    static let ramp: [(fraction: Double, reps: Int)] = [(0.4, 5), (0.6, 3), (0.8, 1)]

    /// `barKg` je težina šipke za vježbe sa šipkom, nil za ostale (tada nema serije s praznom šipkom).
    public static func sets(workingWeightKg: Double, barKg: Double?, step: Double, unit: WeightUnit) -> [SetValues] {
        guard workingWeightKg > 0 else { return [] }
        let tolerance = 1e-6
        var result: [SetValues] = []
        var last = 0.0
        if let barKg, barKg > 0, barKg < workingWeightKg - tolerance {
            result.append(SetValues(kind: .warmUp, weightKg: barKg, reps: 10))
            last = barKg
        }
        for item in ramp {
            let weight = rounded(workingWeightKg * item.fraction, step: step, unit: unit)
            guard weight > last + tolerance, weight < workingWeightKg - tolerance else { continue }
            result.append(SetValues(kind: .warmUp, weightKg: weight, reps: item.reps))
            last = weight
        }
        return result
    }

    /// Najbliža težina na koraku, u kilogramima.
    static func rounded(_ kilograms: Double, step: Double, unit: WeightUnit) -> Double {
        guard step > 0 else { return kilograms }
        let display = WeightConversion.value(fromKilograms: kilograms, in: unit)
        let moved = ((display / step).rounded() * step * 1_000_000).rounded() / 1_000_000
        return WeightConversion.kilograms(from: moved, in: unit)
    }
}

extension WorkoutEngine {

    /// Dodaje zagrijavanje do težine prve radne serije, ispred prve neodrađene serije. Samo za vježbe s
    /// težinom i ponavljanjima, bez postojećeg zagrijavanja i s upisanom težinom radne serije.
    /// Vraća broj dodanih serija.
    @discardableResult
    public func addWarmUps(
        to exercise: SessionExercise, barKg: Double?, step: Double, unit: WeightUnit, now: Date = Date()
    ) throws -> Int {
        guard canAddWarmUps(to: exercise) else { return 0 }
        let sets = exercise.orderedSets
        guard let weight = sets.first(where: { $0.kind == .working && !$0.isCompleted })?.weightKg
            ?? sets.first(where: { $0.kind == .working })?.weightKg else { return 0 }
        let planned = WarmUpGenerator.sets(workingWeightKg: weight, barKg: barKg, step: step, unit: unit)
        guard !planned.isEmpty else { return 0 }
        var ordered = sets
        let insertIndex = ordered.firstIndex { !$0.isCompleted } ?? ordered.count
        for (offset, values) in planned.enumerated() {
            let set = SetLog(orderIndex: insertIndex + offset, kind: .warmUp)
            context.insert(set)
            set.exercise = exercise
            set.weightKg = values.weightKg
            set.reps = values.reps
            ordered.insert(set, at: insertIndex + offset)
        }
        for (index, item) in ordered.enumerated() { item.orderIndex = index }
        if let session = exercise.session { try touch(session, now: now) }
        return planned.count
    }

    /// Nudi li se "Dodaj zagrijavanje": vježba s težinom, bez zagrijavanja i s upisanom težinom radne serije.
    public func canAddWarmUps(to exercise: SessionExercise) -> Bool {
        exercise.inputType == .weightReps
            && !exercise.orderedSets.contains { $0.kind == .warmUp }
            && exercise.orderedSets.contains { $0.kind == .working && ($0.weightKg ?? 0) > 0 }
    }
}
