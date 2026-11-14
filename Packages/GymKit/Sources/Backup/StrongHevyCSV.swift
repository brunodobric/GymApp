import Foundation
import Units

/// Čitanje CSV izvoza iz aplikacija Strong i Hevy u isti oblik kao `ForeignWorkoutsCSV`, pa uvoz
/// (pregled, prepoznavanje vježbi, preskakanje već uvezenih) radi isto. Isto kao `StrongHevyCsv` na Androidu.
///
/// Oba izvoza imaju jedan redak po seriji i zaglavlje sa stupcima:
///
///     Strong: Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
///     Hevy:   title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,
///             weight_kg,reps,distance_km,duration_seconds,rpe
///
/// Oprema je u nazivu vježbe u zagradi ("Bench Press (Barbell)"). Zagrijavanje (Strong "W", Hevy "warmup")
/// uvozi se kao zagrijavanje. Strong ne piše jedinicu težine, pa se uzima jedinica iz postavki (`weightUnit`),
/// osim kad je u nazivu stupca ("Weight (lbs)"). Razdjelnik može biti zarez ili točka-zarez.
public enum StrongHevyCSV {

    enum Format: Equatable { case strong, hevy }

    /// Je li tekst izvoz iz Stronga ili Hevyja.
    public static func matches(_ text: String) -> Bool {
        detect(text) != nil
    }

    /// Čita sve treninge, od najstarijeg prema najnovijem redom kako su u datoteci.
    /// Neispravan redak baca `BackupError.invalidCSV` s brojem retka.
    public static func parse(
        _ text: String, timeZone: TimeZone = .current, weightUnit: WeightUnit = .kilograms
    ) throws -> [ForeignWorkoutsCSV.Workout] {
        guard let (format, separator) = detect(text) else { throw BackupError.invalidCSV(line: 1) }
        let rows = CSV.parse(text.replacingOccurrences(of: "\u{FEFF}", with: ""), separator: separator)
        guard let headerRow = rows.first else { return [] }
        let header = headerRow.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let columns = Columns(header: header, format: format, defaultUnit: weightUnit)

        var workouts: [ForeignWorkoutsCSV.Workout] = []
        var index: [String: Int] = [:]
        for (offset, row) in rows.enumerated().dropFirst() {
            let line = offset + 1
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            let value = { (column: Int?) -> String in
                guard let column, column < row.count else { return "" }
                return row[column].trimmingCharacters(in: .whitespaces)
            }
            let title = value(columns.title)
            let rawDate = value(columns.date)
            guard let startedAt = parseDate(rawDate, format: format, timeZone: timeZone) else {
                throw BackupError.invalidCSV(line: line)
            }
            let key = title + "|" + rawDate
            if index[key] == nil {
                index[key] = workouts.count
                var duration: Int?
                if format == .hevy, let end = parseDate(value(columns.end), format: format, timeZone: timeZone) {
                    duration = max(0, Int(end.timeIntervalSince(startedAt)))
                } else {
                    duration = parseDuration(value(columns.duration))
                }
                var workout = ForeignWorkoutsCSV.Workout(
                    title: title.isEmpty ? "Trening" : title, rawDate: rawDate, startedAt: startedAt,
                    durationSeconds: duration, exercises: [], line: line
                )
                workout.notes = value(columns.workoutNotes)
                workouts.append(workout)
            }
            guard let position = index[key] else { continue }

            let (name, equipment) = splitName(value(columns.exercise))
            guard !name.isEmpty else { throw BackupError.invalidCSV(line: line) }
            let set = try setRow(value: value, columns: columns, format: format, line: line)
            var exercises = workouts[position].exercises
            if let last = exercises.last, last.name == name, last.equipment == equipment {
                exercises[exercises.count - 1].sets.append(set)
            } else {
                exercises.append(ForeignWorkoutsCSV.Exercise(
                    name: name, equipment: equipment, sets: [set], kind: .weightReps, line: line,
                    note: value(columns.exerciseNotes)
                ))
            }
            exercises[exercises.count - 1].kind = kind(of: exercises[exercises.count - 1].sets)
            workouts[position].exercises = exercises
        }
        return workouts
    }

    // MARK: Pomoćno

    /// Stupci po nazivu: Strong i Hevy ih nazivaju različito, a novije verzije dodaju ili mijenjaju stupce.
    struct Columns {
        var title: Int?
        var date: Int?
        var end: Int?
        var duration: Int?
        var exercise: Int?
        var setOrder: Int?
        var setType: Int?
        var weight: Int?
        var reps: Int?
        var distance: Int?
        var seconds: Int?
        var exerciseNotes: Int?
        var workoutNotes: Int?
        var rpe: Int?
        var weightUnit: WeightUnit = .kilograms
        var distanceInMiles = false

        init(header: [String], format: Format, defaultUnit: WeightUnit) {
            func find(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
            func prefix(_ start: String) -> Int? { header.firstIndex { $0.hasPrefix(start) } }
            switch format {
            case .strong:
                title = find(["workout name"])
                date = find(["date"])
                duration = prefix("duration")
                exercise = find(["exercise name"])
                setOrder = find(["set order"])
                weight = prefix("weight")
                reps = find(["reps"])
                distance = prefix("distance")
                seconds = prefix("seconds")
                exerciseNotes = find(["notes"])
                workoutNotes = find(["workout notes"])
                rpe = find(["rpe"])
                let weightName = weight.map { header[$0] } ?? ""
                weightUnit = weightName.contains("lb") ? .pounds : (weightName.contains("kg") ? .kilograms : defaultUnit)
                distanceInMiles = distance.map { header[$0].contains("mi") } ?? false
            case .hevy:
                title = find(["title"])
                date = find(["start_time"])
                end = find(["end_time"])
                exercise = find(["exercise_title"])
                setOrder = find(["set_index"])
                setType = find(["set_type"])
                if let kilograms = find(["weight_kg"]) {
                    weight = kilograms
                } else if let pounds = find(["weight_lbs", "weight_lb"]) {
                    weight = pounds
                    weightUnit = .pounds
                }
                reps = find(["reps"])
                if let kilometers = find(["distance_km"]) {
                    distance = kilometers
                } else if let miles = find(["distance_miles", "distance_mi"]) {
                    distance = miles
                    distanceInMiles = true
                }
                seconds = find(["duration_seconds"])
                exerciseNotes = find(["exercise_notes"])
                workoutNotes = find(["description"])
                rpe = find(["rpe"])
            }
        }
    }

    /// Format i razdjelnik prema prvom retku (zaglavlju).
    static func detect(_ text: String) -> (Format, Character)? {
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        guard let first = cleaned.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        for separator in [Character(","), ";"] {
            let names = Set(CSV.parse(String(first), separator: separator).first?.map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            } ?? [])
            if names.isSuperset(of: ["date", "workout name", "exercise name", "set order"]) { return (.strong, separator) }
            if names.isSuperset(of: ["title", "start_time", "exercise_title", "set_index"]) { return (.hevy, separator) }
        }
        return nil
    }

    private static func setRow(
        value: (Int?) -> String, columns: Columns, format: Format, line: Int
    ) throws -> ForeignWorkoutsCSV.SetRow {
        var set = ForeignWorkoutsCSV.SetRow()
        if let weight = try number(value(columns.weight), line: line), weight > 0 {
            set.weightKg = WeightConversion.kilograms(from: weight, in: columns.weightUnit)
        }
        if let reps = try number(value(columns.reps), line: line), reps > 0 { set.reps = Int(reps.rounded()) }
        if let seconds = try number(value(columns.seconds), line: line), seconds > 0 { set.durationSeconds = Int(seconds.rounded()) }
        if let distance = try number(value(columns.distance), line: line), distance > 0 {
            set.distanceMeters = distance * (columns.distanceInMiles ? 1609.344 : 1000)
        }
        switch format {
        case .strong: set.isWarmUp = value(columns.setOrder).uppercased() == "W"
        case .hevy: set.isWarmUp = value(columns.setType).lowercased() == "warmup"
        }
        return set
    }

    /// Broj s točkom ili zarezom kao decimalnim znakom; prazno je nil, a neispravan broj greška.
    private static func number(_ text: String, line: Int) throws -> Double? {
        guard !text.isEmpty else { return nil }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
            throw BackupError.invalidCSV(line: line)
        }
        return value
    }

    /// Vrsta unosa prema serijama: trajanje i udaljenost, težina ili samo ponavljanja.
    static func kind(of sets: [ForeignWorkoutsCSV.SetRow]) -> ForeignWorkoutsCSV.Kind {
        if sets.contains(where: { ($0.distanceMeters ?? 0) > 0 }) { return .durationDistance }
        if sets.contains(where: { ($0.durationSeconds ?? 0) > 0 }) && !sets.contains(where: { ($0.reps ?? 0) > 0 }) { return .duration }
        if sets.contains(where: { ($0.weightKg ?? 0) > 0 }) { return .weightReps }
        return .reps
    }

    /// "Bench Press (Barbell)" → ("Bench Press", "Barbell"). Bez zagrade oprema je prazna.
    static func splitName(_ text: String) -> (String, String) {
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return (text, "") }
        let name = text[..<open].trimmingCharacters(in: .whitespaces)
        let equipment = text[text.index(after: open)..<text.index(before: text.endIndex)].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (text, "") : (name, equipment)
    }

    /// Strong: "2023-01-15 08:30:00". Hevy: "15 Jan 2023, 08:30" (i ISO 8601 u novijim izvozima).
    static func parseDate(_ text: String, format: Format, timeZone: TimeZone) -> Date? {
        guard !text.isEmpty else { return nil }
        let patterns = switch format {
        case .strong: ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"]
        case .hevy: ["d MMM yyyy, HH:mm", "d MMM yyyy HH:mm", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"]
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for pattern in patterns {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// Strong: "1h 5m", "45m", "50s" ili broj sekundi. Nil kad trajanja nema.
    static func parseDuration(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let seconds = Int(trimmed) { return seconds }
        var total = 0
        var found = false
        var number = ""
        for character in trimmed {
            if character.isNumber {
                number.append(character)
                continue
            }
            guard let value = Int(number) else { continue }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: continue
            }
            found = true
            number = ""
        }
        return found ? total : nil
    }
}
