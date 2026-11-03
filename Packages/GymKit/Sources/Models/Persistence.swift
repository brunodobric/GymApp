import Foundation
import SwiftData

/// Izrada `ModelContainera` za korisničku bazu.
/// Katalog vježbi je zasebna baza koja se ne sinkronizira i dodaje se u fazi 2 (`CatalogExercise`).
public enum GymPersistence {

    public enum Storage {
        /// Samo na uređaju.
        case local
        /// Privatna CloudKit baza korisnika (traži iCloud dozvolu u potpisivanju).
        case cloudKit(containerIdentifier: String)
        /// Za testove i preglede.
        case inMemory
        /// Lokalna baza na zadanoj putanji (za testove migracije).
        case file(URL)
    }

    public static let userStoreName = "User"

    public static func makeUserContainer(storage: Storage) throws -> ModelContainer {
        let schema = Schema(GymSchemaV2.models, version: GymSchemaV2.versionIdentifier)
        let configuration: ModelConfiguration
        switch storage {
        case .local:
            configuration = ModelConfiguration(userStoreName, schema: schema, cloudKitDatabase: .none)
        case .cloudKit(let identifier):
            configuration = ModelConfiguration(userStoreName, schema: schema, cloudKitDatabase: .private(identifier))
        case .inMemory:
            configuration = ModelConfiguration(
                userStoreName, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
        case .file(let url):
            configuration = ModelConfiguration(userStoreName, schema: schema, url: url, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: GymMigrationPlan.self, configurations: [configuration])
    }
}
