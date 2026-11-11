import Foundation

/// Najmanji CSV (RFC 4180): polja s zarezom, navodnicima ili novim retkom stavljaju se u navodnike.
enum CSV {
    static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Čita cijeli tekst u retke polja. Prazni završni redak se ignorira.
    /// `separator` je zarez za vlastiti CSV, a točka-zarez za izvoze nekih drugih aplikacija.
    static func parse(_ text: String, separator: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending = iterator.next()
        var hasContent = false

        func endRow() {
            row.append(field)
            field = ""
            if hasContent || row.count > 1 || !row[0].isEmpty { rows.append(row) }
            row = []
            hasContent = false
        }

        while let character = pending {
            pending = iterator.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
                hasContent = true
            case separator:
                row.append(field)
                field = ""
                hasContent = true
            case "\n", "\r\n", "\r":
                endRow()
            default:
                field.append(character)
            }
        }
        if hasContent || !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

/// Tekst uvezene datoteke iz bajtova.
public enum ImportText {
    /// UTF-8, ili UTF-16 kad datoteka počinje njegovim BOM-om (neke aplikacije i Excel tako izvoze CSV).
    /// BOM se uklanja, da prvi naziv stupca ostane ispravan.
    public static func decode(_ data: Data) -> String {
        var text: String
        if data.starts(with: [0xFF, 0xFE]) {
            text = String(data: data, encoding: .utf16LittleEndian) ?? ""
        } else if data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16BigEndian) ?? ""
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        return text
    }
}

/// Datumi u CSV-u: ISO 8601 s milisekundama (UTC), pa su čitljivi i vraćaju se bez gubitka u milisekundi.
enum CSVDate {
    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    static func string(_ date: Date?) -> String {
        date.map { formatter().string(from: $0) } ?? ""
    }

    static func parse(_ text: String) -> Date? {
        text.isEmpty ? nil : formatter().date(from: text)
    }
}
