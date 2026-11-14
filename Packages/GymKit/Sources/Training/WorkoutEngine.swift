import Catalog
import Foundation
import Models
import SwiftData
import Units

public enum WorkoutError: Error, Equatable {
    /// Već postoji trening u tijeku.
    case alreadyActive
    /// Serija nema sve potrebne vrijednosti za svoju vrstu unosa.
    case setIncomplete
    /// Trening nema nijednu završenu seriju.
    case nothingCompleted
    case needsTwoExercises
}

public struct WorkoutSummary: Equatable, Sendable {
    public struct ExerciseRecords: Equatable, Sendable {
        public let exerciseKey: String
        public let exerciseName: String
        public let records: [PersonalRecord]
    }

    public let durationSeconds: TimeInterval
    public let totalVolumeKg: Double
    public let completedSets: Int
    /// Tvrde serije (`SetMetrics.isHard`): radne serije bez preslabih.
    public let hardSets: Int
    /// Svi rekordi treninga po vježbi.
    public let records: [ExerciseRecords]
    /// Najviše tri istaknuta rekorda (`PRRanking`), od najznačajnijeg.
    public let highlights: [RecordHighlight]
    /// Rekordi koji nisu istaknuti ("i još 4 manja rekorda").
    public let otherRecordsCount: Int
    /// Kardio vježbe u treningu snage (`SessionCardio`); nil bez njih.
    public var cardio: CardioPart? = nil
}

/// Operacije nad aktivnim treningom. Svaka promjena odmah se sprema (specifikacija: oporavak prekinutog treninga),
/// pa gašenje aplikacije usred treninga ne gubi ništa.
public struct WorkoutEngine {
    public let context: ModelContext

    /// Broj radnih serija koje se stvaraju za vježbu bez povijesti.
    public static let defaultWorkingSets = 3

    public init(context: ModelContext) {
        self.context = context
    }

    private var queries: GymQueries { GymQueries(context: context) }

    // MARK: Trening

    @discardableResult
    public func startSession(
        name: String,
        kind: WorkoutKind = .strength,
        device: DeviceRole = .phone,
        templateId: UUID? = nil,
        scheduleId: UUID? = nil,
        now: Date = Date()
    ) throws -> Session {
        if try queries.activeSession() != nil { throw WorkoutError.alreadyActive }
        let session = Session(name: name, kind: kind, startedAt: now)
        session.controllingDevice = device
        session.templateId = templateId
        session.scheduleId = scheduleId
        session.lastActivityAt = now
        context.insert(session)
        try context.save()
        return session
    }

    /// Zatvara trening: briše nezavršene serije, prazne i izbačene vježbe. Trening bez ijedne završene serije
    /// ne može se spremiti (nudi se odbacivanje).
    public func finishSession(_ session: Session, notes: String? = nil, now: Date = Date()) throws {
        let hasCompleted = (session.exercises ?? []).contains { exercise in
            !exercise.isRemoved && (exercise.sets ?? []).contains { $0.isCompleted }
        }
        guard hasCompleted else { throw WorkoutError.nothingCompleted }

        for exercise in session.exercises ?? [] {
            if exercise.isRemoved {
                context.delete(exercise)
                continue
            }
            for set in exercise.sets ?? [] where !set.isCompleted {
                context.delete(set)
            }
            if (exercise.sets ?? []).allSatisfy({ !$0.isCompleted }) {
                context.delete(exercise)
            }
        }
        // Kardio: ukupna udaljenost treninga iz završenih serija (ručni unos). Izbačene vježbe su obrisane,
        // ali ih relacija do spremanja još sadrži, pa se preskaču izričito.
        let distance = (session.exercises ?? []).filter { !$0.isRemoved }.flatMap { $0.sets ?? [] }
            .filter(\.isCompleted).compactMap(\.distanceMeters).reduce(0, +)
        if distance > 0 { session.distanceMeters = distance }
        if let notes { session.notes = notes }
        session.state = .finished
        session.endedAt = now
        session.restTimerStartedAt = nil
        session.restTimerEndsAt = nil
        session.lastActivityAt = now
        try context.save()
    }

    /// Odbacivanje briše trening u cijelosti (i njegove vježbe i serije).
    public func discardSession(_ session: Session) throws {
        context.delete(session)
        try context.save()
    }

    /// Zatvara zaboravljeni trening na predloženi kraj (zadnja završena serija).
    public func closeStaleSession(_ session: Session) throws {
        let lastCompleted = lastCompletedSetAt(in: session)
        let assessment = RecoveryAssessment.assess(
            startedAt: session.startedAt, lastActivityAt: session.lastActivityAt,
            lastCompletedSetAt: lastCompleted, now: Date()
        )
        try finishSession(session, now: assessment.suggestedEnd)
    }

    public func lastCompletedSetAt(in session: Session) -> Date? {
        (session.exercises ?? []).flatMap { $0.sets ?? [] }.compactMap(\.completedAt).max()
    }

    // MARK: Vježbe

    /// Dodaje vježbu i stvara serije prema planu (`SetPlanner`): bez ciljeva onoliko zagrijavanja koliko je bilo
    /// prošli put i najčešći broj radnih serija iz zadnjih izvođenja, s pretpunjenim vrijednostima, a bez
    /// povijesti tri prazne radne serije. Ciljevi predloška određuju serije i ponavljanja, a uz korak težine
    /// plan predlaže veću težinu kad je prošli put dosegnuta gornja granica raspona.
    @discardableResult
    public func addExercise(
        _ ref: ExerciseRef,
        inputType: ExerciseInputType,
        to session: Session,
        restSeconds: Int? = nil,
        targets: [SetTarget] = [],
        weightStep: Double? = nil,
        unit: WeightUnit = .kilograms,
        now: Date = Date()
    ) throws -> SessionExercise {
        let order = ((session.exercises ?? []).map(\.orderIndex).max() ?? -1) + 1
        let exercise = SessionExercise(orderIndex: order, exercise: ref, inputType: inputType)
        exercise.restSeconds = restSeconds
        context.insert(exercise)
        exercise.session = session

        let performances = try previousPerformances(of: ref, before: session)
        let plan = SetPlanner.plan(
            previous: performances.first ?? [],
            recentWorkingCounts: performances.prefix(SmartDefaults.recentPerformanceCount).map { sets in
                sets.filter { $0.kind == .working }.count
            },
            targets: targets, inputType: inputType, weightStep: weightStep, unit: unit
        )
        for (index, values) in plan.sets.enumerated() {
            let set = SetLog(orderIndex: index, kind: values.kind)
            context.insert(set)
            set.exercise = exercise
            set.weightKg = values.weightKg
            set.reps = values.reps
            set.extraWeightKg = values.extraWeightKg
            set.durationSeconds = values.durationSeconds
            set.distanceMeters = values.distanceMeters
        }
        exercise.targetRepsMin = plan.repRange?.lower
        exercise.targetRepsMax = plan.repRange?.upper
        exercise.loadChangeKg = plan.loadChangeKg
        try touch(session, now: now)
        return exercise
    }

    /// Zamjenjuje vježbu u treningu drugom (zauzeta sprava). Bez završenih serija vježba se mijenja na istom
    /// mjestu, s istim brojem serija i vrijednostima iz povijesti nove vježbe. Sa završenim serijama stara
    /// vježba ostaje samo sa završenima, a nova dolazi odmah iza nje s preostalim serijama (barem jednom).
    /// Superset i pauza ostaju.
    @discardableResult
    public func replaceExercise(
        _ exercise: SessionExercise, with ref: ExerciseRef, inputType: ExerciseInputType, now: Date = Date()
    ) throws -> SessionExercise {
        guard let session = exercise.session else { return exercise }
        let sets = exercise.orderedSets
        let done = sets.filter(\.isCompleted)
        let pending = sets.filter { !$0.isCompleted }
        var visible = visibleExercises(in: session)
        let removed = removedExercises(in: session)

        let created = SessionExercise(orderIndex: exercise.orderIndex, exercise: ref, inputType: inputType)
        created.restSeconds = exercise.restSeconds
        created.supersetGroupId = exercise.supersetGroupId
        context.insert(created)
        created.session = session

        let previous = try previousSets(of: ref, before: session)
        let kinds = pending.isEmpty ? [SetKind.working] : pending.map(\.kind)
        var made: [SetValues] = []
        for (index, kind) in kinds.enumerated() {
            let position = made.filter { $0.kind == kind }.count
            let values = SmartDefaults.defaults(forPosition: position, kind: kind, previous: previous) ?? SetValues(kind: kind)
            made.append(values)
            let set = SetLog(orderIndex: index, kind: kind)
            context.insert(set)
            set.exercise = created
            set.weightKg = values.weightKg
            set.reps = values.reps
            set.extraWeightKg = values.extraWeightKg
            set.durationSeconds = values.durationSeconds
            set.distanceMeters = values.distanceMeters
        }

        let index = visible.firstIndex { $0.id == exercise.id } ?? max(visible.count - 1, 0)
        if done.isEmpty {
            if visible.indices.contains(index) { visible[index] = created } else { visible.append(created) }
            context.delete(exercise)
        } else {
            for set in pending { context.delete(set) }
            for (position, set) in done.enumerated() { set.orderIndex = position }
            visible.insert(created, at: min(index + 1, visible.count))
        }
        for (position, item) in (visible + removed).enumerated() { item.orderIndex = position }
        try touch(session, now: now)
        return created
    }

    @discardableResult
    public func addSet(to exercise: SessionExercise, kind: SetKind = .working, now: Date = Date()) throws -> SetLog {
        let previous = try previousSets(of: exercise.exercise, before: exercise.session)
        // Zagrijavanje ide ispred prve neodrađene serije (ili na kraj kad su sve odrađene),
        // jer se zagrijava prije serija koje tek slijede.
        let set = try appendSet(to: exercise, kind: kind, previous: previous, beforeIncomplete: kind == .warmUp)
        if let session = exercise.session { try touch(session, now: now) }
        return set
    }

    /// Briše seriju i vraća njezinu snimku, da se brisanje može poništiti (`restoreSet`).
    @discardableResult
    public func removeSet(_ set: SetLog, now: Date = Date()) throws -> RemovedSet {
        let removed = RemovedSet(
            id: set.id, position: set.orderIndex, values: set.values, completedAt: set.completedAt
        )
        let session = set.exercise?.session
        context.delete(set)
        if let exercise = set.exercise {
            for (index, remaining) in exercise.orderedSets.filter({ $0.id != set.id }).enumerated() {
                remaining.orderIndex = index
            }
        }
        if let session { try touch(session, now: now) } else { try context.save() }
        return removed
    }

    /// Vraća obrisanu seriju na njezino mjesto, s istim vrijednostima i oznakom završetka.
    @discardableResult
    public func restoreSet(_ removed: RemovedSet, to exercise: SessionExercise, now: Date = Date()) throws -> SetLog {
        var sets = exercise.orderedSets
        let set = SetLog(orderIndex: 0, kind: removed.values.kind)
        set.id = removed.id
        set.weightKg = removed.values.weightKg
        set.reps = removed.values.reps
        set.extraWeightKg = removed.values.extraWeightKg
        set.durationSeconds = removed.values.durationSeconds
        set.distanceMeters = removed.values.distanceMeters
        set.rpe = removed.values.rpe
        set.completedAt = removed.completedAt
        context.insert(set)
        set.exercise = exercise
        sets.insert(set, at: min(max(removed.position, 0), sets.count))
        for (index, item) in sets.enumerated() { item.orderIndex = index }
        if let session = exercise.session { try touch(session, now: now) } else { try context.save() }
        return set
    }

    /// Izbacivanje se može poništiti do kraja treninga (`restoreExercise`).
    public func removeExercise(_ exercise: SessionExercise, now: Date = Date()) throws {
        exercise.isRemoved = true
        if let session = exercise.session { try touch(session, now: now) }
    }

    public func restoreExercise(_ exercise: SessionExercise, now: Date = Date()) throws {
        exercise.isRemoved = false
        if let session = exercise.session {
            exercise.orderIndex = ((session.exercises ?? []).map(\.orderIndex).max() ?? -1) + 1
            try touch(session, now: now)
        }
    }

    public func removedExercises(in session: Session) -> [SessionExercise] {
        session.orderedExercises.filter(\.isRemoved)
    }

    public func visibleExercises(in session: Session) -> [SessionExercise] {
        session.orderedExercises.filter { !$0.isRemoved }
    }

    /// Drag & drop: premješta vidljive vježbe, izbačene ostaju na kraju.
    public func moveExercises(in session: Session, from source: IndexSet, to destination: Int, now: Date = Date()) throws {
        var visible = visibleExercises(in: session)
        visible.moveElements(fromOffsets: source, toOffset: destination)
        for (index, exercise) in (visible + removedExercises(in: session)).enumerated() {
            exercise.orderIndex = index
        }
        try touch(session, now: now)
    }

    // MARK: Supersetovi

    /// Spaja vježbe u superset i postavlja ih jednu do druge, na mjesto prve među njima.
    public func makeSuperset(_ exercises: [SessionExercise], in session: Session, now: Date = Date()) throws {
        guard exercises.count >= 2 else { throw WorkoutError.needsTwoExercises }
        let group = UUID()
        let selected = Set(exercises.map(\.id))
        let ordered = visibleExercises(in: session)
        guard let anchor = ordered.firstIndex(where: { selected.contains($0.id) }) else { return }
        let members = ordered.filter { selected.contains($0.id) }
        let others = ordered.filter { !selected.contains($0.id) }
        let insertAt = min(anchor, others.count)
        let result = Array(others[..<insertAt]) + members + Array(others[insertAt...])
        for member in members { member.supersetGroupId = group }
        for (index, exercise) in (result + removedExercises(in: session)).enumerated() {
            exercise.orderIndex = index
        }
        try touch(session, now: now)
    }

    public func removeFromSuperset(_ exercise: SessionExercise, now: Date = Date()) throws {
        let group = exercise.supersetGroupId
        exercise.supersetGroupId = nil
        if let session = exercise.session {
            // Superset s jednom vježbom nema smisla.
            let rest = visibleExercises(in: session).filter { $0.supersetGroupId == group && group != nil }
            if rest.count == 1 { rest[0].supersetGroupId = nil }
            try touch(session, now: now)
        }
    }

    /// Vježbe u istom supersetu (ili sama vježba), po redoslijedu.
    public func group(of exercise: SessionExercise) -> [SessionExercise] {
        guard let id = exercise.supersetGroupId, let session = exercise.session else { return [exercise] }
        return visibleExercises(in: session).filter { $0.supersetGroupId == id }
    }

    // MARK: Serije i rest timer

    /// Označava seriju završenom i vraća rest timer koji treba pokrenuti (nil kad je pauza 0).
    /// Ista zadana pauza za sve vježbe (demo podaci, testovi).
    @discardableResult
    public func completeSet(_ set: SetLog, defaultRestSeconds: Int, now: Date = Date()) throws -> RestTimer? {
        try completeSet(set, restDefaults: RestDefaults(uniform: defaultRestSeconds), isCompound: { _ in nil }, now: now)
    }

    /// Označava seriju završenom i vraća rest timer koji treba pokrenuti (nil kad je pauza 0).
    /// Vježba bez vlastite pauze dobiva zadanu prema vrsti (`RestDefaults`); `isCompound` prima
    /// ključ vježbe (`ExerciseRef.key`).
    @discardableResult
    public func completeSet(
        _ set: SetLog, restDefaults: RestDefaults, isCompound: (String) -> Bool?, now: Date = Date()
    ) throws -> RestTimer? {
        guard let exercise = set.exercise, let session = exercise.session else { return nil }
        guard SetMetrics.isComplete(set.values, inputType: exercise.inputType) else { throw WorkoutError.setIncomplete }
        set.completedAt = now

        let members = group(of: exercise)
        let position = members.firstIndex { $0.id == exercise.id } ?? 0
        let configured = exercise.restSeconds ?? members.last?.restSeconds
        let defaultSeconds = restDefaults.seconds(isCompound: members.map { isCompound($0.exercise.key) })
        let seconds = RestPolicy.seconds(
            positionInGroup: position, groupSize: members.count, configured: configured, defaultSeconds: defaultSeconds
        )
        let timer = seconds > 0 ? RestTimer(startedAt: now, seconds: seconds) : nil
        session.restTimerStartedAt = timer?.startedAt
        session.restTimerEndsAt = timer?.endsAt
        try touch(session, now: now)
        return timer
    }

    public func uncompleteSet(_ set: SetLog, now: Date = Date()) throws {
        set.completedAt = nil
        if let session = set.exercise?.session { try touch(session, now: now) }
    }

    public func restTimer(of session: Session) -> RestTimer? {
        guard let start = session.restTimerStartedAt, let end = session.restTimerEndsAt else { return nil }
        return RestTimer(startedAt: start, endsAt: end)
    }

    @discardableResult
    public func adjustRest(of session: Session, bySeconds delta: Int, now: Date = Date()) throws -> RestTimer? {
        guard let timer = restTimer(of: session) else { return nil }
        let adjusted = timer.adjusted(bySeconds: delta, at: now)
        session.restTimerEndsAt = adjusted.endsAt
        try touch(session, now: now)
        return adjusted
    }

    public func cancelRest(of session: Session, now: Date = Date()) throws {
        session.restTimerStartedAt = nil
        session.restTimerEndsAt = nil
        try touch(session, now: now)
    }

    /// Sprema izmjenu (npr. težine ili ponavljanja) i bilježi aktivnost.
    public func touch(_ session: Session, now: Date = Date()) throws {
        session.lastActivityAt = now
        try context.save()
    }

    // MARK: Sažetak i rekordi

    /// Sažetak treninga s osobnim rekordima. Rekordi se uspoređuju samo s ranije završenim treninzima.
    /// - Parameters:
    ///   - excludedExercises: ključevi vježbi koje je korisnik isključio iz rekorda (`UserSettings.prExcludedExerciseKeys`)
    ///   - isCompound: je li vježba (po ključu) složena, za rang istaknutih rekorda
    public func summary(
        of session: Session,
        trackedKinds: Set<PRKind> = Set(PRKind.allCases),
        excludedExercises: Set<String> = [],
        isCompound: (String) -> Bool? = { _ in nil },
        isCardio: (String) -> Bool = { _ in false }
    ) throws -> WorkoutSummary {
        var volume = 0.0
        var completed = 0
        var hard = 0
        var records: [WorkoutSummary.ExerciseRecords] = []
        var candidates: [RecordCandidate] = []
        for exercise in visibleExercises(in: session) {
            let done = exercise.orderedSets.filter(\.isCompleted).map(\.values)
            completed += done.count
            // Kardio nije tvrda serija: 20 minuta trake ne broji se uz serije snage.
            if !isCardio(exercise.exerciseKey) { hard += done.filter(SetMetrics.isHard).count }
            volume += done.reduce(0) { $0 + SetMetrics.volume($1, inputType: exercise.inputType) }

            let key = exercise.exerciseKey
            guard !trackedKinds.isEmpty, !excludedExercises.contains(key) else { continue }
            let history = try recordHistory(of: exercise.exercise, before: session, inputType: exercise.inputType)
            let found = PersonalRecordDetector.records(
                current: done, history: history, inputType: exercise.inputType, kinds: trackedKinds, date: session.startedAt
            )
            if !found.isEmpty {
                records.append(.init(exerciseKey: key, exerciseName: exercise.exerciseName, records: found))
                candidates.append(RecordCandidate(
                    exerciseKey: key, exerciseName: exercise.exerciseName, records: found, isCompound: isCompound(key)
                ))
            }
        }
        let ranked = PRRanking.highlights(candidates)
        let end = session.endedAt ?? Date()
        return WorkoutSummary(
            durationSeconds: max(0, end.timeIntervalSince(session.startedAt)),
            totalVolumeKg: volume, completedSets: completed, hardSets: hard, records: records,
            highlights: ranked.shown, otherRecordsCount: ranked.hiddenCount,
            cardio: SessionCardio.part(of: session, isCardio: isCardio)
        )
    }

    // MARK: Pomoćno

    /// Dodaje seriju na kraj vježbe, ili ispred prve neodrađene serije kad je `beforeIncomplete` (zagrijavanje).
    @discardableResult
    private func appendSet(
        to exercise: SessionExercise, kind: SetKind, previous: [SetValues], beforeIncomplete: Bool = false
    ) throws -> SetLog {
        var existing = exercise.orderedSets
        let insertIndex = beforeIncomplete
            ? existing.firstIndex { !$0.isCompleted } ?? existing.count
            : existing.count
        let before = existing[..<insertIndex]
        let position = before.filter { $0.kind == kind }.count
        let set = SetLog(orderIndex: insertIndex, kind: kind)
        context.insert(set)
        set.exercise = exercise
        existing.insert(set, at: insertIndex)
        for (index, item) in existing.enumerated() { item.orderIndex = index }

        var defaults = SmartDefaults.defaults(forPosition: position, kind: kind, previous: previous)
        if defaults == nil, let last = before.last(where: { $0.kind == kind })
            ?? existing.last(where: { $0.kind == kind && $0.id != set.id }) {
            // Bez povijesti nova serija preuzima vrijednosti prethodne serije iste vrste u ovom treningu.
            defaults = SmartDefaults.defaults(forPosition: 0, kind: kind, previous: [last.values])
        }
        if let defaults {
            set.weightKg = defaults.weightKg
            set.reps = defaults.reps
            set.extraWeightKg = defaults.extraWeightKg
            set.durationSeconds = defaults.durationSeconds
            set.distanceMeters = defaults.distanceMeters
        }
        return set
    }

    /// Serije zadnjeg završenog izvođenja vježbe (izvor smart defaultsa), prvo u istom treningu (`templateId`).
    private func previousSets(of ref: ExerciseRef, before session: Session?) throws -> [SetValues] {
        try previousPerformances(of: ref, before: session).first ?? []
    }

    /// Završene serije ranijih izvođenja vježbe, od najnovijeg. Kad je trening pokrenut iz predloška,
    /// izvođenja iz istog predloška dolaze prva: ista vježba u "Noge, teško" (5 × 5) i "Noge, lagano"
    /// (3 × 12) inače bi pretpopunila težinu drugog dana.
    public func previousPerformances(of ref: ExerciseRef, before session: Session?) throws -> [[SetValues]] {
        let all = try finishedExercises(of: ref, before: session).compactMap { exercise -> (UUID?, [SetValues])? in
            let sets = exercise.orderedSets.filter(\.isCompleted).map(\.values)
            return sets.isEmpty ? nil : (exercise.session?.templateId, sets)
        }
        guard let templateId = session?.templateId else { return all.map(\.1) }
        let same = all.filter { $0.0 == templateId }.map(\.1)
        let other = all.filter { $0.0 != templateId }.map(\.1)
        return same + other
    }

    /// Ranija izvođenja vježbe za rekorde, od najstarijeg prema najnovijem, s datumima treninga.
    private func recordHistory(of ref: ExerciseRef, before session: Session?, inputType: ExerciseInputType) throws -> RecordHistory {
        var history = RecordHistory()
        for exercise in try finishedExercises(of: ref, before: session).reversed() {
            let done = exercise.orderedSets.filter(\.isCompleted).map(\.values)
            history.add(done, inputType: inputType, date: exercise.session?.startedAt)
        }
        return history
    }

    /// Izvođenja vježbe u ranije završenim treninzima, od najnovijeg prema starijem, bez čitanja serija.
    private func finishedExercises(of ref: ExerciseRef, before session: Session?) throws -> [SessionExercise] {
        let key = ref.key
        let finished = SessionState.finished.rawValue
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false && $0.session?.stateRaw == finished }
        )
        let currentId = session?.id
        let cutoff = session?.startedAt ?? .distantFuture
        return try context.fetch(descriptor)
            .compactMap { exercise -> (Date, SessionExercise)? in
                guard let owner = exercise.session, owner.state == .finished,
                      owner.id != currentId, owner.startedAt < cutoff else { return nil }
                return (owner.startedAt, exercise)
            }
            .sorted { $0.0 > $1.0 }
            .map(\.1)
    }
}

/// Obrisana serija, zapamćena dok korisnik ne potvrdi brisanje (traka "Poništi").
public struct RemovedSet: Equatable, Sendable {
    public let id: UUID
    /// Mjesto serije u vježbi prije brisanja.
    public let position: Int
    public let values: SetValues
    public let completedAt: Date?

    public init(id: UUID, position: Int, values: SetValues, completedAt: Date?) {
        self.id = id
        self.position = position
        self.values = values
        self.completedAt = completedAt
    }
}
