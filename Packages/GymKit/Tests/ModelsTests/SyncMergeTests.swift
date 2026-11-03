import Foundation
import SwiftData
import Testing
@testable import Models

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

@Suite("Sinkronizacija: duplikati i last write wins")
struct SyncMergeTests {

    @Test("Od više postavki ostaju zadnje promijenjene")
    func settingsLastWriteWins() throws {
        let context = try makeContext()
        let untouched = UserSettings()
        let older = UserSettings()
        older.defaultRestSeconds = 60
        older.modifiedAt = Date(timeIntervalSince1970: 1000)
        let newer = UserSettings()
        newer.defaultRestSeconds = 120
        newer.modifiedAt = Date(timeIntervalSince1970: 2000)
        for settings in [untouched, older, newer] { context.insert(settings) }
        try context.save()

        #expect(try GymQueries(context: context).settings().defaultRestSeconds == 120)
        #expect(try Deduplication.removeDuplicateSettings(in: context) == 2)
        let remaining = try context.fetch(FetchDescriptor<UserSettings>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.defaultRestSeconds == 120)
        #expect(try Deduplication.removeDuplicateSettings(in: context) == 0)
    }

    @Test("Bez vremena promjene prednost ima obavljen onboarding, zatim najmanji id")
    func settingsTieBreak() throws {
        let fresh = UserSettings()
        let onboarded = UserSettings()
        onboarded.onboardingCompleted = true
        #expect(UserSettings.preferred(in: [fresh, onboarded]) === onboarded)

        let first = UserSettings()
        let second = UserSettings()
        let expected = first.id.uuidString < second.id.uuidString ? first : second
        #expect(UserSettings.preferred(in: [first, second]) === expected)
        #expect(UserSettings.preferred(in: [second, first]) === expected)
        #expect(UserSettings.preferred(in: []) == nil)
    }

    @Test("Promjena postavki dobiva vrijeme, a nove zadane postavke ne")
    func stamping() throws {
        let context = try makeContext()
        let settings = UserSettings()
        context.insert(settings)
        let now = Date(timeIntervalSince1970: 5000)
        SyncStamping.stampChanges(in: context, now: now)
        try context.save()
        #expect(settings.modifiedAt == nil)

        settings.defaultRestSeconds = 150
        SyncStamping.stampChanges(in: context, now: now)
        try context.save()
        #expect(settings.modifiedAt == now)
    }

    @Test("Onboarding bilježi vrijeme promjene postavki")
    func onboardingStamps() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 7000)
        try OnboardingApplier(context: context).apply(OnboardingAnswers(), now: now)
        #expect(try GymQueries(context: context).settings().modifiedAt == now)
    }

    @Test("Ista vrsta kartice ostaje jednom, a redoslijed se zatvara")
    func dashboardCards() throws {
        let context = try makeContext()
        context.insert(DashboardCard(kindRaw: DashboardCardKind.nextWorkout.rawValue, orderIndex: 0))
        context.insert(DashboardCard(kindRaw: DashboardCardKind.weeklyVolume.rawValue, orderIndex: 1))
        context.insert(DashboardCard(kindRaw: DashboardCardKind.nextWorkout.rawValue, orderIndex: 2))
        context.insert(DashboardCard(kindRaw: "futureCard", orderIndex: 3))
        context.insert(DashboardCard(kindRaw: "futureCard", orderIndex: 4))
        try context.save()

        #expect(try Deduplication.removeDuplicateDashboardCards(in: context) == 1)
        let cards = try DashboardLayout(context: context).allCards()
        #expect(cards.map(\.kindRaw) == ["nextWorkout", "weeklyVolume", "futureCard", "futureCard"])
        #expect(cards.map(\.orderIndex) == [0, 1, 2, 3])
    }

    @Test("Sve vrste duplikata uklanjaju se jednim pozivom")
    func removeAll() throws {
        let context = try makeContext()
        context.insert(UserSettings())
        context.insert(UserSettings())
        context.insert(DashboardCard(kindRaw: DashboardCardKind.plateCalculator.rawValue, orderIndex: 0))
        context.insert(DashboardCard(kindRaw: DashboardCardKind.plateCalculator.rawValue, orderIndex: 1))
        try context.save()
        #expect(try Deduplication.removeAllDuplicates(in: context) == 2)
        #expect(try Deduplication.removeAllDuplicates(in: context) == 0)
    }
}

@Suite("Migracija sheme")
struct MigrationTests {

    @Test("Baza verzije 1 otvara se kao verzija 2 bez gubitka postavki")
    func v1ToV2() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "GymKitMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "User.store")

        do {
            let schema = Schema(versionedSchema: GymSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let settings = GymSchemaV1.UserSettings()
            settings.defaultRestSeconds = 135
            settings.onboardingCompleted = true
            context.insert(settings)
            context.insert(BodyMeasurement(kind: .weight, value: 80))
            try context.save()
        }

        let container = try GymPersistence.makeUserContainer(storage: .file(url))
        let context = ModelContext(container)
        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        #expect(settings.count == 1)
        #expect(settings.first?.defaultRestSeconds == 135)
        #expect(settings.first?.onboardingCompleted == true)
        #expect(settings.first?.modifiedAt == nil)
        #expect(try context.fetchCount(FetchDescriptor<BodyMeasurement>()) == 1)
    }
}
