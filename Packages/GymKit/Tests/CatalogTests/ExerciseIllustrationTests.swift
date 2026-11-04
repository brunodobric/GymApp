import Foundation
import Testing
@testable import Catalog

/// Mali katalog u JSON-u: jedna vježba sa zadanim slikama.
private func catalogJSON(images: String = #"["Images/X/0.jpg", "Images/X/1.jpg"]"#, extraFields: String = "") -> Data {
    Data("""
        {
          "version": 1,
          "source": {"name": "free-exercise-db", "repository": "yuhonas/free-exercise-db", "commit": "abc", "license": "Unlicense"},
          "exercises": [{
            "id": "X", "name": {"en": "X"}, "instructions": {"en": ["Korak."]}, "category": "legs",
            "primaryMuscles": ["quadriceps"], "secondaryMuscles": [], "equipment": "barbell", "level": "beginner",
            "mechanic": "compound", "movement": "legs", "inputType": "weightReps",
            "primaryRegions": ["quads"], "secondaryRegions": [], "images": \(images)\(extraFields)
          }]
        }
        """.utf8)
}

@Suite("Prikaz vježbe")
struct ExerciseIllustrationTests {

    @Test("Dvije fotografije čine animaciju: početni pa završni položaj")
    func twoPhotosAnimate() throws {
        let catalog = try ExerciseCatalog(data: catalogJSON())
        let exercise = try #require(catalog.exercise(withID: "X"))
        #expect(exercise.illustration == .animation(start: "Images/X/0.jpg", end: "Images/X/1.jpg"))
    }

    @Test("Jedna fotografija stoji mirno, a bez fotografija nema prikaza")
    func fewerPhotos() throws {
        let one = try ExerciseCatalog(data: catalogJSON(images: #"["Images/X/0.jpg"]"#))
        #expect(one.exercises[0].illustration == .photo("Images/X/0.jpg"))
        let none = try ExerciseCatalog(data: catalogJSON(images: "[]"))
        #expect(none.exercises[0].illustration == .unavailable)
    }

    @Test("Animaciju čine prve dvije fotografije kad ih ima više")
    func morePhotos() throws {
        let catalog = try ExerciseCatalog(data: catalogJSON(images: #"["A.jpg", "B.jpg", "C.jpg"]"#))
        #expect(catalog.exercises[0].illustration == .animation(start: "A.jpg", end: "B.jpg"))
    }

    @Test("Stari katalog s poljem za crteže i dalje se učitava")
    func legacyDrawingsFieldIgnored() throws {
        let catalog = try ExerciseCatalog(data: catalogJSON(extraFields: #", "drawings": ["Everkinetic-0122-start", "Everkinetic-0122-end"]"#))
        #expect(catalog.exercises[0].illustration == .animation(start: "Images/X/0.jpg", end: "Images/X/1.jpg"))
    }

    @Test("Kodiranje i dekodiranje čuva vježbe")
    func roundTrip() throws {
        let original = try ExerciseCatalog(data: catalogJSON())
        let decoded = try ExerciseCatalog(data: JSONEncoder().encode(original))
        #expect(decoded.exercises == original.exercises)
        #expect(decoded.source == original.source)
    }
}

@Suite("Ritam animacije")
struct PoseLoopTimingTests {
    let timing = PoseLoopTiming(hold: 1, fade: 0.5)

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
        #expect(PoseLoopTiming(hold: 0, fade: 0).endOpacity(at: 5) == 0)
        let instant = PoseLoopTiming(hold: 1, fade: 0)
        #expect(instant.endOpacity(at: 0.5) == 0)
        #expect(instant.endOpacity(at: 1.5) == 1)
        #expect(PoseLoopTiming(hold: -1, fade: -1).period == 0)
    }

    @Test("Standardni ritam traje nekoliko sekundi po krugu")
    func standard() {
        #expect((2...5).contains(PoseLoopTiming.standard.period))
    }
}

@Suite("Sat animacije s pauzom")
struct PoseLoopClockTests {
    let origin = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("Novi sat stoji na nuli dok se ne pokrene")
    func startsStopped() {
        let clock = PoseLoopClock()
        #expect(!clock.isRunning)
        #expect(clock.elapsed(at: origin.addingTimeInterval(10)) == 0)
    }

    @Test("Pauza zadrži položaj, a nastavak teče od njega")
    func pauseAndResume() {
        var clock = PoseLoopClock()
        clock.start(at: origin)
        #expect(clock.elapsed(at: origin.addingTimeInterval(2)) == 2)
        clock.pause(at: origin.addingTimeInterval(2))
        #expect(!clock.isRunning)
        #expect(clock.elapsed(at: origin.addingTimeInterval(50)) == 2)
        clock.start(at: origin.addingTimeInterval(50))
        #expect(clock.elapsed(at: origin.addingTimeInterval(51.5)) == 3.5)
    }

    @Test("Ponovljeni start ili pauza ne mijenjaju vrijeme")
    func idempotent() {
        var clock = PoseLoopClock()
        clock.start(at: origin)
        clock.start(at: origin.addingTimeInterval(5))
        #expect(clock.elapsed(at: origin.addingTimeInterval(6)) == 6)
        clock.pause(at: origin.addingTimeInterval(6))
        clock.pause(at: origin.addingTimeInterval(9))
        #expect(clock.elapsed(at: origin.addingTimeInterval(9)) == 6)
    }

    @Test("Sat ne ide unatrag kad je datum prije pokretanja")
    func neverNegative() {
        var clock = PoseLoopClock()
        clock.start(at: origin)
        #expect(clock.elapsed(at: origin.addingTimeInterval(-3)) == 0)
    }
}
