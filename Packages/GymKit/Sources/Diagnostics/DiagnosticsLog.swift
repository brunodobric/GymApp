import Foundation

/// Jedan izvještaj iz MetricKita: dnevne metrike (pokretanje, memorija, potrošnja) ili
/// dijagnostika (rušenje, zastoj, prekomjerni CPU ili pisanje na disk).
public struct DiagnosticEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case metrics
        case diagnostics
    }

    public var id: UUID
    /// Kad je izvještaj stigao na uređaj.
    public var receivedAt: Date
    public var kind: Kind
    /// Razdoblje koje izvještaj pokriva, ako ga MetricKit navodi.
    public var periodStart: Date?
    public var periodEnd: Date?
    /// Broj dijagnostika po vrsti, npr. ["crash": 1, "hang": 2]. Za metrike je prazno.
    public var counts: [String: Int]
    /// Izvorni JSON iz MetricKita (`jsonRepresentation()`), za izvoz i Xcode.
    public var payload: String

    public init(
        id: UUID = UUID(), receivedAt: Date, kind: Kind, periodStart: Date? = nil, periodEnd: Date? = nil,
        counts: [String: Int] = [:], payload: String
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.kind = kind
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.counts = counts
        self.payload = payload
    }

    fileprivate var dedupeKey: String { kind.rawValue + "|" + payload }

    /// Ukupan broj dijagnostika u izvještaju.
    public var totalCount: Int { counts.values.reduce(0, +) }
}

/// Lokalni dnevnik MetricKit izvještaja. Ostaje na uređaju: ništa se ne šalje automatski,
/// a korisnik ga može sam izvesti i podijeliti (npr. uz prijavu greške).
public struct DiagnosticsLog: Codable, Equatable, Sendable {
    /// Koliko se izvještaja najviše čuva.
    public static let maxEntries = 30
    /// Koliko dugo se izvještaj čuva.
    public static let maxAge: TimeInterval = 90 * 24 * 60 * 60

    /// Izvještaji, najnoviji prvi.
    public private(set) var entries: [DiagnosticEntry]

    public init() {
        entries = []
    }

    /// Dodaje izvještaje i reže dnevnik na zadnjih `maxEntries` mlađih od `maxAge`.
    /// Izvještaj koji je već u dnevniku (ista vrsta i isti JSON) ne dodaje se ponovno, jer MetricKit
    /// kod svakog pokretanja može ponovno vratiti nedavne izvještaje.
    public mutating func append(_ new: [DiagnosticEntry], now: Date) {
        var known = Set(entries.map(\.dedupeKey))
        var merged = entries
        for entry in new where known.insert(entry.dedupeKey).inserted {
            merged.append(entry)
        }
        entries = merged
            .filter { now.timeIntervalSince($0.receivedAt) <= Self.maxAge }
            .sorted { $0.receivedAt > $1.receivedAt }
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }

    public mutating func removeAll() {
        entries = []
    }

    /// Zbroj dijagnostika po vrsti kroz cijeli dnevnik.
    public var totals: [String: Int] {
        entries.reduce(into: [:]) { result, entry in
            for (key, value) in entry.counts { result[key, default: 0] += value }
        }
    }

    // MARK: Spremanje i izvoz

    public static func decode(_ data: Data) throws -> DiagnosticsLog {
        try JSONDecoder.diagnostics.decode(DiagnosticsLog.self, from: data)
    }

    public func encoded() throws -> Data {
        try JSONEncoder.diagnostics.encode(self)
    }

    /// Datoteka za dijeljenje: popis izvještaja s izvornim MetricKit JSON-om, čitljiv u uređivaču teksta.
    public func exportData() throws -> Data {
        let items: [[String: Any]] = entries.map { entry in
            var item: [String: Any] = [
                "receivedAt": ISO8601DateFormatter().string(from: entry.receivedAt),
                "kind": entry.kind.rawValue,
                "counts": entry.counts,
            ]
            // Izvorni JSON ide kao objekt, ne kao string s escapeanim navodnicima.
            if let data = entry.payload.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                item["payload"] = object
            } else {
                item["payload"] = entry.payload
            }
            return item
        }
        return try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }
}

/// Čitanje JSON-a koji MetricKit daje kroz `jsonRepresentation()`.
public enum MetricKitPayload {
    /// Broj dijagnostika po vrsti. MetricKit ih daje kao nizove pod ključevima
    /// `crashDiagnostics`, `hangDiagnostics`, `cpuExceptionDiagnostics`, `diskWriteExceptionDiagnostics`
    /// i `appLaunchDiagnostics`. Ključ u rezultatu je naziv bez nastavka: "crash", "hang"…
    public static func diagnosticCounts(from json: Data) -> [String: Int] {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [:] }
        var counts: [String: Int] = [:]
        for (key, value) in object where key.hasSuffix("Diagnostics") {
            guard let list = value as? [Any], !list.isEmpty else { continue }
            counts[String(key.dropLast("Diagnostics".count)), default: 0] += list.count
        }
        return counts
    }

    /// Početak i kraj razdoblja (`timeStampBegin`, `timeStampEnd`), ako su u JSON-u.
    public static func period(from json: Data) -> (start: Date?, end: Date?) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return (nil, nil) }
        return (date(object["timeStampBegin"]), date(object["timeStampEnd"]))
    }

    /// MetricKit datume piše kao "2026-11-03 00:00:00 +0000".
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

private extension JSONEncoder {
    static var diagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var diagnostics: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
