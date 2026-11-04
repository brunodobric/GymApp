import Catalog
import Foundation
import Observation

/// Učitava službeni katalog iz bundlea (`Catalog/catalog.json`) i čuva ga u memoriji.
@MainActor
@Observable
final class CatalogStore {
    private(set) var catalog: ExerciseCatalog?
    private(set) var summaries: [ExerciseSummary] = []
    private(set) var errorText: String?

    /// Jezik za nazive i upute vježbi: "hr" ili "en". Prati jezik sučelja aplikacije
    /// (ne regiju uređaja), da katalog i ostatak aplikacije uvijek budu na istom jeziku.
    let language: String

    private let directory: URL?

    init(bundle: Bundle = .main) {
        language = bundle.preferredLocalizations.first == "hr" ? "hr" : "en"
        directory = bundle.resourceURL?.appendingPathComponent("Catalog")
        load()
    }

    private func load() {
        guard let directory else {
            errorText = String(localized: "Katalog nije pronađen u aplikaciji.")
            return
        }
        do {
            let loaded = try PerformanceSignpost.measure("CatalogLoad") {
                try ExerciseCatalog(data: Data(contentsOf: directory.appendingPathComponent("catalog.json")))
            }
            catalog = loaded
            summaries = loaded.summaries(language: language)
        } catch {
            errorText = String(localized: "Katalog se nije mogao učitati.")
        }
    }

    /// Slike su u bundleu i nikad ne idu u iCloud. `path` je putanja iz kataloga, npr. "Images/Pushups/0.jpg".
    func imageURL(_ path: String) -> URL {
        (directory ?? Bundle.main.bundleURL).appendingPathComponent(path)
    }

    /// Sličica službene vježbe u mreži kataloga: prva fotografija (početni položaj).
    func thumbnail(for summary: ExerciseSummary) -> ExerciseThumbnail.Source? {
        guard case .catalog(let id) = summary.source,
              let exercise = catalog?.exercise(withID: id),
              let first = exercise.images.first,
              let directory else { return nil }
        return .file(directory.appendingPathComponent(first))
    }
}
