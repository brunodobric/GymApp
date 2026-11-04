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
            let data = try Data(contentsOf: directory.appendingPathComponent("catalog.json"))
            let loaded = try ExerciseCatalog(data: data)
            catalog = loaded
            summaries = loaded.summaries(language: language)
        } catch {
            errorText = String(localized: "Katalog se nije mogao učitati.")
        }
    }

    /// Slike su u bundleu i nikad ne idu u iCloud.
    func imageURLs(for exercise: CatalogExercise) -> [URL] {
        guard let directory else { return [] }
        return exercise.images.map { directory.appendingPathComponent($0) }
    }

    /// Prva slika službene vježbe, za sličicu u mreži kataloga.
    func thumbnailURL(for summary: ExerciseSummary) -> URL? {
        guard case .catalog(let id) = summary.source,
              let first = catalog?.exercise(withID: id)?.images.first,
              let directory else { return nil }
        return directory.appendingPathComponent(first)
    }
}
