import Connectivity
import Foundation
import Observation
import WatchConnectivity

/// Prototip 3: razmjena događaja između iPhonea i Watcha.
/// Isti kod radi na oba uređaja. Svaki primljeni događaj bilježi se s kanalom,
/// kašnjenjem i oznakom duplikata, kako bi se u fazi 0 izmjerilo ponašanje
/// `sendMessage`, `transferUserInfo` i `updateApplicationContext`.
@MainActor
@Observable
final class ConnectivityPrototypeSession: NSObject {

    struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }

    static let shared = ConnectivityPrototypeSession()

    private(set) var log: [LogEntry] = []
    private(set) var activationDescription = "nije aktivirana"
    private(set) var isReachable = false
    private(set) var isCounterpartInstalled = false

    private let role: DeviceRole
    private var deduplicator = WorkoutEventDeduplicator()

    override private init() {
        #if os(watchOS)
        role = .watch
        #else
        role = .phone
        #endif
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            append("WatchConnectivity nije podržan na ovom uređaju")
            return
        }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: Slanje

    func sendViaMessage() {
        guard WCSession.default.isReachable else {
            append("sendMessage: drugi uređaj nije dostupan")
            return
        }
        guard let ping = makePing(channel: "sendMessage") else { return }
        let (event, payload) = ping
        WCSession.default.sendMessage(payload, replyHandler: nil) { error in
            let text = error.localizedDescription
            Task { @MainActor in
                ConnectivityPrototypeSession.shared.append("sendMessage greška: \(text)")
            }
        }
        append("Poslano sendMessage \(event.id.shortText)")
    }

    func sendViaUserInfo() {
        guard let ping = makePing(channel: "transferUserInfo") else { return }
        let (event, payload) = ping
        WCSession.default.transferUserInfo(payload)
        append("U redu za transferUserInfo \(event.id.shortText)")
    }

    func sendViaApplicationContext() {
        guard let ping = makePing(channel: "applicationContext") else { return }
        let (event, payload) = ping
        do {
            try WCSession.default.updateApplicationContext(payload)
            append("Postavljen applicationContext \(event.id.shortText)")
        } catch {
            append("applicationContext greška: \(error.localizedDescription)")
        }
    }

    /// Šalje isti događaj na dva kanala, kako bi se provjerilo prepoznavanje duplikata.
    func sendDuplicate() {
        guard WCSession.default.isReachable else {
            append("Duplikat: drugi uređaj nije dostupan")
            return
        }
        guard let ping = makePing(channel: "duplikat") else { return }
        let (event, payload) = ping
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        WCSession.default.transferUserInfo(payload)
        append("Poslan isti događaj dvaput \(event.id.shortText)")
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: Primanje

    fileprivate func receive(_ event: WorkoutEvent?, channel: String) {
        guard let event else {
            append("Neispravan paket preko \(channel)")
            return
        }
        let latency = Date().timeIntervalSince(event.createdAt)
        let isNew = deduplicator.accept(event)
        let latencyText = (latency * 1000).formatted(.number.precision(.fractionLength(0)))
        append("Primljeno \(channel) od \(event.origin.rawValue) \(event.id.shortText), \(latencyText) ms\(isNew ? "" : ", DUPLIKAT odbačen")")
    }

    fileprivate func updateState(activation: String, reachable: Bool, counterpartInstalled: Bool) {
        activationDescription = activation
        isReachable = reachable
        isCounterpartInstalled = counterpartInstalled
    }

    // MARK: Pomoćno

    private func makePing(channel: String) -> (WorkoutEvent, [String: Any])? {
        let event = WorkoutEvent(origin: role, kind: .ping(note: channel))
        do {
            return (event, try event.payload())
        } catch {
            append("Pakiranje nije uspjelo: \(error)")
            return nil
        }
    }

    fileprivate func append(_ text: String) {
        log.insert(LogEntry(date: Date(), text: text), at: 0)
    }
}

// MARK: - WCSessionDelegate

extension ConnectivityPrototypeSession: WCSessionDelegate {

    nonisolated private static func snapshot(of session: WCSession) -> (String, Bool, Bool) {
        let activation: String = switch session.activationState {
        case .activated: "aktivna"
        case .inactive: "neaktivna"
        case .notActivated: "nije aktivirana"
        @unknown default: "nepoznato"
        }
        #if os(iOS)
        let installed = session.isPaired && session.isWatchAppInstalled
        #else
        let installed = session.isCompanionAppInstalled
        #endif
        return (activation, session.isReachable, installed)
    }

    nonisolated private func publishState(of session: WCSession) {
        let (activation, reachable, installed) = Self.snapshot(of: session)
        Task { @MainActor in
            ConnectivityPrototypeSession.shared.updateState(
                activation: activation,
                reachable: reachable,
                counterpartInstalled: installed
            )
        }
    }

    nonisolated private func deliver(_ payload: [String: Any], channel: String) {
        let event = try? WorkoutEvent(payload: payload)
        Task { @MainActor in
            ConnectivityPrototypeSession.shared.receive(event, channel: channel)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        publishState(of: session)
        if let error {
            let text = error.localizedDescription
            Task { @MainActor in
                ConnectivityPrototypeSession.shared.append("Aktivacija nije uspjela: \(text)")
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        publishState(of: session)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message, channel: "sendMessage")
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo, channel: "transferUserInfo")
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext, channel: "applicationContext")
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

private extension UUID {
    var shortText: String { String(uuidString.prefix(8)) }
}
