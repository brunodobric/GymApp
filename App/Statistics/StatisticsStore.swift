import Foundation
import Observation
import Stats
import SwiftData

/// Statistika izračunata unaprijed, da je tab Statistika spreman čim ga korisnik otvori.
///
/// Računa se u pozadini (zasebni `ModelContext` izvan glavne niti) nakon pokretanja aplikacije, nakon svake
/// izmjene podataka (`DataVersion`) ili postavki i kad aplikacija dođe u prvi plan novog dana.
/// Ekran samo čita `snapshot`, pa ni otvaranje taba ni animacija tab bara ne čekaju na računanje.
@MainActor @Observable
final class StatisticsStore {
    static let shared = StatisticsStore()

    /// Zadnji izračun; nil dok prvi ne završi.
    private(set) var snapshot: StatisticsSnapshot?

    /// Razdoblje kartice Mišići u danima (4 tjedna, 12 tjedana ili godina). Promjena računa samo tu karticu.
    var muscleDays = 28 {
        didSet { if muscleDays != oldValue { refreshHeatmap() } }
    }

    private struct Key: Equatable {
        var version: Int
        /// Tjedan, mjesec i godina ovise o današnjem danu.
        var day: Date
        /// Za vrijeme treninga `DataVersion` miruje, pa se promjena postavki prati i ovako.
        var settings: StatisticsSettings
    }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var computedKey: Key?
    @ObservationIgnored private var computing: Task<Void, Never>?
    @ObservationIgnored private var computingHeatmap: Task<Void, Never>?

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
    }

    /// Novi izračun ako su se od zadnjeg promijenili podaci, dan ili postavke. Inače ne radi ništa.
    func refresh(settings: StatisticsSettings) {
        guard let container else { return }
        let key = Key(version: DataVersion.shared.value, day: Calendar.current.startOfDay(for: Date()), settings: settings)
        guard key != computedKey else { return }
        computedKey = key
        computing?.cancel()
        computingHeatmap?.cancel()
        let days = muscleDays
        let catalog = AppServices.bundledCatalog
        computing = Task {
            let snapshot = await Task.detached(priority: .utility) {
                PerformanceSignpost.measure("Statistics") {
                    StatisticsSnapshotBuilder.make(
                        context: Self.context(container), catalog: catalog, settings: settings, muscleDays: days
                    )
                }
            }.value
            guard !Task.isCancelled else { return }
            self.snapshot = snapshot
            // Razdoblje kartice Mišići promijenjeno dok se računalo.
            if snapshot.muscleDays != muscleDays { refreshHeatmap() }
        }
    }

    private func refreshHeatmap() {
        guard let container, let current = snapshot, current.isPro else { return }
        computingHeatmap?.cancel()
        let days = muscleDays
        let catalog = AppServices.bundledCatalog
        computingHeatmap = Task {
            let heatmap = await Task.detached(priority: .userInitiated) {
                StatisticsSnapshotBuilder.heatmap(context: Self.context(container), catalog: catalog, days: days)
            }.value
            guard !Task.isCancelled, days == muscleDays else { return }
            snapshot?.heatmap = heatmap
            snapshot?.muscleDays = days
        }
    }

    /// Zasebni kontekst samo za čitanje: ništa ne sprema i ne dira glavni kontekst.
    private nonisolated static func context(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}
