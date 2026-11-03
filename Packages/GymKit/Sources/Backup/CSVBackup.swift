import Foundation
import Models
import SwiftData

/// CSV izvoz i uvoz: povijest treninga (jedan redak po seriji) i tjelesna mjerenja.
/// Težine su uvijek u kilogramima, a udaljenost u metrima, neovisno o jedinici u Postavkama.
public enum CSVBackup {
    static let historyColumns = [
        "session_id", "session_name", "workout_kind", "started_at", "ended_at", "session_notes",
        "exercise_order", "exercise_key", "exercise_name", "input_type", "superset_group", "rest_seconds",
        "set_order", "set_kind", "weight_kg", "reps", "extra_weight_kg", "duration_s", "distance_m", "rpe", "completed_at"
    ]
    static let bodyColumns = ["id", "kind", "custom_name", "value", "date", "source"]

    // MARK: Povijest treninga

    public static func exportHistory(from context: ModelContext) throws -> String {
        let finished = SessionState.finished.rawValue
        let sessions = try context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == finished }, sortBy: [SortDescriptor(\.startedAt)]
        ))
        var lines = [CSV.line(historyColumns)]
        for session in sessions.sorted(by: { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }) {
            let head = [
                session.id.uuidString, session.name, session.kindRaw, CSVDate.string(session.startedAt),
                CSVDate.string(session.endedAt), session.notes
            ]
            let exercises = session.orderedExercises.filter { !$0.isRemoved }
            if exercises.isEmpty {
                lines.append(CSV.line(head + Array(repeating: "", count: historyColumns.count - head.count)))
            }
            for exercise in exercises {
                let exerciseFields = [
                    String(exercise.orderIndex), exercise.exerciseKey, exercise.exerciseName, exercise.inputTypeRaw,
                    exercise.supersetGroupId?.uuidString ?? "", exercise.restSeconds.map(String.init) ?? ""
                ]
                let sets = exercise.orderedSets
                if sets.isEmpty {
                    lines.append(CSV.line(head + exerciseFields + Array(repeating: "", count: 9)))
                }
                for set in sets {
                    lines.append(CSV.line(head + exerciseFields + [
                        String(set.orderIndex), set.kindRaw, number(set.weightKg), set.reps.map(String.init) ?? "",
                        number(set.extraWeightKg), set.durationSeconds.map(String.init) ?? "",
                        number(set.distanceMeters), number(set.rpe), CSVDate.string(set.completedAt)
                    ]))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Uvozi treninge iz CSV-a koji je izvezen ovom aplikacijom. Treninzi čiji `session_id` već postoji se preskaču.
    /// Datoteka se prvo cijela provjeri, pa neispravan redak ne ostavlja polovičan uvoz.
    @discardableResult
    public static func importHistory(_ text: String, into context: ModelContext) throws -> BackupImportResult {
        let rows = CSV.parse(text)
        guard let header = rows.first, header == historyColumns else { throw BackupError.invalidCSV(line: 1) }

        struct Line {
            let number: Int
            let fields: [String]
        }
        var order: [UUID] = []
        var groups: [UUID: [Line]] = [:]
        for (index, row) in rows.enumerated().dropFirst() {
            guard row.count == historyColumns.count, let id = UUID(uuidString: row[0]),
                  CSVDate.parse(row[3]) != nil else { throw BackupError.invalidCSV(line: index + 1) }
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(Line(number: index + 1, fields: row))
        }

        let known = Set(try context.fetch(FetchDescriptor<Session>()).map(\.id))
        var result = BackupImportResult()
        do {
            for id in order {
                guard !known.contains(id) else {
                    result.skipped += 1
                    continue
                }
                try buildSession(id: id, lines: (groups[id] ?? []).map { ($0.number, $0.fields) }, in: context)
                result.added += 1
            }
        } catch {
            context.rollback()
            throw error
        }
        try context.save()
        return result
    }

    private static func buildSession(id: UUID, lines: [(number: Int, fields: [String])], in context: ModelContext) throws {
        let head = lines[0].fields
        let session = Session(name: head[1], startedAt: CSVDate.parse(head[3]) ?? Date())
        session.id = id
        session.kindRaw = head[2]
        session.endedAt = CSVDate.parse(head[4])
        session.notes = head[5]
        session.state = .finished
        session.lastActivityAt = session.endedAt ?? session.startedAt
        context.insert(session)

        var exercises: [Int: SessionExercise] = [:]
        for line in lines where !line.fields[6].isEmpty {
            let f = line.fields
            guard let exerciseOrder = Int(f[6]), let ref = ExerciseRef(key: f[7], name: f[8]) else {
                throw BackupError.invalidCSV(line: line.number)
            }
            let exercise: SessionExercise
            if let existing = exercises[exerciseOrder] {
                exercise = existing
            } else {
                exercise = SessionExercise(orderIndex: exerciseOrder, exercise: ref)
                exercise.inputTypeRaw = f[9]
                exercise.supersetGroupId = UUID(uuidString: f[10])
                exercise.restSeconds = Int(f[11])
                context.insert(exercise)
                exercise.session = session
                exercises[exerciseOrder] = exercise
            }
            guard !f[12].isEmpty else { continue }
            guard let setOrder = Int(f[12]) else { throw BackupError.invalidCSV(line: line.number) }
            let set = try makeSet(order: setOrder, fields: f, line: line.number)
            context.insert(set)
            set.exercise = exercise
        }
    }

    private static func makeSet(order: Int, fields f: [String], line: Int) throws -> SetLog {
        func double(_ text: String) throws -> Double? {
            if text.isEmpty { return nil }
            guard let value = Double(text) else { throw BackupError.invalidCSV(line: line) }
            return value
        }
        func integer(_ text: String) throws -> Int? {
            if text.isEmpty { return nil }
            guard let value = Int(text) else { throw BackupError.invalidCSV(line: line) }
            return value
        }
        let set = SetLog(orderIndex: order)
        set.kindRaw = f[13]
        set.weightKg = try double(f[14])
        set.reps = try integer(f[15])
        set.extraWeightKg = try double(f[16])
        set.durationSeconds = try integer(f[17])
        set.distanceMeters = try double(f[18])
        set.rpe = try double(f[19])
        set.completedAt = CSVDate.parse(f[20])
        return set
    }

    // MARK: Tjelesna mjerenja

    public static func exportBody(from context: ModelContext) throws -> String {
        let all = try context.fetch(FetchDescriptor<BodyMeasurement>())
        var lines = [CSV.line(bodyColumns)]
        for item in all.sorted(by: { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }) {
            lines.append(CSV.line([
                item.id.uuidString, item.kindRaw, item.customName ?? "", "\(item.value)",
                CSVDate.string(item.date), item.sourceRaw
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @discardableResult
    public static func importBody(_ text: String, into context: ModelContext) throws -> BackupImportResult {
        let rows = CSV.parse(text)
        guard let header = rows.first, header == bodyColumns else { throw BackupError.invalidCSV(line: 1) }
        var known = Set(try context.fetch(FetchDescriptor<BodyMeasurement>()).map(\.id))
        var result = BackupImportResult()
        for (index, row) in rows.enumerated().dropFirst() {
            guard row.count == bodyColumns.count, let id = UUID(uuidString: row[0]), let value = Double(row[3]),
                  let date = CSVDate.parse(row[4]) else { throw BackupError.invalidCSV(line: index + 1) }
            guard known.insert(id).inserted else {
                result.skipped += 1
                continue
            }
            let item = BodyMeasurement(kind: .custom, value: value, date: date)
            item.id = id
            item.kindRaw = row[1]
            item.customName = row[2].isEmpty ? nil : row[2]
            item.sourceRaw = row[5]
            context.insert(item)
            result.added += 1
        }
        try context.save()
        return result
    }

    static func number(_ value: Double?) -> String {
        value.map { "\($0)" } ?? ""
    }
}
