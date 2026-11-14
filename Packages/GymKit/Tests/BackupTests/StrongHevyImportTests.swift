import Foundation
import Testing
import Units
@testable import Backup

// Uvoz iz izvoza aplikacija Strong i Hevy. Fixturei su skraćeni izvozi s istim stupcima.

private let utc = TimeZone(identifier: "UTC")!

private func fixture(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite("Uvoz iz Stronga i Hevyja")
struct StrongHevyImportTests {

    @Test("Strong: treninzi, zagrijavanje, oprema iz naziva i vrste unosa")
    func strong() throws {
        let text = try fixture("strong.csv")
        #expect(ForeignWorkoutsCSV.matches(text))
        let workouts = try ForeignWorkoutsCSV.parse(text, timeZone: utc)
        #expect(workouts.map(\.name) == ["Push", "Legs"])
        let push = workouts[0]
        #expect(push.startedAt == Date(timeIntervalSince1970: 1_768_465_800))
        #expect(push.durationSeconds == 3900)
        #expect(push.notes == "Dobar dan")
        #expect(push.exercises.map(\.name) == ["Bench Press", "Pull Up", "Plank"])
        #expect(push.exercises[0].equipment == "Barbell")
        #expect(push.exercises[0].sets.map(\.isWarmUp) == [true, false, false])
        #expect(push.exercises[0].sets.map(\.weightKg) == [40, 80, 80])
        #expect(push.exercises[0].note == "")
        #expect(push.exercises.map(\.kind) == [.weightReps, .reps, .duration])
        #expect(push.exercises[2].sets[0].durationSeconds == 60)
        let legs = workouts[1]
        #expect(legs.durationSeconds == 2700)
        #expect(legs.exercises[1].kind == .durationDistance)
        #expect(legs.exercises[1].sets[0].distanceMeters == 5000)
    }

    @Test("Strong bez jedinice u stupcu uzima jedinicu iz postavki")
    func strongPounds() throws {
        let workouts = try ForeignWorkoutsCSV.parse(try fixture("strong.csv"), timeZone: utc, weightUnit: .pounds)
        let weight = try #require(workouts[0].exercises[0].sets[1].weightKg)
        #expect(abs(weight - 80 * 0.45359237) < 1e-9)
    }

    @Test("Hevy: trajanje iz početka i kraja, bilješke i zagrijavanje")
    func hevy() throws {
        let text = try fixture("hevy.csv")
        #expect(ForeignWorkoutsCSV.matches(text))
        let workouts = try ForeignWorkoutsCSV.parse(text, timeZone: utc)
        #expect(workouts.count == 1)
        let push = workouts[0]
        #expect(push.startedAt == Date(timeIntervalSince1970: 1_768_465_800))
        #expect(push.durationSeconds == 3900)
        #expect(push.notes == "Dobar dan")
        #expect(push.exercises.map(\.name) == ["Bench Press", "Lateral Raise"])
        #expect(push.exercises.map(\.equipment) == ["Barbell", "Dumbbell"])
        #expect(push.exercises[0].note == "Sjedalo 4")
        #expect(push.exercises[0].sets.map(\.isWarmUp) == [true, false, false])
        #expect(push.exercises[0].sets.map(\.reps) == [10, 8, 7])
        #expect(ForeignWorkoutImport.notes(for: push) == "Dobar dan\nBench Press: Sjedalo 4")
    }

    @Test("Pomoćni dijelovi: naziv s opremom i trajanje")
    func helpers() {
        #expect(StrongHevyCSV.splitName("Bench Press (Barbell)") == ("Bench Press", "Barbell"))
        #expect(StrongHevyCSV.splitName("Pull Up") == ("Pull Up", ""))
        #expect(StrongHevyCSV.parseDuration("1h 5m") == 3900)
        #expect(StrongHevyCSV.parseDuration("45m") == 2700)
        #expect(StrongHevyCSV.parseDuration("90") == 90)
        #expect(StrongHevyCSV.parseDuration("") == nil)
        #expect(!StrongHevyCSV.matches("Date;Nešto\n1;2"))
    }
}
