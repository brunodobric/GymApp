import Catalog
import Foundation
import Models
import Observation

/// Učitava službeni katalog iz bundlea i čuva ga u memoriji.
///
/// Javni dio je `Catalog/catalog.json`. MoveKit dodatak (`MoveKit/texts.json` s uputama i `MoveKit/Media/`
/// s klipovima i posterima) ulazi u build samo na Macu s licenciranim paketom (docs/movekit.md).
/// Bez njega katalog radi, samo bez uputa i animacija.
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
    private let mediaDirectory: URL?

    init(bundle: Bundle = .main) {
        language = bundle.preferredLocalizations.first == "hr" ? "hr" : "en"
        directory = bundle.resourceURL?.appendingPathComponent("Catalog")
        mediaDirectory = bundle.resourceURL?.appendingPathComponent("MoveKit")
        load()
    }

    private func load() {
        guard let directory else {
            errorText = String(localized: "Katalog nije pronađen u aplikaciji.")
            return
        }
        do {
            var loaded = try PerformanceSignpost.measure("CatalogLoad") {
                try ExerciseCatalog(data: Data(contentsOf: directory.appendingPathComponent("catalog.json")))
            }
            if let texts = loadTexts() {
                loaded = loaded.merging(texts: texts)
            }
            catalog = loaded
            summaries = loaded.summaries(language: language)
        } catch {
            errorText = String(localized: "Katalog se nije mogao učitati.")
        }
    }

    /// Upute i česte greške iz MoveKit dodatka. Nil kad dodatka nema u buildu.
    private func loadTexts() -> [String: CatalogTexts]? {
        guard let url = mediaDirectory?.appendingPathComponent("texts.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CatalogTexts.decode(data)
    }

    /// Ima li build upute iz MoveKit dodatka (bez njega detalj vježbe kaže da uputa nema).
    var hasTexts: Bool {
        guard let mediaDirectory else { return false }
        return FileManager.default.fileExists(atPath: mediaDirectory.appendingPathComponent("texts.json").path)
    }

    /// Datoteka medija iz kataloga (npr. "Media/barbell-squat.mp4") ili nil ako je nema u buildu.
    /// Mediji su u bundleu i nikad ne idu u iCloud.
    func mediaURL(_ path: String) -> URL? {
        guard let url = mediaDirectory?.appendingPathComponent(path),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func illustration(for exercise: CatalogExercise) -> ExerciseIllustration {
        exercise.illustration { mediaURL($0) != nil }
    }

    /// Sličica vježbe: poster klipa za službenu vježbu, fotografija za vlastitu.
    /// Nil kad slike nema (vježba bez postera, build bez MoveKit dodatka ili vlastita vježba bez fotografije).
    func thumbnail(for source: ExerciseSummary.Source?, customExercises: [CustomExercise]) -> ExerciseThumbnail.Source? {
        switch source {
        case .catalog(let id):
            guard let poster = catalog?.exercise(withID: id)?.poster,
                  let url = mediaURL(poster) else { return nil }
            return .file(url)
        case .custom(let id):
            guard let data = customExercises.first(where: { $0.id == id })?.imageData else { return nil }
            return .data(key: id.uuidString, data)
        case nil:
            return nil
        }
    }
}
