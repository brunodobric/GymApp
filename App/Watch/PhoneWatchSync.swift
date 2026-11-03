import Connectivity
import Foundation
import Models
import OSLog
import Planning
import SwiftData

/// Veza aplikacije na iPhoneu sa satom (specifikacija, odjeljak 6, "Sinkronizacija iPhone ↔ Watch").
///
/// * Trening koji vodi sat stiže kao snimka i upisuje se u bazu (bez duplikata, zadnja promjena pobjeđuje).
///   Izmjene na iPhoneu šalju se satu kao naredbe (razlika prema zadnjoj snimci sa sata).
/// * Trening koji vodi iPhone šalje se satu kao snimka, a naredbe sa sata upisuju se u bazu.
/// * Satu se šalje kontekst: sljedeći treninzi, predlošci s pretpunjenim serijama, jedinica i pauza.
@MainActor
final class PhoneWatchSync {
    static let shared = PhoneWatchSync()

    private var container: ModelContainer?
    private let transport = WatchTransport.shared
    private let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "WatchSync")

    /// Zadnja poznata snimka treninga koji vodi sat: osnova za razliku kad se trening mijenja na iPhoneu.
    private var watchBases: [UUID: SessionSnapshot] = [:]
    /// Zadnja snimka treninga s iPhonea poslana satu.
    private var lastSent: SessionSnapshot?
    private var lastContext: WatchContextPayload?
    private var pendingChanges: [UUID: Task<Void, Never>] = [:]

    private init() {}

    private var context: ModelContext? { container?.mainContext }

    /// Poziva se pri pokretanju aplikacije, što ranije, da poruke sa sata stignu i kad se aplikacija
    /// pokrene u pozadini.
    func start(container: ModelContainer) {
        self.container = container
        transport.onEvent = { [weak self] event in self?.handle(event) }
        transport.onContext = { [weak self] payload in self?.handle(payload) }
        transport.onStateChange = { [weak self] in self?.connectionChanged() }
        transport.activate()
        if let context { try? SessionSnapshotStore(context: context).purgeDiscarded() }
    }

    // MARK: Slanje

    /// Trening se promijenio na iPhoneu. Slanje se odgađa kratko, da se tipkanje i brzi niz promjena
    /// pošalju jednom.
    func sessionChanged(_ session: Session) {
        let id = session.id
        pendingChanges[id]?.cancel()
        pendingChanges[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.flush(sessionID: id)
        }
    }

    /// Mora se pozvati prije brisanja treninga na iPhoneu, jer se nakon brisanja ne zna što je bilo.
    func willDiscard(_ session: Session) {
        pendingChanges[session.id]?.cancel()
        var snapshot = SessionSnapshot(session: session)
        let base = watchBases.removeValue(forKey: session.id)
        snapshot.state = .discarded
        snapshot.updatedAt = Date()
        switch session.controllingDevice {
        case .watch:
            guard base != nil || session.state == .active else { return }
            transport.sendReliably(WorkoutEvent(sessionID: session.id, origin: .phone, kind: .commands([.discard])))
        case .phone:
            transport.sendReliably(WorkoutEvent(sessionID: session.id, origin: .phone, kind: .snapshot(snapshot)))
            lastSent = nil
            sendContext(session: nil)
        }
    }

    /// Ponovno slaže kontekst za sat (nakon pokretanja, završetka treninga ili izmjene rasporeda).
    func refreshContext() {
        guard let context, transport.isCounterpartAvailable else { return }
        do {
            lastContext = try WatchContextBuilder(context: context).make()
        } catch {
            logger.error("Kontekst za sat: \(error.localizedDescription)")
        }
        let active = try? GymQueries(context: context).activeSession()
        sendContext(session: active.flatMap { $0.controllingDevice == .phone ? SessionSnapshot(session: $0) : nil })
    }

    private func flush(sessionID: UUID) {
        pendingChanges[sessionID] = nil
        guard let context, let session = try? SessionSnapshotStore(context: context).session(withID: sessionID) else { return }
        let snapshot = SessionSnapshot(session: session)
        switch session.controllingDevice {
        case .phone:
            broadcast(snapshot)
            if snapshot.state != .active { refreshContext() }
        case .watch:
            guard let base = watchBases[sessionID] else { return }
            let commands = SnapshotDiff.commands(from: base, to: snapshot)
            guard !commands.isEmpty else { return }
            transport.sendReliably(WorkoutEvent(sessionID: sessionID, origin: .phone, kind: .commands(commands)))
            watchBases[sessionID] = snapshot
        }
    }

    /// Snimka treninga koji vodi iPhone: odmah ako je sat dostupan, a uvijek i kao zadnje stanje.
    private func broadcast(_ snapshot: SessionSnapshot) {
        guard snapshot != lastSent else { return }
        lastSent = snapshot
        let event = WorkoutEvent(sessionID: snapshot.id, origin: .phone, kind: .snapshot(snapshot))
        if snapshot.state == .active {
            transport.sendIfReachable(event)
            sendContext(session: snapshot)
        } else {
            transport.sendReliably(event)
            sendContext(session: nil)
        }
    }

    private func sendContext(session: SessionSnapshot?) {
        guard transport.isCounterpartAvailable else { return }
        if lastContext == nil, let context {
            lastContext = try? WatchContextBuilder(context: context).make()
        }
        transport.updateContext(ApplicationContextPayload(watchContext: lastContext, session: session))
    }

    // MARK: Primanje

    private func handle(_ event: WorkoutEvent) {
        switch event.kind {
        case let .snapshot(snapshot):
            applyWatchSnapshot(snapshot)
        case let .commands(commands):
            guard let sessionID = event.sessionID else { return }
            applyCommands(commands, to: sessionID, sentAt: event.createdAt)
        }
    }

    private func handle(_ payload: ApplicationContextPayload) {
        if let snapshot = payload.session {
            applyWatchSnapshot(snapshot)
        }
    }

    private func connectionChanged() {
        // Nakon aktivacije sesije: kontekst za sat i zadnje stanje sa sata koje je stiglo dok aplikacija nije radila.
        guard transport.isActivated else { return }
        if lastContext == nil { refreshContext() }
        if let snapshot = transport.receivedContext.session {
            applyWatchSnapshot(snapshot)
        }
    }

    /// Snimka treninga koji vodi sat. Trening koji vodi iPhone ovdje se ne mijenja: iPhone je za njega izvor istine.
    private func applyWatchSnapshot(_ snapshot: SessionSnapshot) {
        guard snapshot.controllingDevice == .watch, let context else { return }
        let store = SessionSnapshotStore(context: context)
        do {
            if let base = watchBases[snapshot.id], base.updatedAt > snapshot.updatedAt {
                // Starija snimka (npr. iz reda za slanje): osnova ostaje novija.
            } else {
                watchBases[snapshot.id] = snapshot
            }
            let outcome = try store.apply(snapshot)
            switch outcome {
            case .applied(let previous):
                if snapshot.state == .finished, previous != .finished, let session = try store.session(withID: snapshot.id) {
                    sessionFinishedOnWatch(session)
                } else if previous == nil {
                    // Trening je upravo započet na satu: podsjetnici za danas se otkazuju.
                    ReminderScheduler.refresh(context: context)
                }
                if snapshot.state != .active { watchBases[snapshot.id] = nil }
            case .discarded:
                watchBases[snapshot.id] = nil
                ReminderScheduler.refresh(context: context)
                purgeLater()
            case .ignoredOlder:
                break
            }
        } catch {
            logger.error("Snimka sa sata: \(error.localizedDescription)")
        }
    }

    /// Naredbe sa sata za trening koji vodi iPhone.
    private func applyCommands(_ commands: [WorkoutCommand], to sessionID: UUID, sentAt: Date) {
        guard let context else { return }
        let store = SessionSnapshotStore(context: context)
        do {
            guard let session = try store.session(withID: sessionID), session.controllingDevice == .phone,
                  session.state == .active else { return }
            let merged = SnapshotDiff.apply(commands, to: SessionSnapshot(session: session), at: max(Date(), sentAt))
            try store.apply(merged, force: true)
            switch merged.state {
            case .active:
                broadcast(merged)
            case .finished:
                broadcast(merged)
                sessionFinishedFromWatch(session)
            case .discarded:
                broadcast(merged)
                RestNotifications.cancel()
                ReminderScheduler.refresh(context: context)
                purgeLater()
            }
        } catch {
            logger.error("Naredbe sa sata: \(error.localizedDescription)")
        }
    }

    /// Sat je završio trening koji je vodio: raspored napreduje. U Zdravlje ga je već spremio sat.
    private func sessionFinishedOnWatch(_ session: Session) {
        guard let context else { return }
        _ = try? ScheduleEngine(context: context).sessionFinished(session)
        RestNotifications.cancel()
        ReminderScheduler.refresh(context: context)
        refreshContext()
    }

    /// Trening koji vodi iPhone završen je sa sata: isto kao završetak na iPhoneu.
    private func sessionFinishedFromWatch(_ session: Session) {
        guard let context else { return }
        _ = try? ScheduleEngine(context: context).sessionFinished(session)
        RestNotifications.cancel()
        ReminderScheduler.refresh(context: context)
        refreshContext()
        Task { await HealthService.shared.saveWorkout(of: session, context: context) }
    }

    /// Odbačeni trening briše se tek kad ga ekran koji ga je prikazivao zatvori.
    private func purgeLater() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let context = self?.context else { return }
            try? SessionSnapshotStore(context: context).purgeDiscarded()
        }
    }
}
