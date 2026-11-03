import Catalog
import Foundation
import Units

/// Polje serije koje se na satu mijenja Digital Crownom.
public enum WatchSetField: String, CaseIterable, Sendable {
    case weight
    case extraWeight
    case reps
    case duration
    case distance

    /// Polja koja vrsta unosa traži, redom kako se prikazuju (prvo težina ili trajanje).
    public static func fields(for inputType: ExerciseInputType) -> [WatchSetField] {
        switch inputType {
        case .weightReps: [.weight, .reps]
        case .weightedBodyweight, .assisted: [.extraWeight, .reps]
        case .bodyweight: [.reps]
        case .duration: [.duration]
        case .durationDistance: [.duration, .distance]
        }
    }

    /// Korak jednog "klika" krune, u jedinici prikaza.
    public func step(unit: WeightUnit) -> Double {
        switch self {
        case .weight, .extraWeight: unit == .kilograms ? 1.25 : 2.5
        case .reps: 1
        case .duration: 5
        case .distance: 50
        }
    }

    /// Raspon vrijednosti u jedinici prikaza.
    public func range(unit: WeightUnit) -> ClosedRange<Double> {
        switch self {
        case .weight, .extraWeight: 0...(unit == .kilograms ? 500 : 1100)
        case .reps: 0...200
        case .duration: 0...(4 * 3600)
        case .distance: 0...100_000
        }
    }

    /// Vrijednost iz serije u jedinici prikaza (težina u kg ili lbs, trajanje u sekundama, udaljenost u metrima).
    /// Prazno polje daje 0.
    public func value(in set: SetSnapshot, unit: WeightUnit) -> Double {
        switch self {
        case .weight: set.weightKg.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) } ?? 0
        case .extraWeight: set.extraWeightKg.map { WeightConversion.displayValue(fromKilograms: $0, in: unit) } ?? 0
        case .reps: Double(set.reps ?? 0)
        case .duration: Double(set.durationSeconds ?? 0)
        case .distance: set.distanceMeters ?? 0
        }
    }

    /// Upisuje vrijednost u jedinici prikaza u seriju (težina se sprema u kilogramima).
    /// Vrijednost se zaokružuje na korak polja i ograničava na raspon.
    public func apply(_ value: Double, to set: inout SetSnapshot, unit: WeightUnit) {
        let range = range(unit: unit)
        let step = step(unit: unit)
        let snapped = min(max((value / step).rounded() * step, range.lowerBound), range.upperBound)
        switch self {
        case .weight: set.weightKg = WeightConversion.kilograms(from: snapped, in: unit)
        case .extraWeight: set.extraWeightKg = WeightConversion.kilograms(from: snapped, in: unit)
        case .reps: set.reps = Int(snapped)
        case .duration: set.durationSeconds = Int(snapped)
        case .distance: set.distanceMeters = snapped
        }
    }

    /// Je li vrijednost u seriji već jednaka (u jedinici prikaza), da kruna ne bi bilježila promjenu bez promjene.
    public func matches(_ value: Double, in set: SetSnapshot, unit: WeightUnit) -> Bool {
        var copy = set
        apply(value, to: &copy, unit: unit)
        return abs(self.value(in: copy, unit: unit) - self.value(in: set, unit: unit)) < 1e-6
            && isFilled(in: set) == isFilled(in: copy)
    }

    private func isFilled(in set: SetSnapshot) -> Bool {
        switch self {
        case .weight: set.weightKg != nil
        case .extraWeight: set.extraWeightKg != nil
        case .reps: set.reps != nil
        case .duration: set.durationSeconds != nil
        case .distance: set.distanceMeters != nil
        }
    }

    /// Tekst vrijednosti za prikaz, npr. "82,5", "8", "1:30", "400".
    public func text(in set: SetSnapshot, unit: WeightUnit, locale: Locale = .current) -> String {
        switch self {
        case .weight:
            guard let kilograms = set.weightKg else { return "–" }
            return WeightFormatter(unit: unit, locale: locale).number(fromKilograms: kilograms)
        case .extraWeight:
            guard let kilograms = set.extraWeightKg else { return "–" }
            return WeightFormatter(unit: unit, locale: locale).number(fromKilograms: kilograms)
        case .reps:
            return set.reps.map(String.init) ?? "–"
        case .duration:
            guard let seconds = set.durationSeconds else { return "–" }
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .distance:
            guard let meters = set.distanceMeters else { return "–" }
            return meters.formatted(.number.precision(.fractionLength(0)).locale(locale))
        }
    }
}
