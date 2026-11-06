import Foundation

/// Jedna službena vježba iz kataloga (samo za čitanje).
///
/// Javni dio (`Resources/Catalog/catalog.json`) nosi naše podatke o vježbi. Upute, česte greške,
/// klipovi i posteri su MoveKit sadržaj: nisu u repozitoriju nego u privatnom dodatku
/// (`MoveKit/texts.json` i `MoveKit/Media/` u bundleu, docs/movekit.md), pa ih build bez paketa nema.
public struct CatalogExercise: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: [String: String]
    public var instructions: [String: [String]]
    public var commonMistakes: [String: [String]]
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
    /// Klip u petlji i poster, putanje unutar mape MoveKit dodatka, npr. "Media/barbell-squat.mp4".
    public let video: String?
    public let poster: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, instructions, commonMistakes, category, primaryMuscles, secondaryMuscles, equipment
        case level, mechanic, movement, inputType, primaryRegions, secondaryRegions, video, poster
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode([String: String].self, forKey: .name)
        instructions = try container.decodeIfPresent([String: [String]].self, forKey: .instructions) ?? [:]
        commonMistakes = try container.decodeIfPresent([String: [String]].self, forKey: .commonMistakes) ?? [:]
        category = try container.decode(ExerciseCategory.self, forKey: .category)
        primaryMuscles = try container.decode([Muscle].self, forKey: .primaryMuscles)
        secondaryMuscles = try container.decode([Muscle].self, forKey: .secondaryMuscles)
        equipment = try container.decode(Equipment.self, forKey: .equipment)
        level = try container.decode(Level.self, forKey: .level)
        mechanic = try container.decodeIfPresent(Mechanic.self, forKey: .mechanic)
        movement = try container.decodeIfPresent(MovementType.self, forKey: .movement)
        inputType = try container.decode(ExerciseInputType.self, forKey: .inputType)
        primaryRegions = try container.decode([String].self, forKey: .primaryRegions)
        secondaryRegions = try container.decode([String].self, forKey: .secondaryRegions)
        video = try container.decodeIfPresent(String.self, forKey: .video)
        poster = try container.decodeIfPresent(String.self, forKey: .poster)
    }

    /// Naziv na traženom jeziku ("hr", "en"). Ako prijevoda nema, vraća engleski.
    public func displayName(language: String) -> String {
        name[language] ?? name["en"] ?? id
    }

    /// Upute na traženom jeziku, inače engleske. Prazno kad MoveKit tekstova nema u buildu.
    public func displayInstructions(language: String) -> [String] {
        instructions[language] ?? instructions["en"] ?? []
    }

    public func displayCommonMistakes(language: String) -> [String] {
        commonMistakes[language] ?? commonMistakes["en"] ?? []
    }
}

public struct CatalogSource: Codable, Hashable, Sendable {
    public let name: String
    public let url: String
    public let license: String
}

/// Privatni MoveKit tekstovi jedne vježbe (`MoveKit/texts.json`): upute i česte greške po jeziku.
public struct CatalogTexts: Codable, Hashable, Sendable {
    public var instructions: [String: [String]]
    public var commonMistakes: [String: [String]]

    public init(instructions: [String: [String]] = [:], commonMistakes: [String: [String]] = [:]) {
        self.instructions = instructions
        self.commonMistakes = commonMistakes
    }

    /// Čita `texts.json`: rječnik id vježbe -> tekstovi.
    public static func decode(_ data: Data) throws -> [String: CatalogTexts] {
        try JSONDecoder().decode([String: CatalogTexts].self, from: data)
    }
}

/// Službeni katalog vježbi. Učitava se iz `catalog.json` koji generira `Tools/CatalogBuilder`.
/// Nije u bazi podataka: nepromjenjiv je i ne sinkronizira se.
public struct ExerciseCatalog: Codable, Sendable {
    public let version: Int
    public let source: CatalogSource
    /// Stari id-jevi (free-exercise-db, katalog do verzije 1) -> novi id. `nil` znači da vježba više
    /// nije u katalogu i pri migraciji postaje vlastita vježba (`CatalogIdMigration`).
    public let legacyIds: [String: String?]
    public private(set) var exercises: [CatalogExercise]

    private let index: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case version, source, legacyIds, exercises
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        source = try container.decode(CatalogSource.self, forKey: .source)
        legacyIds = try container.decodeIfPresent([String: String?].self, forKey: .legacyIds) ?? [:]
        exercises = try container.decode([CatalogExercise].self, forKey: .exercises)
        index = Self.makeIndex(exercises)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(source, forKey: .source)
        try container.encode(legacyIds, forKey: .legacyIds)
        try container.encode(exercises, forKey: .exercises)
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(ExerciseCatalog.self, from: data)
    }

    private static func makeIndex(_ exercises: [CatalogExercise]) -> [String: Int] {
        Dictionary(exercises.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Vježba po id-ju. Prihvaća i stari id iz free-exercise-db, pa stari backupi, uvoz i podaci
    /// koji još nisu migrirani i dalje pronalaze vježbu.
    public func exercise(withID id: String) -> CatalogExercise? {
        if let position = index[id] { return exercises[position] }
        if let renamed = legacyIds[id] ?? nil, let position = index[renamed] { return exercises[position] }
        return nil
    }

    /// Što se događa sa spremljenim id-jem kataloga.
    public enum IDResolution: Equatable, Sendable {
        /// Id je ispravan.
        case current
        /// Stari id koji je preimenovan.
        case renamed(String)
        /// Stari id bez para u novom katalogu.
        case removed
        /// Id koji katalog ne poznaje ni kao stari.
        case unknown
    }

    public func resolve(_ id: String) -> IDResolution {
        if index[id] != nil { return .current }
        guard let entry = legacyIds[id] else { return .unknown }
        if let renamed = entry, index[renamed] != nil { return .renamed(renamed) }
        return .removed
    }

    /// Spaja privatne MoveKit tekstove (upute i česte greške) s javnim katalogom.
    public func merging(texts: [String: CatalogTexts]) -> ExerciseCatalog {
        var copy = self
        for (position, exercise) in copy.exercises.enumerated() {
            guard let text = texts[exercise.id] else { continue }
            copy.exercises[position].instructions = text.instructions
            copy.exercises[position].commonMistakes = text.commonMistakes
        }
        return copy
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
