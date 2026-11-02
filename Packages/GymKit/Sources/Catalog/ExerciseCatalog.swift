import Foundation

/// Jedna službena vježba iz kataloga (samo za čitanje).
public struct CatalogExercise: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: [String: String]
    public let instructions: [String: [String]]
    public let category: ExerciseCategory
    public let primaryMuscles: [Muscle]
    public let secondaryMuscles: [Muscle]
    public let equipment: Equipment
    public let level: Level
    public let mechanic: Mechanic?
    public let movement: MovementType?
    public let inputType: ExerciseInputType
    /// Regije body heatmapa (za statistiku).
    public let primaryRegions: [String]
    public let secondaryRegions: [String]
    /// Putanje slika unutar mape kataloga, npr. "Images/Pushups/0.jpg".
    public let images: [String]

    /// Naziv na traženom jeziku ("hr", "en"). Ako prijevoda nema, vraća engleski.
    public func displayName(language: String) -> String {
        name[language] ?? name["en"] ?? id
    }

    public func displayInstructions(language: String) -> [String] {
        instructions[language] ?? instructions["en"] ?? []
    }
}

public struct CatalogSource: Codable, Hashable, Sendable {
    public let name: String
    public let repository: String
    public let commit: String
    public let license: String
}

/// Službeni katalog vježbi. Učitava se iz `catalog.json` koji generira `Tools/CatalogBuilder`.
/// Nije u bazi podataka: nepromjenjiv je, malen (stotinjak vježbi) i ne sinkronizira se.
public struct ExerciseCatalog: Codable, Sendable {
    public let version: Int
    public let source: CatalogSource
    public let exercises: [CatalogExercise]

    private let index: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case version, source, exercises
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        source = try container.decode(CatalogSource.self, forKey: .source)
        exercises = try container.decode([CatalogExercise].self, forKey: .exercises)
        index = Dictionary(exercises.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(source, forKey: .source)
        try container.encode(exercises, forKey: .exercises)
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(ExerciseCatalog.self, from: data)
    }

    public func exercise(withID id: String) -> CatalogExercise? {
        index[id].map { exercises[$0] }
    }

    /// Sažeci za popis i pretragu.
    public func summaries(language: String) -> [ExerciseSummary] {
        exercises.map { exercise in
            ExerciseSummary(
                source: .catalog(id: exercise.id),
                name: exercise.displayName(language: language),
                alternativeNames: Array(exercise.name.values),
                category: exercise.category,
                muscles: exercise.primaryMuscles,
                equipment: exercise.equipment,
                isArchived: false
            )
        }
    }
}
