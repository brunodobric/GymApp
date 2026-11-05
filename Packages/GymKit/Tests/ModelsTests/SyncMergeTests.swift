import Foundation
import SwiftData
import Testing
import Units
@testable import Models

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

@Suite("Sinkronizacija: duplikati")
struct SyncMergeTests {

    @Test("Od više postavki ostaju one s obavljenim onboardingom")
    func settingsOnboardedWins() throws {
        let context = try makeContext()
        let fresh = UserSettings()
        let customized = UserSettings()
        customized.defaultRestSeconds = 60
        customized.themeRaw = "dark"
        let onboarded = UserSettings()
        onboarded.defaultRestSeconds = 120
        onboarded.onboardingCompleted = true
        for settings in [fresh, customized, onboarded] { context.insert(settings) }
        try context.save()

        #expect(try GymQueries(context: context).settings().defaultRestSeconds == 120)
        #expect(try Deduplication.removeDuplicateSettings(in: context) == 2)
        let remaining = try context.fetch(FetchDescriptor<UserSettings>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.defaultRestSeconds == 120)
        #expect(try Deduplication.removeDuplicateSettings(in: context) == 0)
    }

    @Test("Zatim prednost imaju mijenjane postavke, pa najmanji id, neovisno o redoslijedu")
    func settingsTieBreak() {
        let fresh = UserSettings()
        fresh.onboardingCompleted = true
        let customized = UserSettings()
        customized.onboardingCompleted = true
        customized.weightUnitRaw = "lbs"
        #expect(customized.changeCount(from: UserSettings()) == 1)
        #expect(UserSettings.preferred(in: [fresh, customized]) === customized)
        #expect(UserSettings.preferred(in: [customized, fresh]) === customized)

        let first = UserSettings()
        let second = UserSettings()
        let expected = first.id.uuidString < second.id.uuidString ? first : second
        #expect(UserSettings.preferred(in: [first, second]) === expected)
        #expect(UserSettings.preferred(in: [second, first]) === expected)
        #expect(UserSettings.preferred(in: []) == nil)
    }

    @Test("Jedinica težine dolazi iz važećeg zapisa postavki, a bez postavki su kilogrami")
    func weightUnitFromSettings() {
        #expect(UserSettings.weightUnit(in: []) == .kilograms)
        let single = UserSettings()
        single.weightUnit = .pounds
        #expect(UserSettings.weightUnit(in: [single]) == .pounds)
        #expect(UserSettings.preferred(in: [single]) === single)
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
