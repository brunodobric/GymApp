import Connectivity
import Foundation
import Models
import OSLog
import WatchConnectivity

/// WatchConnectivity veza između iPhonea i Watcha (specifikacija, odjeljak 6). Isti kod radi na oba uređaja.
///
/// * `sendReliably`: `sendMessage` dok je drugi uređaj dostupan, a inače (ili kad poruka ne prođe)
///   `transferUserInfo`, koji sustav isporučuje redom i nakon ponovnog spajanja.
/// * `sendIfReachable`: samo `sendMessage`, za snimke koje ionako nosi i `updateApplicationContext`.
/// * `updateContext`: zadnje stanje; drugi uređaj ga dobije i kad se aplikacija tek pokrene.
///
/// Primljeni događaji prolaze kroz `WorkoutEventDeduplicator`, pa isti događaj stigao dvama kanalima
/// obrađuje se jednom.
@MainActor
final class WatchTransport: NSObject {
    static let shared = WatchTransport()

    /// Primljeni događaj (već bez duplikata).
    var onEvent: ((WorkoutEvent) -> Void)?
    /// Primljeni `applicationContext` drugog uređaja.
    var onContext: ((ApplicationContextPayload) -> Void)?
    /// Sesija je aktivirana ili se promijenila dostupnost.
    var onStateChange: (() -> Void)?

    private(set) var isReachable = false
    private(set) var isActivated = false
    private var deduplicator = WorkoutEventDeduplicator()
    private let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "WatchConnectivity")

    #if os(iOS)
    static let role: DeviceRole = .phone
    #else
    static let role: DeviceRole = .watch
    #endif

    override private init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Ima li smisla slati: na iPhoneu sat mora biti uparen i imati aplikaciju.
    var isCounterpartAvailable: Bool {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return false }
        #if os(iOS)
        return WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
        #else
        return true
        #endif
    }

    /// Zadnji `applicationContext` koji je drugi uređaj poslao (preživi ponovno pokretanje aplikacije).
    var receivedContext: ApplicationContextPayload {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return ApplicationContextPayload() }
        return ApplicationContextPayload(dictionary: WCSession.default.receivedApplicationContext)
    }

    // MARK: Slanje

    func sendReliably(_ event: WorkoutEvent) {
        guard isCounterpartAvailable, let payload = encode(event) else { return }
        let session = WCSession.default
        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload, replyHandler: nil) { [logger] error in
            // Poruka nije stigla: šalje se zajamčenim kanalom (primatelj prepoznaje duplikat po UUID-u).
            logger.info("sendMessage nije prošao, šaljem transferUserInfo: \(error.localizedDescription)")
            if let retry = try? event.payload() {
                WCSession.default.transferUserInfo(retry)
            }
        }
    }

    func sendIfReachable(_ event: WorkoutEvent) {
        guard isCounterpartAvailable, WCSession.default.isReachable, let payload = encode(event) else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    func updateContext(_ context: ApplicationContextPayload) {
        guard isCounterpartAvailable else { return }
        do {
            try WCSession.default.updateApplicationContext(context.dictionary())
        } catch {
            logger.error("updateApplicationContext: \(error.localizedDescription)")
        }
    }

    private func encode(_ event: WorkoutEvent) -> [String: Any]? {
        do {
            return try event.payload()
        } catch {
            logger.error("Pakiranje događaja: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Primanje

    fileprivate func receive(_ event: WorkoutEvent) {
        guard deduplicator.accept(event) else { return }
        onEvent?(event)
    }

    fileprivate func receive(_ context: ApplicationContextPayload) {
        onContext?(context)
    }

    fileprivate func updateState(activated: Bool, reachable: Bool) {
        isActivated = activated
        isReachable = reachable
        onStateChange?()
    }
}

// MARK: - WCSessionDelegate

extension WatchTransport: WCSessionDelegate {

    nonisolated private func publishState(of session: WCSession) {
        let activated = session.activationState == .activated
        let reachable = session.isReachable
        Task { @MainActor in
            WatchTransport.shared.updateState(activated: activated, reachable: reachable)
        }
    }

    nonisolated private func deliver(_ payload: [String: Any]) {
        guard let event = try? WorkoutEvent(payload: payload) else { return }
        Task { @MainActor in
            WatchTransport.shared.receive(event)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        publishState(of: session)
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        publishState(of: session)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let context = ApplicationContextPayload(dictionary: applicationContext)
        Task { @MainActor in
            WatchTransport.shared.receive(context)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        publishState(of: session)
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Korisnik je prebacio na drugi sat: sesiju treba ponovno aktivirati.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        publishState(of: session)
    }
    #endif
}
