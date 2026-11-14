import Foundation

/// Trajne bilješke vježbi: postavka sprave, hvat, širina stava. Vrijede za vježbu gdje god se radi
/// (svi treninzi i prazan trening), za razliku od bilješke uz vježbu u predlošku.
/// Spremaju se u postavkama (`UserSettings.exerciseNotesRaw`) kao JSON `{ključ vježbe: tekst}`, isto na Androidu.
public struct ExerciseNotes: Equatable, Sendable {
    public private(set) var notes: [String: String]

    public init(raw: String = "") {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            notes = [:]
            return
        }
        notes = decoded
    }

    /// Bilješka vježbe (`ExerciseRef.key`), nil bez bilješke.
    public func note(for key: String) -> String? {
        notes[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Postavlja bilješku; prazan tekst je briše.
    public mutating func setNote(_ text: String, for key: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[key] = trimmed.isEmpty ? nil : trimmed
    }

    /// JSON s ključevima abecedno, da isti sadržaj uvijek daje isti tekst (sinkronizacija, kopija).
    public var raw: String {
        guard !notes.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(notes) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension GymSchemaV1.UserSettings {
    /// Trajne bilješke vježbi (`ExerciseNotes`).
    public var exerciseNotes: ExerciseNotes {
        get { ExerciseNotes(raw: exerciseNotesRaw) }
        set { exerciseNotesRaw = newValue.raw }
    }
}
