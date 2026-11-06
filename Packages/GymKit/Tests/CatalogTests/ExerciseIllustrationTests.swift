import Foundation
import Testing
@testable import Catalog

/// Mali katalog u JSON-u: jedna vježba s klipom i posterom.
private func catalogJSON(media: String = #", "video": "Media/x.mp4", "poster": "Media/x.jpg""#) -> Data {
    Data("""
        {
          "version": 2,
          "source": {"name": "MoveKit", "url": "https://movekit.com", "license": "MoveKit License Agreement v1.0"},
          "legacyIds": {"Old_X": "x", "Gone": null},
          "exercises": [{
            "id": "x", "name": {"en": "X", "hr": "Iks"}, "category": "legs",
            "primaryMuscles": ["quadriceps"], "secondaryMuscles": [], "equipment": "barbell", "level": "beginner",
            "mechanic": "compound", "movement": "legs", "inputType": "weightReps",
            "primaryRegions": ["quads"], "secondaryRegions": []\(media)
          }]
        }
        """.utf8)
}

@Suite("Prikaz vježbe")
struct ExerciseIllustrationTests {

    @Test("Klip s posterom kad su obje datoteke u buildu")
    func videoWithPoster() throws {
        let exercise = try #require(ExerciseCatalog(data: catalogJSON()).exercise(withID: "x"))
        #expect(exercise.illustration { _ in true } == .video("Media/x.mp4", poster: "Media/x.jpg"))
    }

    @Test("Bez klipa ostaje poster, a bez medija nema prikaza")
    func missingMedia() throws {
        let exercise = try #require(ExerciseCatalog(data: catalogJSON()).exercise(withID: "x"))
        #expect(exercise.illustration { $0.hasSuffix(".jpg") } == .poster("Media/x.jpg"))
        #expect(exercise.illustration { $0.hasSuffix(".mp4") } == .video("Media/x.mp4", poster: nil))
        #expect(exercise.illustration { _ in false } == .unavailable)
        let none = try ExerciseCatalog(data: catalogJSON(media: ""))
        #expect(none.exercises[0].illustration { _ in true } == .unavailable)
    }

    @Test("Privatni tekstovi se spajaju s katalogom")
    func mergingTexts() throws {
        let catalog = try ExerciseCatalog(data: catalogJSON())
        #expect(catalog.exercises[0].displayInstructions(language: "hr").isEmpty)
        let texts = try CatalogTexts.decode(Data("""
            {"x": {"instructions": {"en": ["Step."], "hr": ["Korak."]}, "commonMistakes": {"en": ["Mistake."]}},
             "nepoznata": {"instructions": {}, "commonMistakes": {}}}
            """.utf8))
        let merged = catalog.merging(texts: texts)
        let exercise = try #require(merged.exercise(withID: "x"))
        #expect(exercise.displayInstructions(language: "hr") == ["Korak."])
        #expect(exercise.displayInstructions(language: "de") == ["Step."])
        #expect(exercise.displayCommonMistakes(language: "hr") == ["Mistake."])
    }

    @Test("Stari id pronalazi novu vježbu")
    func legacyLookup() throws {
        let catalog = try ExerciseCatalog(data: catalogJSON())
        #expect(catalog.exercise(withID: "Old_X")?.id == "x")
        #expect(catalog.resolve("Old_X") == .renamed("x"))
        #expect(catalog.resolve("Gone") == .removed)
        #expect(catalog.exercise(withID: "Gone") == nil)
    }

    @Test("Kodiranje i dekodiranje čuva vježbe i stare id-jeve")
    func roundTrip() throws {
        let original = try ExerciseCatalog(data: catalogJSON())
        let decoded = try ExerciseCatalog(data: JSONEncoder().encode(original))
        #expect(decoded.exercises == original.exercises)
        #expect(decoded.source == original.source)
        #expect(decoded.legacyIds == original.legacyIds)
    }
}
