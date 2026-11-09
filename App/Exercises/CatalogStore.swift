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
    /// Datoteke medija u buildu ("Media/<naziv>"), pročitane jednom: sličice ne pitaju disk pri svakom crtanju.
    private let mediaFiles: Set<String>

    init(bundle: Bundle = .main) {
        language = bundle.preferredLocalizations.first == "hr" ? "hr" : "en"
        directory = bundle.resourceURL?.appendingPathComponent("Catalog")
        mediaDirectory = bundle.resourceURL?.appendingPathComponent("MoveKit")
        mediaFiles = Self.listMedia(in: mediaDirectory)
        load(bundle: bundle)
    }

    private static func listMedia(in directory: URL?) -> Set<String> {
        guard let path = directory?.appendingPathComponent("Media").path,
              let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return Set(names.map { "Media/\($0)" })
    }

    private func load(bundle: Bundle) {
        guard let directory else {
            errorText = String(localized: "Katalog nije pronađen u aplikaciji.")
            return
        }
        do {
            // Katalog iz glavnog bundlea već je dekodiran za Zdravlje, widgete i sat; ne dekodira se dvaput.
            var loaded = try PerformanceSignpost.measure("CatalogLoad") { () throws -> ExerciseCatalog in
                if bundle == .main, let shared = AppServices.bundledCatalog { return shared }
                return try ExerciseCatalog(data: Data(contentsOf: directory.appendingPathComponent("catalog.json")))
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

    /// Datoteka medija iz kataloga (npr. "Media/barbell-squat.mp4") ili nil ako je nema u buildu.
    /// Mediji su u bundleu i nikad ne idu u iCloud.
    func mediaURL(_ path: String) -> URL? {
        guard mediaFiles.contains(path) else { return nil }
        return mediaDirectory?.appendingPathComponent(path)
    }

    func illustration(for exercise: CatalogExercise) -> ExerciseIllustration {
        exercise.illustration { mediaURL($0) != nil }
    }

    /// Sličice za karticu vrste na početnoj kataloga: posteri odabranih vježbi te vrste.
    /// Prazno u buildu bez MoveKit dodatka.
    func featuredThumbnails(_ kind: ExerciseKind) -> [ExerciseThumbnail.Source] {
        guard let catalog else { return [] }
        return catalog
            .featured(kind) { exercise in exercise.poster.flatMap(mediaURL) != nil }
            .compactMap { $0.poster.flatMap(mediaURL).map(ExerciseThumbnail.Source.file) }
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
