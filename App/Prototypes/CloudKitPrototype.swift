#if DEBUG
import CloudKit
import SwiftData
import SwiftUI

// Prototip 1: SwiftData s dvije konfiguracije.
// * PrototypeSyncedItem ide u CloudKit privatnu bazu (kao buduća korisnička baza).
// * PrototypeCatalogItem ostaje samo lokalno (kao budući katalog vježbi).
// Modeli poštuju pravila CloudKita: sva svojstva imaju zadanu vrijednost, nema `unique`,
// a redoslijed se čuva u `orderIndex`.

@Model
final class PrototypeSyncedItem {
    var id: UUID = UUID()
    var title: String = ""
    var orderIndex: Int = 0
    var createdAt: Date = Date()
    var deviceName: String = ""

    init(title: String, orderIndex: Int, deviceName: String) {
        self.title = title
        self.orderIndex = orderIndex
        self.deviceName = deviceName
    }
}

@Model
final class PrototypeCatalogItem {
    var catalogId: String = ""
    var name: String = ""

    init(catalogId: String, name: String) {
        self.catalogId = catalogId
        self.name = name
    }
}

enum CloudKitPrototypeStore {
    static let containerIdentifier = "iCloud.com.brunodobric.gymapp"

    static func makeContainer() throws -> ModelContainer {
        let synced = ModelConfiguration(
            "PrototypeSynced",
            schema: Schema([PrototypeSyncedItem.self]),
            cloudKitDatabase: .private(containerIdentifier)
        )
        let localOnly = ModelConfiguration(
            "PrototypeCatalog",
            schema: Schema([PrototypeCatalogItem.self]),
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: Schema([PrototypeSyncedItem.self, PrototypeCatalogItem.self]),
            configurations: [synced, localOnly]
        )
    }
}

struct CloudKitPrototypeView: View {
    @State private var container: ModelContainer?
    @State private var errorText: String?
    @State private var accountStatus = "provjeravam…"

    var body: some View {
        Group {
            if let container {
                CloudKitPrototypeContent(accountStatus: accountStatus)
                    .modelContainer(container)
            } else if let errorText {
                ContentUnavailableView(
                    "Baza se nije otvorila",
                    systemImage: "exclamationmark.icloud",
                    description: Text(errorText)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle("CloudKit")
        .task {
            #if PERSONAL_TEAM
            errorText = "Aplikacija je potpisana besplatnim Personal Teamom, koji ne podržava iCloud. Ovaj prototip treba plaćeni Apple Developer Program."
            accountStatus = "nije dostupno"
            return
            #endif
            do {
                container = try CloudKitPrototypeStore.makeContainer()
            } catch {
                errorText = String(describing: error)
            }
            accountStatus = await Self.loadAccountStatus()
        }
    }

    private static func loadAccountStatus() async -> String {
        do {
            let status = try await CKContainer(identifier: CloudKitPrototypeStore.containerIdentifier).accountStatus()
            switch status {
            case .available: return "iCloud dostupan"
            case .noAccount: return "Nije prijavljen u iCloud"
            case .restricted: return "iCloud ograničen"
            case .couldNotDetermine: return "Ne može se odrediti"
            case .temporarilyUnavailable: return "Privremeno nedostupan"
            @unknown default: return "Nepoznato stanje"
            }
        } catch {
            return "Greška: \(error.localizedDescription)"
        }
    }
}

private struct CloudKitPrototypeContent: View {
    let accountStatus: String

    @Environment(\.modelContext) private var context
    @Query(sort: \PrototypeSyncedItem.orderIndex) private var items: [PrototypeSyncedItem]
    @Query private var catalog: [PrototypeCatalogItem]

    var body: some View {
        List {
            Section("Stanje") {
                LabeledContent("iCloud", value: accountStatus)
                LabeledContent("Sinkronizirane stavke", value: "\(items.count)")
                LabeledContent("Lokalni katalog", value: "\(catalog.count)")
            }

            Section {
                Button("Dodaj stavku", systemImage: "plus") { addItem() }
                Button("Napuni lokalni katalog (870)", systemImage: "tray.full") { seedCatalog() }
                Button("Obriši sve", systemImage: "trash", role: .destructive) { deleteAll() }
            } footer: {
                Text("Dodaj stavke na jednom uređaju i provjeri pojave li se na drugom. Lokalni katalog ne smije se pojaviti u CloudKit konzoli.")
            }

            Section("Sinkronizirane stavke (povuci za redoslijed)") {
                ForEach(items) { item in
                    VStack(alignment: .leading) {
                        Text(item.title)
                        Text("\(item.deviceName) · #\(item.orderIndex) · \(item.createdAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            }
        }
        .toolbar { EditButton() }
    }

    private func addItem() {
        let next = (items.map(\.orderIndex).max() ?? -1) + 1
        let device = UIDevice.current.name
        context.insert(PrototypeSyncedItem(title: "Stavka \(next + 1)", orderIndex: next, deviceName: device))
        try? context.save()
    }

    private func seedCatalog() {
        guard catalog.isEmpty else { return }
        for index in 0..<870 {
            context.insert(PrototypeCatalogItem(catalogId: "proto-\(index)", name: "Vježba \(index)"))
        }
        try? context.save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() where item.orderIndex != index {
            item.orderIndex = index
        }
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
        try? context.save()
    }

    private func deleteAll() {
        try? context.delete(model: PrototypeSyncedItem.self)
        try? context.delete(model: PrototypeCatalogItem.self)
        try? context.save()
    }
}
#endif
