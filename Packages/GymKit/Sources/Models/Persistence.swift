import SwiftData

/// Izrada `ModelContainera`: korisnička baza (sinkronizira se) i lokalna baza podataka iz Zdravlja
/// (nikad se ne sinkronizira, vidi `HealthLocal.swift`). Obje su u istom containeru, pa ih isti
/// `ModelContext` i upiti vide zajedno.
/// Katalog vježbi nije u SwiftDati, nego je datoteka u aplikaciji (vidi `ExerciseCatalog`).
public enum GymPersistence {

    public enum Storage {
        /// Samo na uređaju.
        case local
        /// Privatna CloudKit baza korisnika (traži iCloud dozvolu u potpisivanju).
        case cloudKit(containerIdentifier: String)
        /// Za testove i preglede.
        case inMemory
    }

    public static let userStoreName = "User"
    public static let healthStoreName = "HealthLocal"

    /// Do prvog izdanja shema se mijenja samo dodavanjem, a SwiftData sam radi laku migraciju, pa se
    /// `GymMigrationPlan` ne predaje. Kod izdanja se verzija zamrzava, a plan migracije počinje se koristiti.
    public static func makeUserContainer(storage: Storage) throws -> ModelContainer {
        let userSchema = Schema(GymSchemaV1.models, version: GymSchemaV1.versionIdentifier)
        let healthSchema = Schema(GymHealthSchema.models)
        let fullSchema = Schema(GymSchemaV1.models + GymHealthSchema.models)
        let inMemory: Bool
        let userDatabase: ModelConfiguration.CloudKitDatabase
        switch storage {
        case .local:
            inMemory = false
            userDatabase = .none
        case .cloudKit(let identifier):
            inMemory = false
            userDatabase = .private(identifier)
        case .inMemory:
            inMemory = true
            userDatabase = .none
        }
        let user = ModelConfiguration(
            userStoreName, schema: userSchema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: userDatabase
        )
        // Izričito .none: s iCloud dozvolom bi zadano (.automatic) sinkroniziralo i ovu bazu.
        let health = ModelConfiguration(
            healthStoreName, schema: healthSchema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: [user, health])
    }
}

public extension ModelContext {
    /// Briše sve zapise modela jedan po jedan. Skupno brisanje (`delete(model:)`) ne radi kad kontejner
    /// ima više konfiguracija: Core Data ga šalje svakoj bazi, a baza bez tog modela javlja grešku.
    func deleteEvery<T: PersistentModel>(_ model: T.Type) throws {
        for item in try fetch(FetchDescriptor<T>()) {
            delete(item)
        }
    }
}
