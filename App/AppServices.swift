import Models
import OSLog
import SwiftData

/// Baza i veze koje trebaju i ekrani i radnje izvan njih (gumb u Live Activityju, poruke sa sata).
///
/// `LiveActivityIntent` sustav može pokrenuti u pozadini prije nego što se išta prikaže, pa se baza otvara
/// ovdje, jednom, a ne u `GymApp`.
@MainActor
enum AppServices {
    /// iCloud kontejner privatne baze.
    static let cloudContainerIdentifier = "iCloud.com.brunodobric.gymapp"

    /// Ima li build iCloud dozvolu. Besplatni Personal Team je nema, pa baza ostaje samo na uređaju.
    static var isCloudSyncSupported: Bool {
        #if PERSONAL_TEAM
        false
        #else
        true
        #endif
    }

    /// Korisnička baza i način na koji je otvorena. Uključivanje i isključivanje sinkronizacije
    /// vrijedi od sljedećeg pokretanja, jer se otvorena baza ne može sigurno zamijeniti dok je ekrani koriste.
    private struct Store {
        var container: ModelContainer
        var isSyncRunning = false
        var syncStartFailed = false
        /// Baza na uređaju se nije otvorila (npr. nakon neuspjele migracije): radi se s praznom bazom u memoriji,
        /// a aplikacija prikazuje `StoreFailureScreen` umjesto da se sruši pri svakom pokretanju.
        var openError: String?
    }

    private static let store: Store = {
        #if DEBUG
        if ScreenshotMode.isActive { return Store(container: ScreenshotMode.makeContainer()) }
        #endif
        if SyncPreferences().usesCloudKit(isSupported: isCloudSyncSupported) {
            do {
                let container = try GymPersistence.makeUserContainer(
                    storage: .cloudKit(containerIdentifier: cloudContainerIdentifier)
                )
                return Store(container: container, isSyncRunning: true)
            } catch {
                // Bez iClouda aplikacija i dalje radi, samo na uređaju. Postavke prikazuju da sinkronizacija nije pokrenuta.
                Logger(subsystem: "com.brunodobric.gymapp", category: "Sync")
                    .error("CloudKit baza se nije otvorila, nastavlja se lokalno: \(String(describing: error))")
                var local = openLocal()
                local.syncStartFailed = true
                return local
            }
        }
        return openLocal()
    }()

    static var container: ModelContainer { store.container }
    /// Je li baza u ovom pokretanju otvorena s CloudKitom.
    static var isSyncRunning: Bool { store.isSyncRunning }
    /// Je li otvaranje s CloudKitom pokušano i nije uspjelo.
    static var syncStartFailed: Bool { store.syncStartFailed }
    /// Opis greške ako se baza na uređaju nije otvorila (vidi `Store.openError`).
    static var storeOpenError: String? { store.openError }

    private static func openLocal() -> Store {
        do {
            return Store(container: try GymPersistence.makeUserContainer(storage: .local))
        } catch {
            Logger(subsystem: "com.brunodobric.gymapp", category: "Store")
                .fault("Korisnička baza se nije mogla otvoriti: \(String(describing: error))")
            do {
                return Store(container: try GymPersistence.makeUserContainer(storage: .inMemory), openError: String(describing: error))
            } catch {
                // Ni prazna baza u memoriji: aplikacija ne može raditi.
                fatalError("Korisnička baza se nije mogla otvoriti: \(error)")
            }
        }
    }

    private static var isStarted = false

    /// Pokreće vezu sa satom i praćenje sinkronizacije. Poziva se što ranije (i iz pozadinskih radnji), a više poziva ne smeta.
    static func start() {
        guard !isStarted else { return }
        isStarted = true
        // Bez baze na uređaju ništa se ne pokreće: poruke sa sata i podaci iz Zdravlja ostaju u redu čekanja
        // dok se baza ne otvori, umjesto da završe u privremenoj bazi u memoriji.
        guard storeOpenError == nil else { return }
        #if DEBUG
        if ScreenshotMode.isActive { ScreenshotMode.populate(container) }
        #endif
        // Dodir na podsjetnik rasporeda otvara pregled treninga.
        NotificationRouter.shared.start()
        // WatchConnectivity sesija mora se aktivirati što ranije, da poruke sa sata
        // stignu i kad se aplikacija pokrene u pozadini.
        // Podaci iz Zdravlja iz verzija prije faze 12 prelaze u lokalnu bazu, da ne idu u iCloud.
        do {
            try HealthLocalStore(context: container.mainContext).moveHealthDataOutOfUserStore()
        } catch {
            Logger(subsystem: "com.brunodobric.gymapp", category: "Health")
                .error("Premještanje podataka iz Zdravlja: \(String(describing: error))")
        }
        PhoneWatchSync.shared.start(container: container)
        SyncMonitor.shared.start()
        // Rušenja, zastoji i performanse (MetricKit), samo u lokalni dnevnik.
        MetricsReporter.shared.start()
    }
}
