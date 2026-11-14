import Foundation
import Units

/// Čitanje CSV izvoza treninga iz druge aplikacije. Ne ovisi o bazi, pa se može testirati samostalno.
///
/// Format (točka-zarez kao razdjelnik, prazan redak između treninga):
///
///     "Push · Day 1 · Week 9 · Gym 2.0";"2026-11-02 4:27 pm";"53 min"
///     "1. Incline Bench Press · Dumbbells · 10 reps"
///     #;KG;REPS
///     1;24;10
///     2;+12.5;10        (vlastita težina + 12,5 kg)
///     3;-;-             (prazna serija)
///     "2. Plank · Bodyweight"
///     #;MINS
///     1;1
///
/// Izvoz iste aplikacije s drugog uređaja smije se razlikovati u sitnicama: razdjelnik može biti i zarez ili
/// tabulator, razmak ispred "pm" može biti neprekinuti (U+00A0, U+202F), "pm" može biti i "PM" ili "p.m.", a
/// 24-satno vrijeme može imati oznaku "h" ("19:51 h", izvoz s Androida). Redak vježbe može imati i bilješku
/// u drugom polju (`"8. Leg Extensions · Machine · 10 reps";"Nisam napravio"`), a prvi redak može biti prazan.
/// Datum je lokalno vrijeme bez vremenske zone. Ciljani broj ponavljanja iz retka vježbe ("10 reps") se ne uvozi.
public enum ForeignWorkoutsCSV {

    /// Jedan odrađeni trening iz datoteke.
    public struct Workout: Equatable, Sendable {
        /// Cijelo zaglavlje, npr. "Push · Day 1 · Week 9 · Gym 2.0".
        public var title: String
        /// Datum i vrijeme točno kako piše u datoteci (ključ za prepoznavanje već uvezenog treninga).
        public var rawDate: String
        public var startedAt: Date
        public var durationSeconds: Int?
        public var exercises: [Exercise]
        /// Redak zaglavlja u datoteci (od 1).
        public var line: Int
        /// Bilješka treninga iz datoteke (Strong "Workout Notes", Hevy "description"). Prazno ako je nema.
        public var notes: String = ""

        /// Naziv treninga: prvi dio zaglavlja ("Push").
        public var name: String {
            title.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? title
        }

        /// Ostatak zaglavlja ("Day 1 · Week 9 · Gym 2.0"), ide u bilješku treninga.
        public var details: String {
            title.components(separatedBy: " · ").dropFirst()
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " · ")
        }

        /// Stabilan identifikator: isti trening iz iste datoteke uvijek dobiva isti UUID,
        /// pa se ponovni uvoz (i uvoz na drugom uređaju) prepoznaje kao već postojeći trening.
        public var stableID: UUID {
            StableUUID.make(from: "foreign-workouts-csv|\(title)|\(rawDate)")
        }
    }

    public struct Exercise: Equatable, Sendable {
        public var name: String
        /// Oprema kako piše u datoteci ("Dumbbells", "Cable"). Prazno ako je nema.
        public var equipment: String
        public var sets: [SetRow]
        /// Vrsta unosa prema stupcima i vrijednostima tablice.
        public var kind: Kind
        public var line: Int
        /// Bilješka uz vježbu (drugo polje retka vježbe). Prazno ako je nema.
        public var note: String = ""
    }

    /// Vrsta unosa vježbe u datoteci.
    public enum Kind: Equatable, Sendable {
        /// Težina i ponavljanja.
        case weightReps
        /// Vlastita težina + teret ("+12.5").
        case weightedBodyweight
        /// Samo ponavljanja.
        case reps
        /// Trajanje (i eventualno udaljenost).
        case duration
        case durationDistance
    }

    /// Jedna serija. Težine u kilogramima, trajanje u sekundama, udaljenost u metrima.
    public struct SetRow: Equatable, Sendable {
        public var weightKg: Double?
        /// Teret uz vlastitu težinu (vrijednost s "+").
        public var extraWeightKg: Double?
        public var reps: Int?
        public var durationSeconds: Int?
        public var distanceMeters: Double?
        /// Serija zagrijavanja (Strong i Hevy je označavaju, ovaj format ne).
        public var isWarmUp = false

        public init(
            weightKg: Double? = nil, extraWeightKg: Double? = nil, reps: Int? = nil,
            durationSeconds: Int? = nil, distanceMeters: Double? = nil
        ) {
            self.weightKg = weightKg
            self.extraWeightKg = extraWeightKg
            self.reps = reps
            self.durationSeconds = durationSeconds
            self.distanceMeters = distanceMeters
        }

        /// Je li serija odrađena. Serija s "-" ili samo s težinom bez ponavljanja se ne uvozi.
        public var isDone: Bool {
            (reps ?? 0) > 0 || (durationSeconds ?? 0) > 0 || (distanceMeters ?? 0) > 0
        }
    }

    // MARK: Prepoznavanje

    /// Je li tekst u ovom formatu: prvi neprazni redak je zaglavlje treninga s datumom.
    /// Prepoznaje i izvoze iz Stronga i Hevyja (`StrongHevyCSV`).
    public static func matches(_ text: String) -> Bool {
        StrongHevyCSV.matches(text) || separator(of: text) != nil
    }

    private static let separators: [Character] = [";", ",", "\t"]

    /// Razdjelnik datoteke: onaj uz koji je prvi neprazni redak zaglavlje treninga. Nil kad nijedan ne odgovara.
    private static func separator(of text: String) -> Character? {
        guard let line = lines(of: text).first(where: { !$0.1.isEmpty })?.1 else { return nil }
        return separators.first { header(from: fields(line, separator: $0)) != nil }
    }

    // MARK: Čitanje

    /// Čita sve treninge. Neispravan redak baca `BackupError.invalidCSV` s brojem retka,
    /// pa se ništa ne uvozi napola.
    /// Izvoz iz Stronga ili Hevyja čita `StrongHevyCSV`; `weightUnit` je jedinica težine kad je datoteka ne navodi.
    public static func parse(_ text: String, timeZone: TimeZone = .current, weightUnit: WeightUnit = .kilograms) throws -> [Workout] {
        if StrongHevyCSV.matches(text) { return try StrongHevyCSV.parse(text, timeZone: timeZone, weightUnit: weightUnit) }
        var workouts: [Workout] = []
        var columns: [Column]?
        let delimiter = separator(of: text) ?? ";"

        for (number, line) in lines(of: text) {
            if line.isEmpty {
                columns = nil
                continue
            }
            let row = fields(line, separator: delimiter)

            if let header = header(from: row) {
                guard let date = parseDate(header.rawDate, timeZone: timeZone) else {
                    throw BackupError.invalidCSV(line: number)
                }
                workouts.append(Workout(
                    title: header.title, rawDate: header.rawDate, startedAt: date,
                    durationSeconds: parseDuration(header.duration), exercises: [], line: number
                ))
                columns = nil
                continue
            }

            guard !workouts.isEmpty else { throw BackupError.invalidCSV(line: number) }

            if row.count == 1 || row.count == 2, var exercise = exerciseLine(row[0], line: number) {
                if row.count == 2 { exercise.note = row[1] }
                workouts[workouts.count - 1].exercises.append(exercise)
                columns = nil
                continue
            }

            if row.first == "#" {
                guard !workouts[workouts.count - 1].exercises.isEmpty else { throw BackupError.invalidCSV(line: number) }
                var parsed: [Column] = []
                for name in row.dropFirst() {
                    guard let column = Column(rawValue: name.uppercased()) else { throw BackupError.invalidCSV(line: number) }
                    parsed.append(column)
                }
                columns = parsed
                continue
            }

            if let columns, let first = row.first, Int(first) != nil, row.count == columns.count + 1 {
                try appendSet(Array(row.dropFirst()), columns: columns, to: &workouts[workouts.count - 1], line: number)
                continue
            }

            throw BackupError.invalidCSV(line: number)
        }
        return workouts
    }

    // MARK: Dijelovi retka

    private enum Column: String {
        case kilograms = "KG"
        case pounds = "LBS"
        case reps = "REPS"
        case minutes = "MINS"
        case seconds = "SECS"
        case kilometers = "KM"
        case miles = "MI"
    }

    /// Redci s brojem retka (od 1), bez razmaka i BOM-a na krajevima (i kad su dvije datoteke spojene u jednu).
    private static func lines(of text: String) -> [(Int, String)] {
        let trimmed = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}"))
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .map { ($0.offset + 1, $0.element.trimmingCharacters(in: trimmed)) }
    }

    private static func fields(_ line: String, separator: Character) -> [String] {
        (CSV.parse(line, separator: separator).first ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private struct Header {
        let title: String
        let rawDate: String
        let duration: String
    }

    private static func header(from row: [String]) -> Header? {
        guard row.count == 3, !row[0].isEmpty, parseDate(row[1], timeZone: .gmt) != nil else { return nil }
        // Datum je ključ treninga, pa se razmaci svode na jedan običan: isti trening dobiva isti ključ i kad ga
        // je izvezao uređaj koji ispred "pm" stavlja neprekinuti razmak.
        return Header(title: row[0], rawDate: words(row[1]).joined(separator: " "), duration: row[2])
    }

    /// "3. Incline Bench Press · Dumbbells · 10 reps" → naziv i oprema.
    private static func exerciseLine(_ text: String, line: Int) -> Exercise? {
        guard let dot = text.firstIndex(of: "."), Int(text[..<dot]) != nil else { return nil }
        let rest = text[text.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        let parts = rest.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let name = parts.first, !name.isEmpty else { return nil }
        let equipment = parts.count > 1 && !isTarget(parts[1]) ? parts[1] : ""
        return Exercise(name: name, equipment: equipment, sets: [], kind: .weightReps, line: line)
    }

    /// Cilj iz plana ("10 reps", "1 min"), a ne oprema.
    private static func isTarget(_ text: String) -> Bool {
        text.first?.isNumber == true
    }

    private static func appendSet(_ values: [String], columns: [Column], to workout: inout Workout, line: Int) throws {
        var set = SetRow()
        var weighted = false
        for (column, raw) in zip(columns, values) {
            var text = raw.replacingOccurrences(of: ",", with: ".")
            if text == "-" || text.isEmpty { continue }
            if text.hasPrefix("+") {
                weighted = true
                text.removeFirst()
            }
            switch column {
            case .kilograms, .pounds:
                guard let value = Double(text), NumberInput.isAcceptable(value) else { throw BackupError.invalidCSV(line: line) }
                let kilograms = column == .pounds ? value * 0.45359237 : value
                if weighted { set.extraWeightKg = kilograms } else { set.weightKg = kilograms }
            case .reps:
                guard let value = Int(text), value >= 0 else { throw BackupError.invalidCSV(line: line) }
                set.reps = value
            case .minutes, .seconds:
                guard let seconds = parseTime(text, minutes: column == .minutes) else { throw BackupError.invalidCSV(line: line) }
                set.durationSeconds = seconds
            case .kilometers, .miles:
                guard let value = Double(text), NumberInput.isAcceptable(value) else { throw BackupError.invalidCSV(line: line) }
                set.distanceMeters = value * (column == .kilometers ? 1000 : 1609.344)
            }
        }

        var exercise = workout.exercises[workout.exercises.count - 1]
        exercise.sets.append(set)
        exercise.kind = kind(columns: columns, weighted: weighted || exercise.kind == .weightedBodyweight)
        if exercise.kind == .weightedBodyweight {
            // Ista vježba ima i serije bez "+": i to je teret uz vlastitu težinu.
            for index in exercise.sets.indices where exercise.sets[index].weightKg != nil {
                exercise.sets[index].extraWeightKg = exercise.sets[index].weightKg
                exercise.sets[index].weightKg = nil
            }
        }
        workout.exercises[workout.exercises.count - 1] = exercise
    }

    private static func kind(columns: [Column], weighted: Bool) -> Kind {
        let hasTime = columns.contains(.minutes) || columns.contains(.seconds)
        let hasDistance = columns.contains(.kilometers) || columns.contains(.miles)
        if hasTime || hasDistance { return hasDistance ? .durationDistance : .duration }
        if weighted { return .weightedBodyweight }
        if columns.contains(.kilograms) || columns.contains(.pounds) { return .weightReps }
        return .reps
    }

    // MARK: Datum i trajanje

    /// Riječi odvojene bilo kojim razmakom, i neprekinutim (U+00A0, U+202F), kakav neki uređaji stave ispred "pm".
    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// "2026-11-02 4:27 pm", "2026-11-02 16:27" ili "2026-11-02 16:27 h" u zadanoj vremenskoj zoni. Prihvaća i
    /// sekunde ("16:27:05") te oznaku napisanu kao "PM", "p.m." ili "p. m.".
    static func parseDate(_ text: String, timeZone: TimeZone) -> Date? {
        let parts = words(text.lowercased())
        guard parts.count >= 2 else { return nil }
        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        let rawTime = parts[1].split(separator: ":")
        let time = rawTime.compactMap { Int($0) }
        guard day.count == 3, time.count == rawTime.count, (2...3).contains(time.count),
              (1...12).contains(day[1]), (1...31).contains(day[2]), (0...59).contains(time[1]),
              time.count == 2 || (0...59).contains(time[2]) else { return nil }
        var hour = time[0]
        if parts.count > 2 {
            let marker = parts.dropFirst(2).joined().replacingOccurrences(of: ".", with: "")
            // "h" je samo oznaka 24-satnog vremena; "am" i "pm" mijenjaju sat.
            if marker != "h" {
                guard (1...12).contains(hour), marker == "am" || marker == "pm" else { return nil }
                hour = hour % 12 + (marker == "pm" ? 12 : 0)
            }
        }
        guard (0...23).contains(hour) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: day[0], month: day[1], day: day[2], hour: hour, minute: time[1])
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day[2] else { return nil }
        return date
    }

    /// "53 min", "1 hr", "1:17 hr", "1 hr 5 min", "45 sec" → sekunde. Nil za nepoznat zapis.
    static func parseDuration(_ text: String) -> Int? {
        let tokens = words(text.lowercased())
        guard !tokens.isEmpty, tokens.count % 2 == 0 else { return nil }
        var total = 0
        for index in stride(from: 0, to: tokens.count, by: 2) {
            let unit = tokens[index + 1]
            let multiplier: Int
            switch unit {
            case "hr", "hrs", "h", "hour", "hours": multiplier = 3600
            case "min", "mins", "m", "minute", "minutes": multiplier = 60
            case "sec", "secs", "s", "second", "seconds": multiplier = 1
            default: return nil
            }
            // "1:17 hr" je 1 sat i 17 minuta, "1:30 min" 1 minuta i 30 sekundi.
            let pieces = tokens[index].split(separator: ":").compactMap { Int($0) }
            guard pieces.count == tokens[index].split(separator: ":").count, (1...2).contains(pieces.count) else { return nil }
            total += pieces[0] * multiplier
            if pieces.count == 2 {
                guard (0...59).contains(pieces[1]), multiplier > 1 else { return nil }
                total += pieces[1] * multiplier / 60
            }
        }
        return total > 0 ? total : nil
    }

    /// Vrijednost u stupcu MINS ili SECS: "1", "1.5" ili "1:30".
    private static func parseTime(_ text: String, minutes: Bool) -> Int? {
        let pieces = text.split(separator: ":")
        // "1:30" je uvijek minute i sekunde.
        let limit = DurationInput.maximumSeconds
        if pieces.count == 2, let whole = Int(pieces[0]), let part = Int(pieces[1]), (0...59).contains(part) {
            // Granica prije množenja: ogroman broj minuta inače prelije `Int` i sruši aplikaciju.
            guard (0...limit / 60).contains(whole) else { return nil }
            return whole * 60 + part
        }
        // "inf" i "nan" su `Double`, ali `Int(_:)` ih ne može pretvoriti i ruši aplikaciju.
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
        let seconds = value * (minutes ? 60 : 1)
        guard seconds <= Double(limit) else { return nil }
        return Int(seconds.rounded())
    }
}

/// Deterministički UUID iz teksta (FNV-1a, 128 bita). Nije kriptografski, služi samo za prepoznavanje istog zapisa.
enum StableUUID {
    static func make(from text: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
            return hash
        }
        let high = fnv(0xCBF2_9CE4_8422_2325)
        let low = fnv(0x84222325_CBF29CE4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: high >> (56 - 8 * index))
            bytes[index + 8] = UInt8(truncatingIfNeeded: low >> (56 - 8 * index))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // verzija 5 (ime → UUID)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 varijanta
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
