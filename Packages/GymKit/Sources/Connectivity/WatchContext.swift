import Catalog
import Foundation
import Models
import Units
import WidgetData

// Zadnje stanje koje iPhone šalje satu preko `updateApplicationContext` (specifikacija, odjeljak 6):
// sljedeći treninzi i predlošci s pretpunjenim serijama (smart defaults), jedinica i zadana pauza.
// Sat ga sprema, pa trening može započeti i kad iPhone nije u blizini.

public struct PlannedSetPayload: Codable, Sendable, Hashable {
    public var kind: SetKind
    public var weightKg: Double?
    public var reps: Int?
    public var extraWeightKg: Double?
    public var durationSeconds: Int?
    public var distanceMeters: Double?

    public init(
        kind: SetKind = .working, weightKg: Double? = nil, reps: Int? = nil, extraWeightKg: Double? = nil,
        durationSeconds: Int? = nil, distanceMeters: Double? = nil
    ) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.extraWeightKg = extraWeightKg
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }
}

public struct PlannedExercisePayload: Codable, Sendable, Hashable {
    public var exercise: ExerciseRef
    public var inputType: ExerciseInputType
    public var restSeconds: Int?
    /// Vježbe s istim brojem čine superset (broj vrijedi samo unutar jednog plana).
    public var supersetGroup: Int?
    public var sets: [PlannedSetPayload]
    /// Kardio vježba (katalog ili vlastita vježba u kategoriji kardio). Nil iz starije verzije aplikacije.
    public var isCardio: Bool?
    /// Završene serije zadnjeg izvođenja, za redak "prošli put" na satu. Nil iz starije verzije aplikacije.
    public var previous: [PlannedSetPayload]?
    /// Složena vježba iz kataloga (zadana pauza, `RestDefaults`). Nil kad se ne zna ili iz starije verzije aplikacije.
    public var isCompound: Bool?

    public init(
        exercise: ExerciseRef, inputType: ExerciseInputType, restSeconds: Int? = nil, supersetGroup: Int? = nil,
        sets: [PlannedSetPayload], isCardio: Bool? = nil, previous: [PlannedSetPayload]? = nil, isCompound: Bool? = nil
    ) {
        self.exercise = exercise
        self.inputType = inputType
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
        self.sets = sets
        self.isCardio = isCardio
        self.isCompound = isCompound
        self.previous = previous
    }
}

public struct PlannedWorkoutPayload: Codable, Sendable, Hashable, Identifiable {
    public var templateId: UUID?
    public var scheduleId: UUID?
    public var name: String
    /// Naziv rasporeda kad je ovo njegov sljedeći trening.
    public var scheduleName: String?
    public var kind: WorkoutKind
    public var exercises: [PlannedExercisePayload]

    public init(
        templateId: UUID?, scheduleId: UUID?, name: String, scheduleName: String?, kind: WorkoutKind,
        exercises: [PlannedExercisePayload]
    ) {
        self.templateId = templateId
        self.scheduleId = scheduleId
        self.name = name
        self.scheduleName = scheduleName
        self.kind = kind
        self.exercises = exercises
    }

    public var id: String {
        "\(scheduleId?.uuidString ?? "-")/\(templateId?.uuidString ?? name)"
    }
}

public struct WatchContextPayload: Codable, Sendable, Equatable {
    /// Sljedeći trening svakog aktivnog rasporeda.
    public var upcoming: [PlannedWorkoutPayload]
    /// Predlošci izvan rasporeda (za trening koji nije na redu).
    public var templates: [PlannedWorkoutPayload]
    public var weightUnit: WeightUnit
    /// Zadana pauza za izolacijske i ostale vježbe.
    public var defaultRestSeconds: Int
    /// Zadana pauza za složene vježbe. Nil iz starije verzije aplikacije (tada vrijedi `defaultRestSeconds`).
    public var compoundRestSeconds: Int?
    /// Korisnik je u aplikaciji uključio Apple Zdravlje: sat sprema trening u Zdravlje.
    public var savesToHealth: Bool
    public var generatedAt: Date
    /// Tekući tjedan za komplikaciju tjednog cilja (isti kao u widgetima na iPhoneu). Nil iz starije verzije aplikacije.
    public var week: WidgetSnapshot.Week?
    /// Zadnja tjelesna težina u kg, za komplikaciju težine.
    public var bodyWeightKg: Double?
    /// Naglasna boja iz postavki na iPhoneu. Nil iz starije verzije aplikacije (sat tada koristi plavu).
    public var accent: AccentChoice?

    public init(
        upcoming: [PlannedWorkoutPayload], templates: [PlannedWorkoutPayload], weightUnit: WeightUnit,
        defaultRestSeconds: Int, savesToHealth: Bool, generatedAt: Date
    ) {
        self.upcoming = upcoming
        self.templates = templates
        self.weightUnit = weightUnit
        self.defaultRestSeconds = defaultRestSeconds
        self.savesToHealth = savesToHealth
        self.generatedAt = generatedAt
    }

    /// Kad sat još nije dobio ništa od iPhonea.
    public static let empty = WatchContextPayload(
        upcoming: [], templates: [], weightUnit: .kilograms, defaultRestSeconds: 90, savesToHealth: false,
        generatedAt: .distantPast
    )
}

/// Sadržaj `updateApplicationContext`. iPhone šalje kontekst za sat i, dok iPhone vodi trening, njegovu
/// snimku. Sat šalje snimku treninga koji vodi. Ključ koji nedostaje znači "nema" (npr. nema treninga).
public struct ApplicationContextPayload: Sendable, Equatable {
    public static let contextKey = "watchContext"
    public static let sessionKey = "session"

    public var watchContext: WatchContextPayload?
    public var session: SessionSnapshot?

    public init(watchContext: WatchContextPayload? = nil, session: SessionSnapshot? = nil) {
        self.watchContext = watchContext
        self.session = session
    }

    /// Podaci su JSON sažet LZFSE-om, jer WatchConnectivity ima ograničenje veličine.
    public func dictionary() throws -> [String: Any] {
        let encoder = ConnectivityCoding.makeEncoder()
        var result: [String: Any] = [:]
        if let watchContext { result[Self.contextKey] = try Self.compress(encoder.encode(watchContext)) }
        if let session { result[Self.sessionKey] = try Self.compress(encoder.encode(session)) }
        return result
    }

    /// Neispravan ili nepoznat dio se preskače (npr. nakon nadogradnje samo jednog uređaja).
    public init(dictionary: [String: Any]) {
        let decoder = ConnectivityCoding.makeDecoder()
        if let data = dictionary[Self.contextKey] as? Data, let raw = try? Self.decompress(data) {
            watchContext = try? decoder.decode(WatchContextPayload.self, from: raw)
        }
        if let data = dictionary[Self.sessionKey] as? Data, let raw = try? Self.decompress(data) {
            session = try? decoder.decode(SessionSnapshot.self, from: raw)
        }
    }

    static func compress(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .lzfse) as Data
    }

    static func decompress(_ data: Data) throws -> Data {
        try (data as NSData).decompressed(using: .lzfse) as Data
    }
}

/// Spremanje konteksta i snimke na satu (JSON), da prežive gašenje aplikacije.
public enum SnapshotStorage {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try ConnectivityCoding.makeEncoder().encode(value)
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try ConnectivityCoding.makeDecoder().decode(type, from: data)
    }
}
