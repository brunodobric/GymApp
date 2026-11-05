import Foundation
import Testing
@testable import Models

@Suite("Sinkronizacija: stanje")
struct SyncStatusTests {

    private func resolve(
        isSupported: Bool = true,
        isEnabled: Bool = true,
        isRunning: Bool = true,
        startFailed: Bool = false,
        account: CloudAccountState? = .available,
        activity: SyncActivity = .idle(lastSync: nil)
    ) -> SyncStatus {
        SyncStatus.resolve(
            isSupported: isSupported, isEnabled: isEnabled, isRunning: isRunning,
            startFailed: startFailed, account: account, activity: activity
        )
    }

    @Test("Build bez iClouda uvijek je nedostupan")
    func unsupported() {
        #expect(resolve(isSupported: false) == .unavailable)
        #expect(resolve(isSupported: false, isEnabled: false, isRunning: false) == .unavailable)
    }

    @Test("Isključivanje i uključivanje vrijedi nakon ponovnog pokretanja")
    func pendingRestart() {
        #expect(resolve(isEnabled: false, isRunning: false) == .off)
        #expect(resolve(isEnabled: false, isRunning: true) == .willTurnOff)
        #expect(resolve(isEnabled: true, isRunning: false) == .willTurnOn)
        #expect(resolve(isEnabled: true, isRunning: false, startFailed: true) == .startFailed)
    }

    @Test("Stanje računa ima prednost pred aktivnošću")
    func account() {
        #expect(resolve(account: nil) == .checkingAccount)
        #expect(resolve(account: .noAccount, activity: .syncing) == .noAccount)
        #expect(resolve(account: .restricted) == .restricted)
        #expect(resolve(account: .temporarilyUnavailable) == .accountUnavailable)
        #expect(resolve(account: .unknown) == .accountUnavailable)
    }

    @Test("S dostupnim računom prikazuje se aktivnost")
    func activity() {
        let date = Date(timeIntervalSince1970: 1000)
        #expect(resolve(activity: .syncing) == .syncing)
        #expect(resolve(activity: .idle(lastSync: date)) == .synced(lastSync: date))
        #expect(resolve(activity: .failed(.quotaExceeded)) == .failed(.quotaExceeded))
        #expect(SyncStatus.failed(.network).needsAttention)
        #expect(!SyncStatus.synced(lastSync: nil).needsAttention)
    }
}

@Suite("Sinkronizacija: događaji")
struct SyncActivityTrackerTests {

    @Test("Događaj traje od početka do kraja")
    func startAndEnd() {
        var tracker = SyncActivityTracker()
        let id = UUID()
        let end = Date(timeIntervalSince1970: 500)
        let started = tracker.apply(SyncEvent(id: id, kind: .export))
        #expect(started == false)
        #expect(tracker.activity == .syncing)
        let ended = tracker.apply(SyncEvent(id: id, kind: .export, endDate: end))
        #expect(ended == false)
        #expect(tracker.activity == .idle(lastSync: end))
    }

    @Test("Uspješan kraj uvoza traži uklanjanje duplikata")
    func importFinished() {
        var tracker = SyncActivityTracker()
        let id = UUID()
        tracker.apply(SyncEvent(id: id, kind: .import))
        let finished = tracker.apply(SyncEvent(id: id, kind: .import, endDate: .now))
        #expect(finished)
        let failed = tracker.apply(SyncEvent(id: UUID(), kind: .import, endDate: .now, failure: .network))
        #expect(failed == false)
    }

    @Test("Greška ostaje do sljedećeg uspjeha")
    func failureClearsOnSuccess() {
        var tracker = SyncActivityTracker()
        tracker.apply(SyncEvent(id: UUID(), kind: .export, endDate: .now, failure: .quotaExceeded))
        #expect(tracker.activity == .failed(.quotaExceeded))
        tracker.apply(SyncEvent(id: UUID(), kind: .import))
        #expect(tracker.activity == .failed(.quotaExceeded))
        let end = Date(timeIntervalSince1970: 2000)
        tracker.apply(SyncEvent(id: UUID(), kind: .import, endDate: end))
        #expect(tracker.activity == .syncing)
        #expect(tracker.lastSuccess == end)
    }

    @Test("Zadnja sinkronizacija je najkasniji kraj")
    func lastSuccessIsLatest() {
        var tracker = SyncActivityTracker()
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)
        tracker.apply(SyncEvent(id: UUID(), kind: .export, endDate: late))
        tracker.apply(SyncEvent(id: UUID(), kind: .import, endDate: early))
        #expect(tracker.lastSuccess == late)
    }

    @Test("Kraj uvoza se pamti zasebno, a izvoz i neuspjeli uvoz ga ne mijenjaju")
    func lastImport() {
        var tracker = SyncActivityTracker()
        tracker.apply(SyncEvent(id: UUID(), kind: .export, endDate: Date(timeIntervalSince1970: 100)))
        #expect(tracker.lastImport == nil)
        tracker.apply(SyncEvent(id: UUID(), kind: .import, endDate: Date(timeIntervalSince1970: 50), failure: .network))
        #expect(tracker.lastImport == nil)
        let end = Date(timeIntervalSince1970: 300)
        tracker.apply(SyncEvent(id: UUID(), kind: .import, endDate: end))
        #expect(tracker.lastImport == end)
    }
}

@Suite("Sinkronizacija: postavka")
struct SyncPreferencesTests {

    @Test("Zadano je uključeno, a promjena se pamti")
    func defaultsAndChanges() throws {
        let suite = "SyncPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SyncPreferences(defaults: defaults)
        #expect(preferences.isEnabled)
        #expect(preferences.usesCloudKit(isSupported: true))
        #expect(!preferences.usesCloudKit(isSupported: false))
        preferences.isEnabled = false
        #expect(!SyncPreferences(defaults: defaults).isEnabled)
        #expect(!preferences.usesCloudKit(isSupported: true))
    }
}
