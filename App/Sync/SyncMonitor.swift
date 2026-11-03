import CloudKit
import CoreData
import Models
import OSLog
import SwiftUI

/// Prati stanje iCloud računa i događaje sinkronizacije korisničke baze, za prikaz u Postavkama.
///
/// SwiftData ne otkriva `NSPersistentCloudKitContainer` koji koristi, ali on i dalje javlja
/// `eventChangedNotification`, pa se događaji (postavljanje, uvoz, izvoz) čitaju odatle.
@MainActor
@Observable
final class SyncMonitor {
    static let shared = SyncMonitor()

    /// Stanje računa. nil dok se provjerava.
    private(set) var account: CloudAccountState?
    private(set) var tracker = SyncActivityTracker()

    /// Postavka "Sinkronizacija preko iClouda". Promjena vrijedi od sljedećeg pokretanja.
    var isEnabled: Bool {
        get { enabledStorage }
        set {
            enabledStorage = newValue
            SyncPreferences().isEnabled = newValue
        }
    }

    private var enabledStorage = SyncPreferences().isEnabled

    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "Sync")

    var status: SyncStatus {
        SyncStatus.resolve(
            isSupported: AppServices.isCloudSyncSupported,
            isEnabled: isEnabled,
            isRunning: AppServices.isSyncRunning,
            startFailed: AppServices.syncStartFailed,
            account: account,
            activity: tracker.activity
        )
    }

    func start() {
        guard !isStarted, AppServices.isCloudSyncSupported else { return }
        isStarted = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event else { return }
            let syncEvent = Self.syncEvent(from: event)
            MainActor.assumeIsolated { self?.handle(syncEvent) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccount() }
        })
        refreshAccount()
    }

    /// Ponovno provjerava iCloud račun (npr. kad se otvore Postavke).
    func refreshAccount() {
        guard AppServices.isCloudSyncSupported else { return }
        Task {
            let state: CloudAccountState
            do {
                let status = try await CKContainer(identifier: AppServices.cloudContainerIdentifier).accountStatus()
                state = Self.accountState(from: status)
            } catch {
                logger.error("Stanje iCloud računa nije poznato: \(String(describing: error))")
                state = .unknown
            }
            account = state
        }
    }

    private func handle(_ event: SyncEvent) {
        if let failure = event.failure {
            logger.error("Sinkronizacija nije uspjela: \(String(describing: failure))")
        }
        tracker.apply(event)
    }

    // MARK: Pretvorba iz CloudKita

    nonisolated private static func syncEvent(from event: NSPersistentCloudKitContainer.Event) -> SyncEvent {
        let kind: SyncEventKind
        switch event.type {
        case .import: kind = .import
        case .export: kind = .export
        default: kind = .setup
        }
        var failure: SyncFailure?
        if event.endDate != nil, !event.succeeded {
            failure = failureKind(event.error)
        }
        return SyncEvent(id: event.identifier, kind: kind, endDate: event.endDate, failure: failure)
    }

    nonisolated private static func failureKind(_ error: Error?) -> SyncFailure {
        guard let error = error as? CKError else { return .other }
        switch error.code {
        case .quotaExceeded: return .quotaExceeded
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy: return .network
        case .notAuthenticated: return .notAuthenticated
        case .partialFailure:
            // Djelomična greška nosi greške pojedinih zapisa: puni iCloud je najvažnije prepoznati.
            let inner = error.partialErrorsByItemID?.values.compactMap { $0 as? CKError } ?? []
            return inner.contains { $0.code == .quotaExceeded } ? .quotaExceeded : .other
        default: return .other
        }
    }

    nonisolated private static func accountState(from status: CKAccountStatus) -> CloudAccountState {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .unknown
        @unknown default: .unknown
        }
    }
}
