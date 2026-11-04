import Foundation
import Testing
@testable import Catalog

/// Mali katalog u JSON-u: jedna vježba, s crtežima ili bez njih.
private func catalogJSON(drawings: String?, images: String = #"["Images/X/0.jpg", "Images/X/1.jpg"]"#, drawingsSource: Bool = false) -> Data {
    let drawingsField = drawings.map { #", "drawings": \#($0)"# } ?? ""
    let sourceField = drawingsSource
        ? #""drawingsSource": {"name": "Everkinetic", "repository": "everkinetic/data", "commit": "abc", "license": "CC BY-SA 4.0"},"#
        : ""
    return Data("""
        {
          "version": 1,
          "source": {"name": "free-exercise-db", "repository": "yuhonas/free-exercise-db", "commit": "abc", "license": "Unlicense"},
          \(sourceField)
          "exercises": [{
            "id": "X", "name": {"en": "X"}, "instructions": {"en": ["Korak."]}, "category": "legs",
            "primaryMuscles": ["quadriceps"], "secondaryMuscles": [], "equipment": "barbell", "level": "beginner",
            "mechanic": "compound", "movement": "legs", "inputType": "weightReps",
            "primaryRegions": ["quads"], "secondaryRegions": [], "images": \(images)\(drawingsField)
          }]
        }
        """.utf8)
}

@Suite("Crteži vježbi")
struct ExerciseIllustrationTests {

    @Test("Katalog bez polja za crteže se učitava, a vježba zadržava fotografije")
    func catalogWithoutDrawings() throws {
        let catalog = try ExerciseCatalog(data: catalogJSON(drawings: nil))
        let exercise = try #require(catalog.exercise(withID: "X"))
        #expect(catalog.drawingsSource == nil)
        #expect(exercise.drawings == nil)
        #expect(exercise.illustration == .photos(["Images/X/0.jpg", "Images/X/1.jpg"]))
    }

    @Test("Crtež ima prednost pred fotografijama: početni pa završni položaj")
    func drawingWins() throws {
        let data = catalogJSON(drawings: #"["Everkinetic-0122-start", "Everkinetic-0122-end"]"#, drawingsSource: true)
        let catalog = try ExerciseCatalog(data: data)
        let exercise = try #require(catalog.exercise(withID: "X"))
        #expect(exercise.illustration == .drawing(start: "Everkinetic-0122-start", end: "Everkinetic-0122-end"))
        #expect(catalog.drawingsSource?.license == "CC BY-SA 4.0")
    }

    @Test("Crtež bez točno dva položaja se ne koristi")
    func incompleteDrawingFallsBack() throws {
        let one = try ExerciseCatalog(data: catalogJSON(drawings: #"["Everkinetic-0122-start"]"#))
        #expect(one.exercises[0].illustration == .photos(["Images/X/0.jpg", "Images/X/1.jpg"]))
        let nothing = try ExerciseCatalog(data: catalogJSON(drawings: "[]", images: "[]"))
        #expect(nothing.exercises[0].illustration == .unavailable)
    }

    @Test("Kodiranje i dekodiranje čuva crteže i njihov izvor")
    func roundTrip() throws {
        let original = try ExerciseCatalog(data: catalogJSON(drawings: #"["A", "B"]"#, drawingsSource: true))
        let decoded = try ExerciseCatalog(data: JSONEncoder().encode(original))
        #expect(decoded.exercises == original.exercises)
        #expect(decoded.drawingsSource == original.drawingsSource)
    }
}

@Suite("Ritam animacije crteža")
struct DrawingLoopTimingTests {
    let timing = DrawingLoopTiming(hold: 1, fade: 0.5)

    @Test("Krug: početni, pretapanje, završni, pretapanje natrag")
    func cycle() {
        #expect(timing.period == 3)
        #expect(timing.endOpacity(at: 0) == 0)
        #expect(timing.endOpacity(at: 0.99) == 0)
        #expect(abs(timing.endOpacity(at: 1.25) - 0.5) < 0.0001)
        #expect(timing.endOpacity(at: 1.5) == 1)
        #expect(timing.endOpacity(at: 2.49) == 1)
        #expect(abs(timing.endOpacity(at: 2.75) - 0.5) < 0.0001)
        #expect(timing.endOpacity(at: 3) == 0)
    }

    @Test("Animacija se vrti u krug bez kraja")
    func loops() {
        for elapsed in stride(from: 0.0, to: 3.0, by: 0.1) {
            let first = timing.endOpacity(at: elapsed)
            #expect(abs(timing.endOpacity(at: elapsed + 30) - first) < 0.0001)
            #expect(abs(timing.endOpacity(at: elapsed + 3000) - first) < 0.0001)
        }
    }

    @Test("Pretapanje je glatko i uvijek između 0 i 1")
    func smoothAndBounded() {
        var previous = timing.endOpacity(at: 1)
        for step in 1...50 {
            let value = timing.endOpacity(at: 1 + Double(step) * 0.01)
            #expect(value >= previous)
            #expect((0...1).contains(value))
            previous = value
        }
        // Ease-in-out: na početku pretapanja promjena je sporija nego na sredini.
        #expect(timing.endOpacity(at: 1.05) < 0.1)
    }

    @Test("Negativno vrijeme i nulto trajanje ne ruše izračun")
    func edgeCases() {
        #expect((0...1).contains(timing.endOpacity(at: -0.4)))
        #expect(DrawingLoopTiming(hold: 0, fade: 0).endOpacity(at: 5) == 0)
        let instant = DrawingLoopTiming(hold: 1, fade: 0)
        #expect(instant.endOpacity(at: 0.5) == 0)
        #expect(instant.endOpacity(at: 1.5) == 1)
        #expect(DrawingLoopTiming(hold: -1, fade: -1).period == 0)
    }

    @Test("Standardni ritam traje nekoliko sekundi po krugu")
    func standard() {
        #expect((2...5).contains(DrawingLoopTiming.standard.period))
    }
}
