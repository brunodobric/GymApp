import CoreData
import Foundation
import Models
import Observation
import SwiftData

/// Brojač izmjena podataka: Statistika, Pregled i kartice na Početnoj preračunavaju se kad se on promijeni.
///
/// Raste nakon spremanja baze (bilo kojeg konteksta: završen, uređen ili obrisan trening, uvoz iz Zdravlja,
/// uvoz sigurnosne kopije) i nakon uvoza s iClouda, uz kratku odgodu da se više spremanja spoji u jedno.
/// Prije su ekrani pratili samo broj treninga, pa izmjena starog treninga nije osvježavala statistiku.
/// Dok traje trening (aktivnost u zadnjih nekoliko sati), svaka serija sprema bazu, a završeni treninzi se ne
/// mijenjaju, pa brojač miruje do završetka treninga.
@MainActor @Observable
final class DataVersion {
    static let shared = DataVersion()

    private(set) var value = 0

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Odgoda nakon spremanja: završetak treninga i uvozi spremaju više puta zaredom.
    static let debounce: Duration = .milliseconds(800)
    /// Trening bez aktivnosti dulje od ovoga ne zaustavlja brojač (zaboravljen trening).
    static let activeWindow: TimeInterval = 6 * 3600

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DataVersion.shared.scheduleBump() }
        })
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil else { return }
            MainActor.assumeIsolated { DataVersion.shared.scheduleBump() }
        })
    }

    private func scheduleBump() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard let self, !Task.isCancelled else { return }
            if !self.isWorkoutInProgress() { self.value &+= 1 }
        }
    }

    private func isWorkoutInProgress() -> Bool {
        guard let container else { return false }
        let cutoff = Date.now.addingTimeInterval(-Self.activeWindow)
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == "active" && $0.lastActivityAt > cutoff }
        )
        return ((try? container.mainContext.fetchCount(descriptor)) ?? 0) > 0
    }
}
