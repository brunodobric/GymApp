import Catalog
import Foundation
import Models
import SwiftData
import Testing
@testable import Backup

// Uvoz iz CSV izvoza druge aplikacije. Fixture je stvarni izvoz (53 treninga, UTF-8 s BOM-om, CRLF).

private let utc = TimeZone(identifier: "UTC")!

private func fixture() throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/workouts-druga-aplikacija.csv")
    return try String(contentsOf: url, encoding: .utf8)
}

private func bundledCatalog() throws -> ExerciseCatalog {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // BackupTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // GymKit
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // korijen repozitorija
        .appendingPathComponent("Resources/Catalog/catalog.json")
    return try ExerciseCatalog(data: Data(contentsOf: url))
}

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Vježbe iz fixturea koje nemaju par u katalogu i uvoze se kao vlastite.
private let expectedCustom: Set<String> = ["Rows with Wide Neutral Grip", "Skull Crushers with Rope"]

@Suite("Čitanje CSV-a druge aplikacije")
struct ForeignWorkoutsCSVTests {

    @Test("Fixture: svi treninzi, vježbe i serije")
    func parsesFixture() throws {
        let workouts = try ForeignWorkoutsCSV.parse(fixture(), timeZone: utc)
        #expect(workouts.count == 53)
        #expect(workouts.reduce(0) { $0 + $1.exercises.count } == 277)
        let sets = workouts.flatMap(\.exercises).flatMap(\.sets)
        #expect(sets.count == 839)
        #expect(sets.filter(\.isDone).count == 836)
        let distinct = Set(workouts.flatMap(\.exercises).map { "\($0.name)|\($0.equipment)" })
        #expect(distinct.count == 35)
    }

    @Test("Zaglavlje: naziv, detalji, datum u lokalnom vremenu i trajanje")
    func header() throws {
        let first = try #require(try ForeignWorkoutsCSV.parse(fixture(), timeZone: utc).first)
        #expect(first.title == "Push · Day 1 · Week 9 · Gym 2.0")
        #expect(first.name == "Push")
        #expect(first.details == "Day 1 · Week 9 · Gym 2.0")
        #expect(first.startedAt == utcDate(2026, 11, 2, 16, 27))
        #expect(first.durationSeconds == 53 * 60)
        #expect(first.line == 1)

        let exercise = first.exercises[0]
        #expect(exercise.name == "Incline Bench Press")
        #expect(exercise.equipment == "Dumbbells")
        #expect(exercise.kind == .weightReps)
        #expect(exercise.sets == [
            .init(weightKg: 24, reps: 10), .init(weightKg: 24, reps: 10), .init(weightKg: 24, reps: 7),
        ])
    }

    @Test("Vremenska zona pomiče trenutak, ali ne i identitet treninga")
    func timeZoneDoesNotChangeIdentity() throws {
        let zagreb = try ForeignWorkoutsCSV.parse(fixture(), timeZone: TimeZone(identifier: "Europe/Zagreb")!)
        let inUTC = try ForeignWorkoutsCSV.parse(fixture(), timeZone: utc)
        #expect(zagreb[0].startedAt == utcDate(2026, 11, 2, 15, 27))
        #expect(zagreb.map(\.stableID) == inUTC.map(\.stableID))
        #expect(Set(inUTC.map(\.stableID)).count == 53)
    }

    @Test("Trajanje: minute, sati, sati s minutama")
    func durations() {
        #expect(ForeignWorkoutsCSV.parseDuration("53 min") == 3180)
        #expect(ForeignWorkoutsCSV.parseDuration("1 hr") == 3600)
        #expect(ForeignWorkoutsCSV.parseDuration("1:17 hr") == 4620)
        #expect(ForeignWorkoutsCSV.parseDuration("1 hr 5 min") == 3900)
        #expect(ForeignWorkoutsCSV.parseDuration("45 sec") == 45)
        #expect(ForeignWorkoutsCSV.parseDuration("dugo") == nil)
    }

    @Test("Datum: 12-satni i 24-satni zapis, neispravan datum se odbija")
    func dates() {
        #expect(ForeignWorkoutsCSV.parseDate("2026-11-02 12:05 am", timeZone: utc) == utcDate(2026, 11, 2, 0, 5))
        #expect(ForeignWorkoutsCSV.parseDate("2026-11-02 12:05 pm", timeZone: utc) == utcDate(2026, 11, 2, 12, 5))
        #expect(ForeignWorkoutsCSV.parseDate("2026-11-02 16:27", timeZone: utc) == utcDate(2026, 11, 2, 16, 27))
        #expect(ForeignWorkoutsCSV.parseDate("2026-02-30 4:00 pm", timeZone: utc) == nil)
        #expect(ForeignWorkoutsCSV.parseDate("53 min", timeZone: utc) == nil)
    }

    @Test("Vlastita težina + teret, prazne serije i trajanje u minutama")
    func specialValues() throws {
        let workouts = try ForeignWorkoutsCSV.parse(fixture(), timeZone: utc)
        let exercises = workouts.flatMap(\.exercises)

        let calves = try #require(exercises.last { $0.name == "Standing Calf Raises" })
        #expect(calves.kind == .weightedBodyweight)
        #expect(calves.sets.map(\.extraWeightKg) == [0, 8, 12, 12])
        #expect(calves.sets.allSatisfy { $0.weightKg == nil && $0.reps == 10 })

        let empty = try #require(exercises.first { $0.line == 1018 })
        #expect(empty.name == "High Cable Flys")
        #expect(empty.sets.count == 3 && empty.sets.allSatisfy { !$0.isDone })

        let plank = try #require(exercises.first { $0.name == "Plank" })
        #expect(plank.kind == .duration)
        #expect(plank.sets.map(\.durationSeconds) == [60, 60])
    }

    @Test("Kratka datoteka bez BOM-a, s LF i decimalnim teretom")
    func inlineText() throws {
        let text = """
            "Leđa · Day 2 · Week 1 · Plan";"2025-01-05 9:00 am";"1 hr"
            "1. Pull-Ups · Bodyweight · 8 reps"
            #;KG;REPS
            1;+12.5;8
            2;+12.5;-

            "Noge";"2025-01-07 6:30 pm";"40 min"
            "1. Squats · Barbell"
            #;KG;REPS
            1;100;5
            """
        let workouts = try ForeignWorkoutsCSV.parse(text, timeZone: utc)
        #expect(workouts.map(\.name) == ["Leđa", "Noge"])
        #expect(workouts[1].details.isEmpty)
        #expect(workouts[0].exercises[0].sets == [.init(extraWeightKg: 12.5, reps: 8), .init(extraWeightKg: 12.5)])
        #expect(workouts[1].exercises[0].equipment == "Barbell")
    }

    @Test("Neispravan redak javlja broj retka")
    func invalidLine() {
        let text = "\"Push · Day 1\";\"2026-11-02 4:27 pm\";\"53 min\"\n\"1. Bench Press · Barbell\"\n#;KG;REPS\n1;abc;10\n"
        #expect(throws: BackupError.invalidCSV(line: 4)) { try ForeignWorkoutsCSV.parse(text) }
        #expect(throws: BackupError.invalidCSV(line: 1)) { try ForeignWorkoutsCSV.parse("1;24;10\n") }
        let unknownColumn = "\"Push\";\"2026-11-02 4:27 pm\";\"53 min\"\n\"1. Row · Machine\"\n#;WATTS\n"
        #expect(throws: BackupError.invalidCSV(line: 3)) { try ForeignWorkoutsCSV.parse(unknownColumn) }
    }

    @Test("Beskonačna ili ogromna vrijednost se odbija umjesto da sruši uvoz", arguments: [
        "#;KG;REPS\n1;inf;10\n", "#;KG;REPS\n1;nan;10\n", "#;MINS\n1;inf\n", "#;SECS\n1;nan\n",
        "#;MINS\n1;99999999999999:30\n", "#;KM\n1;inf\n",
    ])
    func nonFiniteValues(_ table: String) {
        let text = "\"Push · Day 1\";\"2026-11-02 4:27 pm\";\"53 min\"\n\"1. Bench Press · Barbell\"\n" + table
        #expect(throws: BackupError.invalidCSV(line: 4)) { try ForeignWorkoutsCSV.parse(text) }
    }

    @Test("Prepoznaje format, a vlastiti CSV ne")
    func detection() throws {
        #expect(ForeignWorkoutsCSV.matches(try fixture()))
        #expect(!ForeignWorkoutsCSV.matches(CSV.line(CSVBackup.historyColumns)))
        #expect(!ForeignWorkoutsCSV.matches(""))
    }
}

@Suite("Povezivanje vježbi s katalogom")
struct ForeignExerciseMatcherTests {

    @Test("Svaki poznati naziv upućuje na vježbu koja postoji u katalogu")
    func knownNamesExist() throws {
        let catalog = try bundledCatalog()
        for entry in ForeignExerciseMatcher.knownNames {
            #expect(catalog.exercise(withID: entry.catalogId) != nil, "\(entry.name): nema \(entry.catalogId)")
        }
    }

    @Test("Vježbe iz fixturea: 33 iz kataloga, 2 vlastite")
    func fixtureExercises() throws {
        let catalog = try bundledCatalog()
        let exercises = try ForeignWorkoutsCSV.parse(fixture(), timeZone: utc).flatMap(\.exercises)
        var matched: [String: String] = [:]
        var custom = Set<String>()
        for exercise in exercises {
            if let id = ForeignExerciseMatcher.catalogId(name: exercise.name, equipment: exercise.equipment, catalog: catalog) {
                matched[exercise.name] = id
            } else {
                custom.insert(exercise.name)
            }
        }
        #expect(custom == expectedCustom)
        #expect(Set(matched.keys).count == 33)
        #expect(matched["Side Plank"] == "elbow-side-plank")
        #expect(matched["Incline Chest Press"] == "incline-machine-chest-press")
        #expect(matched["Standing Calf Raises"] == "standing-calf-raise-machine")
        #expect(matched["Incline Bench Press"] == "dumbbell-incline-bench-press")
        #expect(matched["Squats"] == "barbell-squat")
        #expect(matched["Lat Pulldowns with Close Neutral Grip"] == "neutral-grip-lat-pulldown")
        #expect(matched["Plank"] == "front-plank")
    }

    @Test("Isti naziv uz drugu opremu nije ista vježba")
    func equipmentMatters() throws {
        let catalog = try bundledCatalog()
        #expect(ForeignExerciseMatcher.catalogId(name: "Leg Extensions", equipment: "Machine", catalog: catalog) == "machine-leg-extension")
        #expect(ForeignExerciseMatcher.catalogId(name: "Standing Calf Raises", equipment: "Machine", catalog: catalog) == "standing-calf-raise-machine")
        #expect(ForeignExerciseMatcher.catalogId(name: "Rows with Wide Neutral Grip", equipment: "Resistance bands", catalog: catalog) == nil)
        #expect(ForeignExerciseMatcher.catalogId(name: "Leg Extensions", equipment: "Dumbbells", catalog: catalog) == nil)
        #expect(ForeignExerciseMatcher.equipment(from: "EZ bar") == .ezBar)
        #expect(ForeignExerciseMatcher.equipment(from: "Resistance bands") == .bands)
    }
}

@Suite("Uvoz treninga iz druge aplikacije")
struct ForeignWorkoutImportTests {

    @Test("Pregled prije uvoza ne mijenja bazu")
    func preview() throws {
        let context = try makeContext()
        let preview = try ForeignWorkoutImport.preview(
            fixture(), catalog: bundledCatalog(), language: "hr", context: context, timeZone: utc
        )
        #expect(preview.newWorkouts.count == 53)
        #expect(preview.alreadyImported == 0)
        #expect(preview.exercises.count == 35)
        #expect(preview.newCustomCount == 2)
        #expect(preview.setCount == 836)
        #expect(preview.firstDate == utcDate(2023, 3, 16, 17, 47))
        #expect(preview.lastDate == utcDate(2026, 11, 2, 16, 27))
        let bench = try #require(preview.exercises.first { $0.sourceName == "Incline Bench Press" })
        #expect(bench.target == .catalog(id: "dumbbell-incline-bench-press", name: "Potisak bučicama s kose klupe"))
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CustomExercise>()) == 0)
    }

    @Test("Uvoz sprema treninge, serije i vlastite vježbe")
    func importsFixture() throws {
        let context = try makeContext()
        let catalog = try bundledCatalog()
        let preview = try ForeignWorkoutImport.preview(fixture(), catalog: catalog, language: "hr", context: context, timeZone: utc)
        let result = try ForeignWorkoutImport.apply(preview, into: context)
        #expect(result == BackupImportResult(added: 53, skipped: 0))

        let sessions = try context.fetch(FetchDescriptor<Session>())
        #expect(sessions.count == 53)
        #expect(sessions.allSatisfy { $0.state == .finished && $0.endedAt != nil })
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 836)
        #expect(try context.fetchCount(FetchDescriptor<SessionExercise>()) == 276)
        let customs = try context.fetch(FetchDescriptor<CustomExercise>())
        #expect(Set(customs.map(\.name)) == expectedCustom)

        let push = try #require(sessions.first { $0.startedAt == utcDate(2026, 11, 2, 16, 27) })
        #expect(push.name == "Push")
        #expect(push.notes == "Day 1 · Week 9 · Gym 2.0")
        #expect(push.endedAt == utcDate(2026, 11, 2, 17, 20))
        let exercises = push.orderedExercises
        #expect(exercises.map(\.exerciseKey) == [
            "c:dumbbell-incline-bench-press", "c:dumbbell-seated-overhead-press", "c:dumbbell-lateral-raise", "c:cable-bar-pushdown", "c:cable-high-to-low-fly",
        ])
        let sets = exercises.flatMap(\.orderedSets)
        let volume = sets.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
        #expect(volume == 3514)
        // Serije su odrađene (statistika broji samo njih) i redom unutar trajanja treninga.
        let times = sets.compactMap(\.completedAt)
        #expect(times.count == sets.count)
        #expect(times == times.sorted())
        #expect(times.allSatisfy { $0 > push.startedAt && $0 <= push.endedAt! })

        let calves = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.exerciseKey == "c:standing-calf-raise-machine" }
        #expect(calves.allSatisfy { $0.inputType == .weightedBodyweight })
        #expect(calves.contains { $0.orderedSets.map(\.extraWeightKg) == [0, 8, 12, 12] })
        #expect(calves.count == 4)
    }

    @Test("Ponovni uvoz iste datoteke ne stvara duplikate")
    func reimportSkipsEverything() throws {
        let context = try makeContext()
        let catalog = try bundledCatalog()
        let text = try fixture()
        try ForeignWorkoutImport.apply(
            ForeignWorkoutImport.preview(text, catalog: catalog, language: "hr", context: context, timeZone: utc), into: context
        )
        let again = try ForeignWorkoutImport.preview(text, catalog: catalog, language: "hr", context: context, timeZone: utc)
        #expect(again.newWorkouts.isEmpty)
        #expect(again.alreadyImported == 53)
        #expect(try ForeignWorkoutImport.apply(again, into: context) == BackupImportResult(added: 0, skipped: 53))
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 53)
        #expect(try context.fetchCount(FetchDescriptor<CustomExercise>()) == 2)

        // Novija datoteka s jednim novim treningom na vrhu dodaje samo njega, i to u drugoj vremenskoj zoni.
        let newer = """
            "Pull · Day 2 · Week 9 · Gym 2.0";"2026-11-04 4:10 pm";"50 min"
            "1. Rows with Wide Neutral Grip · Resistance bands · 10 reps"
            #;KG;REPS
            1;14;10

            """ + text
        let zagreb = TimeZone(identifier: "Europe/Zagreb")!
        let update = try ForeignWorkoutImport.preview(newer, catalog: catalog, language: "hr", context: context, timeZone: zagreb)
        #expect(update.newWorkouts.count == 1 && update.alreadyImported == 53)
        #expect(update.exercises.map(\.target.isNewCustom) == [false], "postojeća vlastita vježba se ponovno koristi")
        try ForeignWorkoutImport.apply(update, into: context)
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 54)
        #expect(try context.fetchCount(FetchDescriptor<CustomExercise>()) == 2)
    }

    @Test("Trening koji se u datoteci ponavlja uvozi se jednom")
    func duplicateInsideFile() throws {
        let context = try makeContext()
        let block = """
            "Push";"2026-11-02 4:27 pm";"53 min"
            "1. Bench Press · Barbell · 10 reps"
            #;KG;REPS
            1;80;10

            """
        let preview = try ForeignWorkoutImport.preview(
            block + block, catalog: bundledCatalog(), language: "en", context: context, timeZone: utc
        )
        #expect(preview.newWorkouts.count == 1 && preview.alreadyImported == 1)
        #expect(preview.exercises.first?.target == .catalog(id: "barbell-bench-press", name: "Barbell Bench Press"))
    }

    @Test("Postojeća vlastita vježba istog naziva se koristi umjesto nove")
    func reusesExistingCustom() throws {
        let context = try makeContext()
        let mine = CustomExercise(name: "rows with wide neutral grip")
        context.insert(mine)
        try context.save()
        let preview = try ForeignWorkoutImport.preview(
            fixture(), catalog: bundledCatalog(), language: "hr", context: context, timeZone: utc
        )
        let rows = try #require(preview.exercises.first { $0.sourceName == "Rows with Wide Neutral Grip" })
        #expect(rows.target == .existingCustom(id: mine.id, name: "rows with wide neutral grip"))
        // Druga vježba bez para u katalogu (Skull Crushers with Rope) je i dalje nova.
        #expect(preview.newCustomCount == 1)
        try ForeignWorkoutImport.apply(preview, into: context)
        #expect(try context.fetchCount(FetchDescriptor<CustomExercise>()) == 2)
    }
}
