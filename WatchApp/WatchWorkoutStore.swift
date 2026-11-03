import Catalog
import Connectivity
import Foundation
import Models
import Observation
import OSLog
import Training
import Units
import WatchKit

/// Stanje aplikacije na satu: kontekst s iPhonea, aktivni trening i sažetak završenog.
///
/// * Trening koji vodi sat (`controllingDevice == .watch`) mijenja se lokalno preko `SnapshotEngine`,
///   sprema u datoteku i šalje iPhoneu kao snimka. Završni zapis ide zajamčenim kanalom, pa stigne
///   i kad je iPhone dio vremena izvan dosega.
/// * Trening koji vodi iPhone ovdje se zrcali: izmjene se odmah prikazuju i šalju iPhoneu kao naredbe.
@MainActor
@Observable
final class WatchWorkoutStore {
    static let shared = WatchWorkoutStore()

    struct Summary: Equatable {
        var name: String
        var duration: TimeInterval
        var completedSets: Int
        var volumeKg: Double
        var activeEnergyKilocalories: Double?
        var averageHeartRate: Double?
    }

    private(set) var context: WatchContextPayload = .empty
    private(set) var active: SessionSnapshot?
    private(set) var summary: Summary?
    /// Vježba prikazana na ekranu serije.
    var currentExerciseID: UUID?
    /// Pauza traje (timer još nije istekao).
    private(set) var isResting = false
    /// Sve serije su završene: nudi se završetak treninga.
    var showsFinishPrompt = false
    var errorText: String?

    let health = WorkoutSessionManager()

    @ObservationIgnored private let transport = WatchTransport.shared
    @ObservationIgnored private let logger = Logger(subsystem: "com.brunodobric.gymapp.watchkitapp", category: "Store")
    /// Zrcaljeni trening: stanje koje iPhone već zna (osnova za razliku).
    @ObservationIgnored private var mirrorBase: SessionSnapshot?
    @ObservationIgnored private var pendingSend: Task<Void, Never>?
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var isFinishing = false

    private init() {}

    var unit: WeightUnit { context.weightUnit }
    var isController: Bool { active?.controllingDevice == .watch }

    // MARK: Pokretanje aplikacije

    func start() {
        restore()
        transport.onEvent = { [weak self] event in self?.handle(event) }
        transport.onContext = { [weak self] payload in self?.handle(payload) }
        transport.onStateChange = { [weak self] in self?.connectionChanged() }
        transport.activate()
        // Trening završen ili odbačen prije gašenja aplikacije: završni zapis ide iPhoneu (opet, bez štete,
        // jer iPhone prepoznaje duplikat), a sat se vraća na početni ekran.
        if let active, active.state != .active {
            if isController { publish(active, reliably: true) }
            clearActive()
        }
        if isController { health.recover() }
        selectCurrentExercise()
        scheduleRestAlert()
    }

    // MARK: Trening na satu

    func begin(_ plan: PlannedWorkoutPayload) {
        guard active == nil else { return }
        let snapshot = SnapshotEngine.start(plan, device: .watch)
        active = snapshot
        summary = nil
        showsFinishPrompt = false
        currentExerciseID = snapshot.visibleExercises.first?.id
        persist()
        publish(snapshot, reliably: true)
        Task { await health.start(sessionID: snapshot.id, at: snapshot.startedAt) }
    }

    /// Serija koja je na redu u prikazanoj vježbi (u supersetu može biti iz druge vježbe grupe).
    var currentSet: (exercise: ExerciseSnapshot, set: SetSnapshot)? {
        guard let active, let id = currentExerciseID else { return nil }
        return SnapshotEngine(snapshot: active).nextSet(forExercise: id)
    }

    var currentExercise: ExerciseSnapshot? {
        guard let id = currentExerciseID else { return nil }
        return active?.exercise(withID: id)
    }

    var restTimer: RestTimer? {
        active.flatMap { SnapshotEngine(snapshot: $0).restTimer }
    }

    func completeCurrentSet() {
        guard let (exercise, set) = currentSet else { return }
        do {
            let rest = context.defaultRestSeconds
            try mutate { engine in
                _ = try engine.completeSet(set.id, defaultRestSeconds: rest)
            }
            WKInterfaceDevice.current().play(.success)
            guard let snapshot = active else { return }
            let engine = SnapshotEngine(snapshot: snapshot)
            if let next = engine.exerciseAfterCompleting(in: exercise.id) {
                // U supersetu ostaje prikazana ista vježba grupe, a serija dolazi po naizmjeničnom redu.
                let shown = currentExerciseID.map { engine.group(of: $0).map(\.id) } ?? []
                if !shown.contains(next) { currentExerciseID = next }
            } else {
                showsFinishPrompt = true
            }
        } catch WorkoutError.setIncomplete {
            WKInterfaceDevice.current().play(.failure)
            errorText = String(localized: "Upiši sve vrijednosti serije.")
        } catch {
            errorText = String(localized: "Serija se nije mogla spremiti.")
        }
    }

    func setValue(_ value: Double, field: WatchSetField, setID: UUID) {
        guard let set = active?.set(withID: setID), !field.matches(value, in: set, unit: unit) else { return }
        let displayUnit = unit
        mutate { engine in
            engine.updateSet(setID) { field.apply(value, to: &$0, unit: displayUnit) }
        }
    }

    func uncomplete(_ setID: UUID) {
        mutate { $0.uncompleteSet(setID) }
    }

    func addSet(to exerciseID: UUID) {
        mutate { _ = $0.addSet(to: exerciseID) }
        currentExerciseID = exerciseID
        showsFinishPrompt = false
    }

    func adjustRest(by seconds: Int) {
        mutate { $0.adjustRest(bySeconds: seconds) }
    }

    func skipRest() {
        mutate { $0.cancelRest() }
    }

    /// Prethodna ili sljedeća vježba (superset se preskače kao cjelina).
    func moveExercise(by offset: Int) {
        guard let active else { return }
        let engine = SnapshotEngine(snapshot: active)
        var heads: [UUID] = []
        var seenGroups = Set<UUID>()
        for exercise in active.visibleExercises {
            if let group = exercise.supersetGroupId {
                guard seenGroups.insert(group).inserted else { continue }
            }
            heads.append(exercise.id)
        }
        let currentHead = currentExerciseID.flatMap { id in engine.group(of: id).first?.id } ?? heads.first
        guard let index = heads.firstIndex(where: { $0 == currentHead }) else { return }
        let target = index + offset
        guard heads.indices.contains(target) else { return }
        currentExerciseID = heads[target]
        showsFinishPrompt = false
    }

    func canMoveExercise(by offset: Int) -> Bool {
        guard let active, let id = currentExerciseID else { return false }
        let engine = SnapshotEngine(snapshot: active)
        let visible = active.visibleExercises
        let group = Set(engine.group(of: id).map(\.id))
        guard let first = visible.firstIndex(where: { group.contains($0.id) }),
              let last = visible.lastIndex(where: { group.contains($0.id) }) else { return false }
        return offset < 0 ? first > 0 : last < visible.count - 1
    }

    func select(_ exerciseID: UUID) {
        currentExerciseID = exerciseID
        showsFinishPrompt = false
    }

    // MARK: Kraj

    /// Vraća false kad trening nema nijednu završenu seriju (nudi se odbacivanje).
    @discardableResult
    func finish() -> Bool {
        guard let active else { return false }
        // Završetak je već u tijeku (čeka se Zdravlje): to nije trening bez serija.
        if isFinishing { return true }
        var engine = SnapshotEngine(snapshot: active)
        do {
            try engine.finish()
        } catch {
            return false
        }
        if isController {
            isFinishing = true
            self.active = engine.snapshot
            persist()
            Task { await completeFinish() }
        } else {
            sendCommands(from: mirrorBase ?? active, to: engine.snapshot)
            showSummary(of: engine.snapshot, volume: engine.totalVolumeKg)
            clearActive()
        }
        return true
    }

    func discard() {
        guard let active else { return }
        var engine = SnapshotEngine(snapshot: active)
        engine.discard()
        if isController {
            health.discard()
            publish(engine.snapshot, reliably: true)
        } else {
            transport.sendReliably(WorkoutEvent(sessionID: active.id, origin: .watch, kind: .commands([.discard])))
        }
        clearActive()
    }

    func closeSummary() {
        summary = nil
    }

    /// Završetak treninga koji vodi sat: zatvara se sesija u Zdravlju, a završni zapis s pulsom i kalorijama
    /// šalje se iPhoneu zajamčenim kanalom.
    private func completeFinish() async {
        guard var snapshot = active else { return }
        let result = await endHealthSession(at: snapshot.endedAt ?? Date())
        var engine = SnapshotEngine(snapshot: snapshot)
        engine.recordHealth(
            workoutId: result.workoutId, activeEnergyKilocalories: result.activeEnergyKilocalories,
            averageHeartRate: result.averageHeartRate
        )
        snapshot = engine.snapshot
        publish(snapshot, reliably: true)
        showSummary(of: snapshot, volume: engine.totalVolumeKg)
        clearActive()
        isFinishing = false
    }

    /// Zdravlje ima najviše 10 sekundi za zatvaranje sesije. Ako ne odgovori, trening se ipak
    /// završava i šalje iPhoneu (bez pulsa i kalorija), da sat ne ostane zapeo u treningu.
    private func endHealthSession(at date: Date) async -> WorkoutSessionManager.Result {
        let save = context.savesToHealth
        let gate = ResumeGate()
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let result = await self.health.end(at: date, save: save)
                if gate.open() { continuation.resume(returning: result) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                if gate.open() { continuation.resume(returning: WorkoutSessionManager.Result()) }
            }
        }
    }

    private func showSummary(of snapshot: SessionSnapshot, volume: Double) {
        summary = Summary(
            name: snapshot.name,
            duration: (snapshot.endedAt ?? Date()).timeIntervalSince(snapshot.startedAt),
            completedSets: snapshot.completedSetCount,
            volumeKg: volume,
            activeEnergyKilocalories: snapshot.activeEnergyKilocalories,
            averageHeartRate: snapshot.averageHeartRate
        )
    }

    private func clearActive() {
        pendingSend?.cancel()
        restTask?.cancel()
        active = nil
        mirrorBase = nil
        currentExerciseID = nil
        isResting = false
        showsFinishPrompt = false
        persist()
    }

    // MARK: Promjene i slanje

    private func mutate(_ change: (inout SnapshotEngine) throws -> Void) rethrows {
        guard let active else { return }
        var engine = SnapshotEngine(snapshot: active)
        try change(&engine)
        guard engine.snapshot != active else { return }
        self.active = engine.snapshot
        persist()
        scheduleSend()
        scheduleRestAlert()
    }

    /// Kruna i brzi niz promjena šalju se jednom, nakon kratke stanke.
    private func scheduleSend() {
        pendingSend?.cancel()
        pendingSend = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.sendPending()
        }
    }

    private func sendPending() {
        guard let active else { return }
        if isController {
            publish(active, reliably: false)
        } else {
            sendCommands(from: mirrorBase ?? active, to: active)
            mirrorBase = active
        }
    }

    private func sendCommands(from base: SessionSnapshot, to edited: SessionSnapshot) {
        let commands = SnapshotDiff.commands(from: base, to: edited)
        guard !commands.isEmpty else { return }
        transport.sendReliably(WorkoutEvent(sessionID: edited.id, origin: .watch, kind: .commands(commands)))
    }

    /// Snimka treninga koji vodi sat. Uvijek ide i kao zadnje stanje (`applicationContext`), pa iPhone
    /// koji je bio izvan dosega dobije najnovije stanje čim se spoji.
    private func publish(_ snapshot: SessionSnapshot, reliably: Bool) {
        let event = WorkoutEvent(sessionID: snapshot.id, origin: .watch, kind: .snapshot(snapshot))
        if reliably {
            transport.sendReliably(event)
        } else {
            transport.sendIfReachable(event)
        }
        transport.updateContext(ApplicationContextPayload(session: snapshot))
    }

    // MARK: Primanje

    private func handle(_ event: WorkoutEvent) {
        switch event.kind {
        case let .snapshot(snapshot):
            applyPhoneSnapshot(snapshot)
        case let .commands(commands):
            guard let active, isController, active.id == event.sessionID, !isFinishing else { return }
            let merged = SnapshotDiff.apply(commands, to: active, at: max(Date(), event.createdAt))
            switch merged.state {
            case .active:
                self.active = merged
                persist()
                publish(merged, reliably: false)
                scheduleRestAlert()
                selectCurrentExercise()
            case .finished:
                // Trening je završen na iPhoneu: sat zatvara sesiju i šalje završni zapis.
                isFinishing = true
                self.active = merged
                persist()
                Task { await completeFinish() }
            case .discarded:
                health.discard()
                publish(merged, reliably: true)
                clearActive()
            }
        }
    }

    private func handle(_ payload: ApplicationContextPayload) {
        if let watchContext = payload.watchContext, watchContext != context {
            context = watchContext
            persist()
        }
        if let snapshot = payload.session {
            applyPhoneSnapshot(snapshot)
        } else if payload.watchContext != nil, active?.controllingDevice == .phone {
            // iPhone više nema aktivan trening: zrcaljeni trening se zatvara.
            clearActive()
        }
    }

    private func connectionChanged() {
        guard transport.isActivated else { return }
        handle(transport.receivedContext)
        // Trening koji vodi sat: iPhone dobiva zadnje stanje i nakon što je bio izvan dosega.
        if let active, isController { publish(active, reliably: false) }
    }

    /// Snimka treninga koji vodi iPhone. Trening koji vodi sat ima prednost i ne prepisuje se.
    private func applyPhoneSnapshot(_ snapshot: SessionSnapshot) {
        guard snapshot.controllingDevice == .phone else { return }
        if let active, active.controllingDevice == .watch { return }
        if snapshot.state != .active {
            if active?.id == snapshot.id { clearActive() }
            return
        }
        if let active, active.id == snapshot.id, !snapshot.isNewer(than: active.updatedAt) { return }
        active = snapshot
        mirrorBase = snapshot
        summary = nil
        persist()
        selectCurrentExercise()
        scheduleRestAlert()
    }

    // MARK: Pauza

    /// Haptika na kraju odmora. Dok traje sesija treninga, aplikacija radi i sa spuštenim zapešćem.
    private func scheduleRestAlert() {
        restTask?.cancel()
        guard let timer = restTimer, !timer.isExpired(at: Date()) else {
            isResting = false
            return
        }
        isResting = true
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timer.remaining(at: Date())))
            guard !Task.isCancelled, let self else { return }
            WKInterfaceDevice.current().play(.notification)
            self.isResting = false
            // Sat koji vodi trening gasi timer; zrcaljeni čeka da ga ugasi iPhone.
            if self.isController { self.skipRest() }
        }
    }

    private func selectCurrentExercise() {
        guard let active else { return }
        if let id = currentExerciseID, active.exercise(withID: id).map({ !$0.isRemoved }) == true { return }
        let visible = active.visibleExercises
        currentExerciseID = visible.first { !$0.isFullyCompleted }?.id ?? visible.first?.id
    }

    // MARK: Spremanje

    private func persist() {
        ComplicationState.update(context: context, active: active, restTimer: restTimer)
        do {
            try WatchStateFile.save(WatchStateFile.State(context: context, active: active, mirrorBase: mirrorBase))
        } catch {
            logger.error("Spremanje stanja: \(error.localizedDescription)")
        }
    }

    private func restore() {
        guard let state = WatchStateFile.load() else { return }
        context = state.context
        active = state.active
        mirrorBase = state.mirrorBase
    }
}

/// Propušta samo prvi od dva rezultata (Zdravlje ili istek vremena).
@MainActor
private final class ResumeGate {
    private var isOpen = true

    func open() -> Bool {
        defer { isOpen = false }
        return isOpen
    }
}
