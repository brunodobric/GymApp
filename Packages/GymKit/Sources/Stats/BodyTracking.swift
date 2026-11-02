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

    /// Povijest jedne mjere, od najstarije. Za vlastitu mjeru se razlikuje po nazivu.
    public func measurements(of kind: BodyMeasurementKind, customName: String? = nil) throws -> [BodyMeasurement] {
        let raw = kind.rawValue
        let found = try context.fetch(FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.date)]
        ))
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

    /// Nazivi vlastitih mjera koje korisnik prati.
    public func customNames() throws -> [String] {
        let all = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let names = all.filter { $0.kind == .custom }.compactMap(\.customName).filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    public func delete(_ measurement: BodyMeasurement) throws {
        context.delete(measurement)
        try context.save()
    }
}
