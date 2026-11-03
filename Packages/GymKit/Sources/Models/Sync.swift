import Foundation

// Sinkronizacija korisničke baze preko CloudKita (faza 12).
// Ovdje je samo logika stanja, bez CloudKita: aplikacija pretvara stanje računa i događaje
// `NSPersistentCloudKitContainer` u ove tipove, pa se ponašanje može testirati.

/// Stanje iCloud računa na uređaju.
public enum CloudAccountState: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    /// Sustav nije mogao odrediti stanje (ili je provjera javila grešku).
    case unknown
}

/// Zašto sinkronizacija nije uspjela.
public enum SyncFailure: Equatable, Sendable {
    /// Korisnikov iCloud je pun.
    case quotaExceeded
    /// Nema mreže. Sinkronizacija se nastavlja sama kad se veza vrati.
    case network
    /// iCloud traži ponovnu prijavu.
    case notAuthenticated
    case other
}

/// Vrsta događaja sinkronizacije (`NSPersistentCloudKitContainer.EventType`).
public enum SyncEventKind: Equatable, Sendable {
    case setup
    case `import`
    case export
}

/// Jedan događaj sinkronizacije. Sustav javlja svaki događaj dvaput: na početku (`endDate == nil`) i na kraju.
public struct SyncEvent: Equatable, Sendable {
    public var id: UUID
    public var kind: SyncEventKind
    public var endDate: Date?
    /// nil znači da je događaj uspio (ili još traje).
    public var failure: SyncFailure?

    public init(id: UUID, kind: SyncEventKind, endDate: Date? = nil, failure: SyncFailure? = nil) {
        self.id = id
        self.kind = kind
        self.endDate = endDate
        self.failure = failure
    }
}

/// Što sinkronizacija trenutno radi.
public enum SyncActivity: Equatable, Sendable {
    /// Ništa ne radi. Datum je kraj zadnjeg uspješnog događaja u ovom pokretanju aplikacije.
    case idle(lastSync: Date?)
    case syncing
    case failed(SyncFailure)
}

/// Prati događaje sinkronizacije i iz njih izvodi trenutnu aktivnost.
public struct SyncActivityTracker: Equatable, Sendable {
    public private(set) var running: Set<UUID> = []
    public private(set) var lastSuccess: Date?
    public private(set) var failure: SyncFailure?

    public init() {}

    /// Primjenjuje događaj. Vraća true kad je upravo uspješno završio uvoz s iClouda
    /// (tada mogu stići duplikati, pa ih treba ukloniti).
    @discardableResult
    public mutating func apply(_ event: SyncEvent) -> Bool {
        guard let endDate = event.endDate else {
            running.insert(event.id)
            return false
        }
        running.remove(event.id)
        if let failure = event.failure {
            self.failure = failure
            return false
        }
        failure = nil
        lastSuccess = max(lastSuccess ?? endDate, endDate)
        return event.kind == .import
    }

    public var activity: SyncActivity {
        if let failure { return .failed(failure) }
        if !running.isEmpty { return .syncing }
        return .idle(lastSync: lastSuccess)
    }
}

/// Stanje sinkronizacije koje se prikazuje u Postavkama.
public enum SyncStatus: Equatable, Sendable {
    /// Build bez iCloud dozvole (besplatni Personal Team).
    case unavailable
    /// Korisnik je isključio sinkronizaciju.
    case off
    /// Uključena je, a počinje nakon ponovnog pokretanja aplikacije.
    case willTurnOn
    /// Isključena je, a prestaje nakon ponovnog pokretanja aplikacije.
    case willTurnOff
    /// Baza se nije mogla otvoriti s CloudKitom, pa radi samo na uređaju.
    case startFailed
    case checkingAccount
    case noAccount
    case restricted
    case accountUnavailable
    case syncing
    /// Sve je sinkronizirano. Datum zadnje sinkronizacije u ovom pokretanju, ako je poznat.
    case synced(lastSync: Date?)
    case failed(SyncFailure)

    /// Treba li korisnik nešto napraviti ili je stanje neispravno (za boju ikone).
    public var needsAttention: Bool {
        switch self {
        case .startFailed, .noAccount, .restricted, .accountUnavailable, .failed: true
        default: false
        }
    }

    public static func resolve(
        isSupported: Bool,
        isEnabled: Bool,
        isRunning: Bool,
        startFailed: Bool,
        account: CloudAccountState?,
        activity: SyncActivity
    ) -> SyncStatus {
        guard isSupported else { return .unavailable }
        guard isEnabled else { return isRunning ? .willTurnOff : .off }
        guard isRunning else { return startFailed ? .startFailed : .willTurnOn }
        switch account {
        case nil: return .checkingAccount
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .temporarilyUnavailable, .unknown: return .accountUnavailable
        case .available:
            switch activity {
            case .failed(let failure): return .failed(failure)
            case .syncing: return .syncing
            case .idle(let lastSync): return .synced(lastSync: lastSync)
            }
        }
    }
}

/// Postavka "Sinkronizacija preko iClouda". Čuva se na uređaju, ne u bazi: o njoj ovisi
/// otvara li se baza s CloudKitom, a svaki uređaj je uključuje zasebno.
public struct SyncPreferences {
    public static let enabledKey = "syncEnabled"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Zadano je uključeno.
    public var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// Treba li bazu otvoriti s CloudKitom.
    public func usesCloudKit(isSupported: Bool) -> Bool {
        isSupported && isEnabled
    }
}
