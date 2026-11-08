import Foundation
import Models
import SwiftData

public enum BodyTrackingError: Error, Equatable {
    case invalidValue
}

/// Praćenje tijela: mjere se spremaju u metričkim jedinicama (kg za težinu, cm za ostalo).
public struct BodyTracking {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func add(
        _ kind: BodyMeasurementKind, value: Double, date: Date = Date(), customName: String? = nil,
        source: MeasurementSource = .manual
    ) throws -> BodyMeasurement {
        guard value.isFinite, value > 0 else { throw BodyTrackingError.invalidValue }
        let measurement = BodyMeasurement(kind: kind, value: value, date: date, source: source)
        if kind == .custom { measurement.customName = customName?.trimmingCharacters(in: .whitespaces) }
        context.insert(measurement)
        try context.save()
        return measurement
    }

    /// Tjelesna težina (kg) koju se prihvaća iz Prečaca i Sirija. Broj izvan raspona je gotovo sigurno krivo
    /// izgovoren ili upisan (npr. 8 umjesto 80), pa se ne sprema.
    public static let shortcutWeightRange: ClosedRange<Double> = 20...400

    /// Tjelesna težina iz Prečaca ili Sirija, u kg (pretvorbu iz lbs radi intent).
    @discardableResult
    public func addShortcutWeight(kilograms: Double, date: Date = Date()) throws -> BodyMeasurement {
        guard kilograms.isFinite, Self.shortcutWeightRange.contains(kilograms) else { throw BodyTrackingError.invalidValue }
        return try add(.weight, value: kilograms, date: date)
    }

    /// Povijest jedne mjere, od najstarije, s mjerenjima iz Zdravlja. Za vlastitu mjeru se razlikuje po nazivu.
    public func measurements(of kind: BodyMeasurementKind, customName: String? = nil) throws -> [BodyMeasurement] {
        let raw = kind.rawValue
        let manual = try context.fetch(FetchDescriptor<BodyMeasurement>(predicate: #Predicate { $0.kindRaw == raw }))
        let health = try context.fetch(FetchDescriptor<HealthMeasurement>(predicate: #Predicate { $0.kindRaw == raw }))
        let found = BodyMeasurement.merged(manual, health: health)
        guard kind == .custom else { return found }
        return found.filter { $0.customName == customName }
    }

    public func latest(of kind: BodyMeasurementKind, customName: String? = nil) throws -> BodyMeasurement? {
        try measurements(of: kind, customName: customName).last
    }

    /// Razlika između zadnje i prve vrijednosti; nil kad ima manje od dva unosa.
    public func change(of kind: BodyMeasurementKind, customName: String? = nil) throws -> Double? {
        let list = try measurements(of: kind, customName: customName)
        guard let first = list.first, let last = list.last, list.count >= 2 else { return nil }
        return last.value - first.value
    }

    /// Promjena zadnje vrijednosti u zadnjih `days` dana: prema zadnjem mjerenju starom barem `days` dana
    /// (gledano od zadnjeg), a bez njega prema prvom mjerenju. Nil kad ima manje od dva unosa.
    public func recentChange(of kind: BodyMeasurementKind, days: Int = 30) throws -> Double? {
        Self.recentChange(in: try measurements(of: kind), days: days)
    }

    /// `measurements` od najstarijeg prema najnovijem.
    static func recentChange(in measurements: [BodyMeasurement], days: Int) -> Double? {
        guard measurements.count >= 2, let last = measurements.last else { return nil }
        let limit = last.date.addingTimeInterval(-Double(days) * 86_400)
        let reference = measurements.last { $0.date <= limit } ?? measurements[0]
        return last.value - reference.value
    }

    /// Nazivi vlastitih mjera koje korisnik prati.
    public func customNames() throws -> [String] {
        let all = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let names = all.filter { $0.kind == .custom }.compactMap(\.customName).filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    /// Mjerenje iz Zdravlja briše se iz lokalne baze (u Zdravlju ostaje).
    public func delete(_ measurement: BodyMeasurement) throws {
        if measurement.source == .healthKit, try HealthLocalStore(context: context).measurement(id: measurement.id) != nil {
            try HealthLocalStore(context: context).deleteMeasurement(id: measurement.id)
            return
        }
        context.delete(measurement)
        try context.save()
    }
}
