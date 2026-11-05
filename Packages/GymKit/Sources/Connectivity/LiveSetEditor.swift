import Catalog
import Foundation
import Models
import Training
import Units

/// Jedna vrijednost sljedeće serije u Live Activityju, s gumbima − i + (specifikacija, odjeljak 6).
public struct LiveSetValue: Equatable, Sendable {
    public var field: WatchSetField
    /// Broj bez jedinice, npr. "82,5", "8", "1:30", "400". "–" kad vrijednost nije upisana.
    public var text: String
    /// Jedinica za prikaz uz broj ("kg", "lbs", "m"). Prazno za ponavljanja i trajanje.
    public var unitSymbol: String
    public var canDecrease: Bool
    public var canIncrease: Bool
}

/// Prikaz i promjena vrijednosti sljedeće serije iz Live Activityja.
///
/// Polja, koraci i rasponi isti su kao za Digital Crown na satu (`WatchSetField`), pa jedan dodir na + ili −
/// mijenja vrijednost kao jedan klik krune: 1,25 kg (2,5 lbs), 1 ponavljanje, 5 sekundi ili 50 metara.
public enum LiveSetEditor {

    /// Vrijednosti serije redom kako se prikazuju (prvo težina ili trajanje).
    public static func values(
        of set: SetLog,
        inputType: ExerciseInputType,
        unit: WeightUnit,
        locale: Locale = .current
    ) -> [LiveSetValue] {
        let snapshot = makeSnapshot(of: set)
        return WatchSetField.fields(for: inputType).map { field in
            let range = field.range(unit: unit)
            let value = field.value(in: snapshot, unit: unit)
            return LiveSetValue(
                field: field,
                text: field.text(in: snapshot, unit: unit, locale: locale),
                unitSymbol: unitSymbol(of: field, unit: unit),
                canDecrease: field.isFilled(in: snapshot) && value > range.lowerBound,
                canIncrease: value < range.upperBound
            )
        }
    }

    /// Mijenja polje serije za `steps` koraka (+1 ili −1). Težina se sprema u kilogramima.
    /// Prazno polje kreće od nule i ne smanjuje se. Vraća `false` kad se vrijednost nije promijenila (npr. na rubu raspona).
    @discardableResult
    public static func adjust(_ set: SetLog, field: WatchSetField, steps: Int, unit: WeightUnit) -> Bool {
        var snapshot = makeSnapshot(of: set)
        guard steps > 0 || field.isFilled(in: snapshot) else { return false }
        let target = field.value(in: snapshot, unit: unit) + Double(steps) * field.step(unit: unit)
        guard !field.matches(target, in: snapshot, unit: unit) else { return false }
        field.apply(target, to: &snapshot, unit: unit)
        set.weightKg = snapshot.weightKg
        set.reps = snapshot.reps
        set.extraWeightKg = snapshot.extraWeightKg
        set.durationSeconds = snapshot.durationSeconds
        set.distanceMeters = snapshot.distanceMeters
        return true
    }

    /// Vrijednosti iste serije u prethodnom treningu u dva reda: težina (ili trajanje) gore, ponavljanja
    /// (ili udaljenost) dolje, npr. "30 kg\n12 ×", "12 ×" ili "1:30\n400 m".
    /// Serija se uspoređuje po poziciji među serijama iste vrste (kao smart defaults). `nil` kad prošli put nema.
    public static func previousText(
        of set: SetLog,
        inputType: ExerciseInputType,
        previous: [SetValues],
        unit: WeightUnit,
        locale: Locale = .current
    ) -> String? {
        let sameKind = set.exercise?.orderedSets.filter { $0.kind == set.kind } ?? [set]
        let position = sameKind.firstIndex { $0.id == set.id } ?? 0
        guard let old = SmartDefaults.defaults(forPosition: position, kind: set.kind, previous: previous) else { return nil }
        let weight = WeightFormatter(unit: unit, locale: locale)
        switch inputType {
        case .weightReps:
            guard let kilograms = old.weightKg, let reps = old.reps else { return nil }
            return "\(weight.string(fromKilograms: kilograms))\n\(reps) ×"
        case .bodyweight:
            return old.reps.map { "\($0) ×" }
        case .weightedBodyweight, .assisted:
            guard let reps = old.reps else { return nil }
            return "\(weight.string(fromKilograms: old.extraWeightKg ?? 0))\n\(reps) ×"
        case .duration:
            return old.durationSeconds.map(durationText)
        case .durationDistance:
            let parts = [
                old.durationSeconds.map(durationText),
                old.distanceMeters.map { "\($0.formatted(.number.precision(.fractionLength(0)).locale(locale))) m" },
            ]
            let text = parts.compactMap { $0 }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
    }

    private static func durationText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func unitSymbol(of field: WatchSetField, unit: WeightUnit) -> String {
        switch field {
        case .weight, .extraWeight: unit.symbol
        case .distance: "m"
        case .reps, .duration: ""
        }
    }

    private static func makeSnapshot(of set: SetLog) -> SetSnapshot {
        SetSnapshot(
            id: set.id, orderIndex: set.orderIndex, kind: set.kind, weightKg: set.weightKg, reps: set.reps,
            extraWeightKg: set.extraWeightKg, durationSeconds: set.durationSeconds,
            distanceMeters: set.distanceMeters, rpe: set.rpe, completedAt: set.completedAt
        )
    }
}
