import Models
import OSLog
import Stats
import SwiftData
import WidgetData
import WidgetKit
import WidgetSync

/// Drži widgete (početni i zaključani zaslon, kontrola, komplikacije na satu) u skladu s bazom.
///
/// Nakon svakog spremanja baze, uz kratku odgodu da se više spremanja spoji u jedno, slaže novu snimku
/// (`WidgetSnapshotBuilder`) i sprema je u App Group. Widgeti se osvježavaju samo kad se snimka promijeni,
/// jer sustav ograničava broj osvježavanja. Spremanje iz bilo kojeg dijela aplikacije (trening, težina,
/// raspored, Prečaci) zato ne treba posebno javljati widgetima.
@MainActor
final class WidgetRefresher {
    static let shared = WidgetRefresher()

    /// Zadnja složena snimka (i za kontekst sata).
    private(set) var latest: WidgetSnapshot?

    private var container: ModelContainer?
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "Widgets")

    /// Odgoda nakon spremanja: završetak treninga sprema više puta zaredom.
    static let debounce: Duration = .seconds(1)

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetRefresher.shared.scheduleRefresh() }
        })
        // U ponoć se mijenja "danas" i tjedan (snimka je za tekući dan).
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetRefresher.shared.scheduleRefresh() }
        })
        scheduleRefresh(after: .zero)
    }

    /// Nova snimka nakon kratke odgode; novi poziv odgađa prethodni.
    func scheduleRefresh(after delay: Duration = WidgetRefresher.debounce) {
        guard container != nil else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Slaže snimku odmah. Zasebni kontekst: snimka ništa ne sprema, a ono što dohvat stvori (npr. postavke
    /// prije onboardinga) ne završi u glavnom kontekstu.
    func refresh() {
        guard let container else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let settings = UserSettings.preferred(in: (try? context.fetch(FetchDescriptor<UserSettings>())) ?? [])
        let unit = settings?.weightUnit ?? .kilograms
        let custom = (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? []
        let info = ExerciseInfoBuilder.provider(catalog: AppServices.bundledCatalog, custom: custom)
        let builder = WidgetSnapshotBuilder(
            context: context, isCardio: ExerciseInfoBuilder.isCardio(info), isCompound: { info($0)?.isCompound },
            recordText: { RecordFormat.value($0, unit: unit) }
        )
        do {
            let snapshot = try builder.make()
            let watchChanged = snapshot.week != latest?.week || snapshot.bodyWeight?.latestKg != latest?.bodyWeight?.latestKg
            latest = snapshot
            if try WidgetSnapshotStore.shared.save(snapshot) {
                WidgetCenter.shared.reloadAllTimelines()
                ControlCenter.shared.reloadAllControls()
            }
            if watchChanged { PhoneWatchSync.shared.refreshContext() }
        } catch {
            logger.error("Snimka za widgete: \(String(describing: error))")
        }
    }
}
