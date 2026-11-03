#if DEBUG
import CoreData
import Models
import SwiftData
import SwiftUI

/// Alat za razvoj: stvara cijelu shemu korisničke baze u CloudKit Development okruženju.
///
/// SwiftData sam stvara samo tipove i polja zapisa koje je stvarno poslao, pa bi polje koje je uvijek nil
/// (npr. `UserSettings.modifiedAt` na novom uređaju) nedostajalo u shemi. `initializeCloudKitSchema` šalje
/// po jedan probni zapis svakog tipa sa svim poljima i odmah ga briše. Nakon toga se shema u CloudKit konzoli
/// objavljuje u produkcijsko okruženje (vidi docs/sinkronizacija.md).
@MainActor
enum CloudKitSchemaTool {
    static func initializeSchema() throws {
        // Zasebna privremena datoteka: korisnička baza je već otvorena, a alat ne smije dirati njezine podatke.
        let url = FileManager.default.temporaryDirectory.appending(path: "CloudKitSchema-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        try autoreleasepool {
            let description = NSPersistentStoreDescription(url: url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: AppServices.cloudContainerIdentifier
            )
            description.shouldAddStoreAsynchronously = false
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: GymSchemaV2.models) else {
                throw CocoaError(.featureUnsupported)
            }
            let container = NSPersistentCloudKitContainer(name: GymPersistence.userStoreName, managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }
    }
}

/// Ekran u Prototipima (samo Debug build) za pokretanje alata.
struct CloudKitSchemaToolView: View {
    @State private var result: String?
    @State private var isRunning = false

    var body: some View {
        Form {
            Section {
                Button("Stvori shemu u Developmentu") { run() }
                    .disabled(isRunning || !AppServices.isCloudSyncSupported)
                if isRunning { ProgressView() }
                if let result { Text(result).font(.footnote) }
            } footer: {
                Text("""
                    Pokreće se iz Xcodea (Debug build ide u Development okruženje), nakon svake promjene sheme. \
                    Zatim u CloudKit konzoli: Deploy Schema Changes u produkciju.
                    """)
            }
            Section("Stanje") {
                LabeledContent("Sinkronizacija u ovom pokretanju", value: AppServices.isSyncRunning ? "da" : "ne")
                LabeledContent("Kontejner", value: AppServices.cloudContainerIdentifier)
            }
        }
        .navigationTitle("CloudKit shema")
    }

    private func run() {
        isRunning = true
        defer { isRunning = false }
        do {
            try CloudKitSchemaTool.initializeSchema()
            result = "Shema je poslana u Development. Provjeri tipove CD_* u CloudKit konzoli."
        } catch {
            result = "Nije uspjelo: \(error)"
        }
    }
}
#endif
