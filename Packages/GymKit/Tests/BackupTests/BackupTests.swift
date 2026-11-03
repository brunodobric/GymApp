import Catalog
import Foundation
import Models
import SwiftData
import Testing
@testable import Backup

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let exportTime = Date(timeIntervalSince1970: 1_810_000_000)

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

/// Po jedan zapis svake vrste, s neobičnim vrijednostima (zarez, navodnici, novi redak, nedostajuća polja).
@discardableResult
private func fillSample(_ context: ModelContext) throws -> UUID {
    let settings = try GymQueries(context: context).settings()
    settings.weightUnit = .pounds
    settings.defaultRestSeconds = 120
    settings.goal = .strength
    settings.experience = .intermediate
    settings.equipment = [.barbell, .dumbbell]
    settings.trainingDaysPerWeek = 4
    settings.onboardingCompleted = true
    settings.wantsHealthKit = true
    settings.notificationsEnabled = false
    settings.bodyMapFemale = true
    settings.availablePlatesKg = [1.25, 2.5, 20]

    let custom = CustomExercise(name: "Moja \"vježba\", s zarezom")
    custom.details = "Prvi red\nDrugi red"
    custom.muscles = [.chest, .triceps]
    custom.imageData = Data([1, 2, 3, 4])
    context.insert(custom)

    let template = WorkoutTemplate(name: "Push")
    context.insert(template)
    let templateExercise = TemplateExercise(
        orderIndex: 0, exercise: ExerciseRef(catalogId: "bench", name: "Potisak s klupe")
    )
    templateExercise.restSeconds = 150
    templateExercise.notes = "Pauza na prsima"
    templateExercise.supersetGroupId = UUID()
    context.insert(templateExercise)
    templateExercise.template = template
    let templateSet = TemplateSet(orderIndex: 0, targetWeightKg: 80, targetReps: 5)
    context.insert(templateSet)
    templateSet.exercise = templateExercise

    let schedule = Schedule(name: "Tjedni")
    schedule.cycleCount = 4
    schedule.weekdays = [2, 4, 6]
    schedule.reminderMinutes = 18 * 60
    schedule.isActive = true
    schedule.currentPosition = 1
    context.insert(schedule)
    let workoutItem = ScheduleItem(orderIndex: 0, kind: .workout, workoutTemplateId: template.id)
    let restItem = ScheduleItem(orderIndex: 1, kind: .restDay)
    for item in [workoutItem, restItem] {
        context.insert(item)
        item.schedule = schedule
    }
    let change = CycleOverride(scheduleId: schedule.id, cycleNumber: 1, scheduleItemId: workoutItem.id, kind: .replaceExercise)
    change.targetExerciseKey = "c:bench"
    change.replacement = ExerciseRef(catalogId: "incline", name: "Kosi potisak")
    change.replacementInputType = .weightReps
    context.insert(change)

    let session = Session(name: "Push, \"A\"", startedAt: start)
    session.state = .finished
    session.endedAt = start.addingTimeInterval(3600)
    session.notes = "Dobar trening,\nlagani kraj"
    session.averageHeartRate = 131.5
    session.templateId = template.id
    context.insert(session)
    let benchEntry = SessionExercise(orderIndex: 0, exercise: ExerciseRef(catalogId: "bench", name: "Potisak s klupe"))
    benchEntry.restSeconds = 120
    context.insert(benchEntry)
    benchEntry.session = session
    for (index, reps) in [8, 6].enumerated() {
        let set = SetLog(orderIndex: index, kind: index == 0 ? .warmUp : .working)
        set.weightKg = 60 + Double(index) * 22.5
        set.reps = reps
        set.rpe = 8.5
        set.completedAt = start.addingTimeInterval(600 + Double(index) * 180)
        context.insert(set)
        set.exercise = benchEntry
    }
    let cardio = SessionExercise(orderIndex: 1, exercise: ExerciseRef(customExerciseId: custom.id, name: custom.name), inputType: .durationDistance)
    context.insert(cardio)
    cardio.session = session
    let run = SetLog(orderIndex: 0)
    run.durationSeconds = 1500
    run.distanceMeters = 5000.5
    run.completedAt = start.addingTimeInterval(3000)
    context.insert(run)
    run.exercise = cardio
    let emptyExercise = SessionExercise(orderIndex: 2, exercise: ExerciseRef(catalogId: "plank", name: "Plank"))
    context.insert(emptyExercise)
    emptyExercise.session = session

    let weight = BodyMeasurement(kind: .weight, value: 82.4, date: start)
    context.insert(weight)
    let custom2 = BodyMeasurement(kind: .custom, value: 36.5, date: start.addingTimeInterval(86_400))
    custom2.customName = "Bicepsi, lijevi"
    custom2.source = .healthKit
    context.insert(custom2)
    context.insert(DashboardCard(kindRaw: "plateCalculator", orderIndex: 0))

    // Ne smiju u izvoz.
    let active = Session(name: "U tijeku", startedAt: start.addingTimeInterval(7200))
    context.insert(active)
    let discarded = Session(name: "Odbačen", startedAt: start.addingTimeInterval(9000))
    discarded.state = .discarded
    context.insert(discarded)

    try context.save()
    return session.id
}

@Suite("JSON sigurnosna kopija")
struct JSONBackupTests {

    @Test("Export pa import na čistoj bazi vraća identične podatke")
    func roundTrip() throws {
        let source = try makeContext()
        try fillSample(source)
        let first = try JSONBackup.export(from: source, now: exportTime)

        let target = try makeContext()
        let result = try JSONBackup.importBackup(first, into: target)
        let second = try JSONBackup.export(from: target, now: exportTime)

        #expect(first == second)
        #expect(result.added == 8 && result.skipped == 0)
        let session = try #require(try target.fetch(FetchDescriptor<Session>()).first)
        #expect(session.orderedExercises.count == 3)
        #expect(session.orderedExercises[0].orderedSets.count == 2)
        #expect(try GymQueries(context: target).settings().weightUnit == .pounds)
        #expect(try GymQueries(context: target).settings().bodyMapFemale)
    }

    @Test("Trening u tijeku i odbačeni se ne izvoze")
    func onlyFinishedSessions() throws {
        let context = try makeContext()
        try fillSample(context)
        let data = try JSONBackup.export(from: context, now: exportTime)
        let target = try makeContext()
        try JSONBackup.importBackup(data, into: target)
        let names = try target.fetch(FetchDescriptor<Session>()).map(\.name)
        #expect(names == ["Push, \"A\""])
    }

    @Test("Ponovni uvoz ne udvostručuje podatke")
    func importIsIdempotent() throws {
        let source = try makeContext()
        try fillSample(source)
        let data = try JSONBackup.export(from: source, now: exportTime)
        let again = try JSONBackup.importBackup(data, into: source)
        #expect(again.added == 0 && again.skipped == 8)
        #expect(try source.fetch(FetchDescriptor<Session>()).count == 3)
        #expect(try source.fetch(FetchDescriptor<SetLog>()).count == 3)
        #expect(try source.fetch(FetchDescriptor<UserSettings>()).count == 1)
    }

    @Test("Tuđa ili novija datoteka se odbija")
    func rejectsUnknownFiles() throws {
        let context = try makeContext()
        #expect(throws: BackupError.unsupportedFormat) {
            try JSONBackup.importBackup(Data("{}".utf8), into: context)
        }
        #expect(throws: BackupError.unsupportedFormat) {
            try JSONBackup.importBackup(Data("nije json".utf8), into: context)
        }
        let source = try makeContext()
        let data = try JSONBackup.export(from: source, now: exportTime)
        let newer = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 9")
        #expect(throws: BackupError.newerVersion(9)) {
            try JSONBackup.importBackup(Data(newer.utf8), into: context)
        }
    }
}

@Suite("CSV sigurnosna kopija")
struct CSVBackupTests {

    @Test("Povijest: export pa import vraća identičan CSV")
    func historyRoundTrip() throws {
        let source = try makeContext()
        try fillSample(source)
        let first = try CSVBackup.exportHistory(from: source)

        let target = try makeContext()
        let result = try CSVBackup.importHistory(first, into: target)
        let second = try CSVBackup.exportHistory(from: target)

        #expect(first == second)
        #expect(result == BackupImportResult(added: 1, skipped: 0))
        let session = try #require(try target.fetch(FetchDescriptor<Session>()).first)
        #expect(session.name == "Push, \"A\"")
        #expect(session.notes == "Dobar trening,\nlagani kraj")
        #expect(session.state == .finished)
        #expect(session.orderedExercises.map(\.orderedSets.count) == [2, 1, 0])
        #expect(session.orderedExercises[1].exerciseCustomId != nil)
        #expect(session.orderedExercises[0].orderedSets[1].weightKg == 82.5)
    }

    @Test("Povijest: ponovni uvoz preskače postojeće treninge")
    func historyImportIsIdempotent() throws {
        let context = try makeContext()
        try fillSample(context)
        let csv = try CSVBackup.exportHistory(from: context)
        let result = try CSVBackup.importHistory(csv, into: context)
        #expect(result == BackupImportResult(added: 0, skipped: 1))
        #expect(try context.fetch(FetchDescriptor<Session>()).count == 3)
    }

    @Test("Povijest: neispravan redak odbija cijeli uvoz")
    func invalidHistoryChangesNothing() throws {
        let source = try makeContext()
        try fillSample(source)
        let lines = try CSVBackup.exportHistory(from: source).split(separator: "\n", omittingEmptySubsequences: true)
        let header = String(lines[0])
        #expect(throws: BackupError.invalidCSV(line: 1)) {
            try CSVBackup.importHistory("a,b,c\n1,2,3\n", into: try makeContext())
        }
        let target = try makeContext()
        let broken = header + "\n" + UUID().uuidString + ",Ime,strength,nije datum" + String(repeating: ",", count: 17) + "\n"
        #expect(throws: BackupError.invalidCSV(line: 2)) {
            try CSVBackup.importHistory(broken, into: target)
        }
        #expect(try target.fetch(FetchDescriptor<Session>()).isEmpty)

        // Neispravan broj u redku serije, nakon ispravnog treninga: ništa se ne sprema.
        let good = UUID().uuidString
        let row = [good, "A", "strength", "2027-01-15T08:00:00.000Z", "", "", "0", "c:bench", "Bench", "weightReps", "", "",
                   "0", "working", "abc", "", "", "", "", "", ""].joined(separator: ",")
        #expect(throws: BackupError.invalidCSV(line: 2)) {
            try CSVBackup.importHistory(header + "\n" + row + "\n", into: target)
        }
        #expect(try target.fetch(FetchDescriptor<Session>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
    }

    @Test("Mjerenja: export pa import vraća identičan CSV")
    func bodyRoundTrip() throws {
        let source = try makeContext()
        try fillSample(source)
        let first = try CSVBackup.exportBody(from: source)
        let target = try makeContext()
        let result = try CSVBackup.importBody(first, into: target)
        #expect(result == BackupImportResult(added: 2, skipped: 0))
        #expect(try CSVBackup.exportBody(from: target) == first)
        let custom = try target.fetch(FetchDescriptor<BodyMeasurement>()).first { $0.kind == .custom }
        #expect(custom?.customName == "Bicepsi, lijevi" && custom?.source == .healthKit)
    }

    @Test("importAny prepoznaje vrstu CSV-a po zaglavlju")
    func importAnyDetectsKind() throws {
        let source = try makeContext()
        try fillSample(source)
        let history = try CSVBackup.exportHistory(from: source)
        let body = try CSVBackup.exportBody(from: source)
        let target = try makeContext()
        #expect(try CSVBackup.importAny(history, into: target) == BackupImportResult(added: 1, skipped: 0))
        #expect(try CSVBackup.importAny(body, into: target) == BackupImportResult(added: 2, skipped: 0))
        #expect(throws: BackupError.invalidCSV(line: 1)) {
            try CSVBackup.importAny("x,y\n1,2\n", into: target)
        }
    }

    @Test("CSV parser: navodnici, zarezi, novi redovi i CRLF")
    func parser() {
        let rows = CSV.parse("a,\"b,\"\"c\"\"\nd\",e\r\n1,,3\r\n")
        #expect(rows == [["a", "b,\"c\"\nd", "e"], ["1", "", "3"]])
        #expect(CSV.parse("").isEmpty)
        #expect(CSV.line(["x", "y,z", "q\"r"]) == "x,\"y,z\",\"q\"\"r\"")
    }
}

@Suite("Brisanje svih podataka")
struct DataResetTests {

    @Test("Briše sve zapise i djecu, a postavke se vraćaju na zadane")
    func deletesEverything() throws {
        let context = try makeContext()
        try fillSample(context)
        try DataReset.deleteAll(in: context)

        #expect(try context.fetch(FetchDescriptor<Session>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateSet>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Schedule>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ScheduleItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CycleOverride>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CustomExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DashboardCard>()).isEmpty)
        let settings = try GymQueries(context: context).settings()
        #expect(settings.weightUnit == .kilograms && !settings.onboardingCompleted)
    }
}
