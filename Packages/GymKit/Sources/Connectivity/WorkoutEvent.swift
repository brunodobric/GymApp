import Foundation
import Models

/// Događaj koji se tijekom treninga razmjenjuje između iPhonea i Watcha
/// preko WatchConnectivityja (specifikacija, odjeljak 6).
///
/// Svaki događaj ima UUID i vrijeme nastanka, pa primatelj može prepoznati
/// duplikate (isti događaj stigne i preko `sendMessage` i preko `transferUserInfo`)
/// i riješiti sukob zadnjom promjenom.
public struct WorkoutEvent: Codable, Sendable, Equatable, Identifiable {

    public enum Kind: Codable, Sendable, Equatable {
        /// Cijelo stanje treninga s uređaja koji ga vodi.
        case snapshot(SessionSnapshot)
        /// Izmjene s uređaja koji trening zrcali, za uređaj koji ga vodi.
        case commands([WorkoutCommand])
    }

    public let id: UUID
    public let sessionID: UUID?
    public let createdAt: Date
    public let origin: DeviceRole
    public let kind: Kind

    public init(id: UUID = UUID(), sessionID: UUID? = nil, createdAt: Date = Date(), origin: DeviceRole, kind: Kind) {
        self.id = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.origin = origin
        self.kind = kind
    }
}

// MARK: - Pakiranje za WatchConnectivity

public enum WorkoutEventCodingError: Error, Equatable {
    case missingPayload
}

enum ConnectivityCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

extension WorkoutEvent {
    /// Ključ pod kojim se događaj šalje u WatchConnectivity rječniku.
    public static let payloadKey = "workoutEvent"

    /// Rječnik spreman za `sendMessage` ili `transferUserInfo`.
    /// Sadrži samo `Data`, što WatchConnectivity podržava (property list).
    public func payload() throws -> [String: Any] {
        [Self.payloadKey: try ConnectivityCoding.makeEncoder().encode(self)]
    }

    public init(payload: [String: Any]) throws {
        guard let data = payload[Self.payloadKey] as? Data else {
            throw WorkoutEventCodingError.missingPayload
        }
        self = try ConnectivityCoding.makeDecoder().decode(WorkoutEvent.self, from: data)
    }
}

/// Pamti već obrađene događaje i propušta svaki samo jednom.
public struct WorkoutEventDeduplicator: Sendable {
    private var seen: Set<UUID> = []

    public init() {}

    /// `true` ako je događaj nov i treba ga obraditi.
    public mutating func accept(_ event: WorkoutEvent) -> Bool {
        seen.insert(event.id).inserted
    }
}
