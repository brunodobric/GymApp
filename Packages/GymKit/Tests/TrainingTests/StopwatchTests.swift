import Foundation
import Testing
@testable import Training

private let base = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Štoperica serije")
struct StopwatchTests {

    @Test("Vrijeme teče od početka, pauza ga zadržava, a nastavak dodaje")
    func pauseAndResume() {
        var watch = Stopwatch(setID: UUID(), startedAt: base)
        #expect(watch.isRunning)
        #expect(watch.elapsedSeconds(at: base.addingTimeInterval(90)) == 90)

        watch.pause(at: base.addingTimeInterval(100))
        #expect(!watch.isRunning)
        #expect(watch.elapsedSeconds(at: base.addingTimeInterval(500)) == 100)

        watch.resume(at: base.addingTimeInterval(200))
        #expect(watch.elapsedSeconds(at: base.addingTimeInterval(230)) == 130)
        #expect(watch.displayStart(at: base.addingTimeInterval(230)) == base.addingTimeInterval(100))
    }

    @Test("Prekidač mijenja stanje, a dvostruka pauza ništa ne mijenja")
    func toggle() {
        var watch = Stopwatch(setID: UUID(), startedAt: base)
        watch.toggle(at: base.addingTimeInterval(10))
        watch.pause(at: base.addingTimeInterval(50))
        #expect(watch.elapsedSeconds(at: base.addingTimeInterval(60)) == 10)
        watch.toggle(at: base.addingTimeInterval(60))
        #expect(watch.isRunning)
        #expect(watch.elapsedSeconds(at: base.addingTimeInterval(65)) == 15)
    }
}
