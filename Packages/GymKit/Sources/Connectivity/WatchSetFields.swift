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

    /// Težina ili dodatna težina (korak ovisi o opremi vježbe).
    public var isWeight: Bool { self == .weight || self == .extraWeight }

    /// Korak jednog "klika" krune ili dodira na + i −, u jedinici prikaza. Za težinu je to korak vježbe
    /// (`WeightStepSettings`, isti kao na kotačiću na iPhoneu), a bez njega korak jedinice (`WheelOptions`).
    public func step(unit: WeightUnit, weightStep: Double? = nil) -> Double {
        switch self {
        case .weight, .extraWeight: weightStep.flatMap { $0 > 0 ? $0 : nil } ?? WheelOptions.weightStep(for: unit)
        case .reps: 1
        case .duration: 5
        case .distance: 50
        }
    }

    /// Vrijednost nakon `steps` koraka od `value`. Težina ide na sljedeću vrijednost na koraku, kao na
    /// kotačiću: 83 kg s korakom 2,5 ide na 85 ili 82,5, a ne na 85,5 ili 80,5.
    public func value(_ value: Double, movedBy steps: Int, step: Double) -> Double {
        guard isWeight, steps != 0, step > 0 else { return value + Double(steps) * step }
        let position = value / step
        let tolerance = 1e-6
        let target = steps > 0
            ? (position + tolerance).rounded(.down) + Double(steps)
            : (position - tolerance).rounded(.up) + Double(steps)
        return target * step
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

    /// Upisuje vrijednost u jedinici prikaza u seriju (težina se sprema u kilogramima) i ograničava je na raspon.
    /// Ponavljanja, trajanje i udaljenost zaokružuju se na korak polja. Težina se zaokružuje samo na 0,05
    /// (preciznost prikaza), ne na korak: težina upisana na iPhoneu izvan koraka (npr. 83 kg) ne smije se
    /// promijeniti sama. Kruna i gumbi + i − ionako daju vrijednosti na koraku.
    public func apply(_ value: Double, to set: inout SetSnapshot, unit: WeightUnit) {
        let range = range(unit: unit)
        let rounded = isWeight
            ? (value * Self.weightSubdivisions).rounded() / Self.weightSubdivisions
            : (value / step(unit: unit)).rounded() * step(unit: unit)
        let snapped = min(max(rounded, range.lowerBound), range.upperBound)
        switch self {
        case .weight: set.weightKg = WeightConversion.kilograms(from: snapped, in: unit)
        case .extraWeight: set.extraWeightKg = WeightConversion.kilograms(from: snapped, in: unit)
        case .reps: set.reps = Int(snapped)
        case .duration: set.durationSeconds = Int(snapped)
        case .distance: set.distanceMeters = snapped
        }
    }

    /// Težina se zaokružuje na 1/20 (0,05), kao prikaz u `WeightConversion.displayValue`. Dijeli se s 20,
    /// a ne množi s 0,05, da 81,25 ostane točno 81,25.
    static let weightSubdivisions = 20.0

    /// Je li vrijednost u seriji već jednaka (u jedinici prikaza), da kruna ne bi bilježila promjenu bez promjene.
    public func matches(_ value: Double, in set: SetSnapshot, unit: WeightUnit) -> Bool {
        var copy = set
        apply(value, to: &copy, unit: unit)
        return abs(self.value(in: copy, unit: unit) - self.value(in: set, unit: unit)) < 1e-6
            && isFilled(in: set) == isFilled(in: copy)
    }

    /// Je li polje upisano (prazno se prikazuje kao "–").
    func isFilled(in set: SetSnapshot) -> Bool {
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
