import Foundation

/// Ugrađena vrijednost (ne zaseban model): upućuje na vježbu iz kataloga ili na vlastitu vježbu.
/// Sprema i naziv za prikaz, pa povijest ostaje čitljiva i ako vježba nestane.
public struct ExerciseRef: Hashable, Codable, Sendable {
    public var catalogId: String?
    public var customExerciseId: UUID?
    public var name: String

    public init(catalogId: String, name: String) {
        self.catalogId = catalogId
        self.customExerciseId = nil
        self.name = name
    }

    public init(customExerciseId: UUID, name: String) {
        self.catalogId = nil
        self.customExerciseId = customExerciseId
        self.name = name
    }

    init(catalogId: String?, customExerciseId: UUID?, name: String) {
        self.catalogId = catalogId
        self.customExerciseId = customExerciseId
        self.name = name
    }

    /// Stabilan ključ za upite: "c:<id kataloga>" ili "u:<UUID vlastite vježbe>".
    public var key: String {
        if let catalogId { return "c:\(catalogId)" }
        if let customExerciseId { return "u:\(customExerciseId.uuidString)" }
        return ""
    }
}
