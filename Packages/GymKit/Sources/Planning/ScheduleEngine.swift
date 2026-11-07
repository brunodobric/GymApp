import Catalog
import Foundation
import Models
import SwiftData

/// Vježba kakva će biti u sljedećem treningu, nakon privremenih izmjena ciklusa.
public struct PlannedExercise: Equatable, Sendable, Identifiable {
    public let source: UUID
    public let ref: ExerciseRef
    public let inputType: ExerciseInputType
    /// Vježba je zamijenjena u ovom ciklusu (ciljevi originalne vježbe se ne primjenjuju).
    public let isReplacement: Bool

    public init(source: UUID, ref: ExerciseRef, inputType: ExerciseInputType, isReplacement: Bool) {
        self.source = source
        self.ref = ref
        self.inputType = inputType
        self.isReplacement = isReplacement
    }

    public var id: UUID { source }
}

/// Sljedeći trening koji "Započni" nudi za jedan raspored.
public struct PlannedWorkout {
    public let schedule: Schedule
    public let item: ScheduleItem
    public let template: WorkoutTemplate
    public let cycle: Int
    public let exercises: [PlannedExercise]
}

/// Napredovanje kroz raspored. Osnova je redoslijed, ne kalendar: propušteni dan ništa ne pomiče.
///
/// Sljedeći trening je prvi trening u nizu koji u tekućem ciklusu nije odrađen ni preskočen. Odrađeni
/// treninzi pamte se kao izmjene ciklusa (`completedWorkout`), pa premještanje ili umetanje treninga ne
/// ostavlja neodrađeni trening iza sebe. `currentPosition` je indeks iza zadnjeg odrađenog treninga prije
/// prvog neodrađenog: sve ispred nje je odrađeno, preskočeno ili dan odmora.
public struct ScheduleEngine {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Rasporedi

    @discardableResult
    public func createSchedule(name: String, cycleCount: Int? = nil) throws -> Schedule {
        let schedule = Schedule(name: name)
        schedule.cycleCount = cycleCount
        schedule.isActive = true
        context.insert(schedule)
        try context.save()
        return schedule
    }

    @discardableResult
    public func addWorkout(_ template: WorkoutTemplate, to schedule: Schedule) throws -> ScheduleItem {
        try append(kind: .workout, templateId: template.id, to: schedule)
    }

    /// Novi prazni trening (predložak) koji odmah ide na kraj niza. Za raspored koji se slaže prije
    /// nego što postoji ijedan trening: vježbe se dodaju u uređivaču novog treninga.
    @discardableResult
    public func addNewWorkout(named name: String, to schedule: Schedule) throws -> WorkoutTemplate {
        let template = try TemplateEngine(context: context).createTemplate(name: name)
        try addWorkout(template, to: schedule)
        return template
    }

    /// Umeće više treninga odjednom (odabir više treninga ili drag & drop na iPadu), redom kojim su zadani.
    /// Bez `index` idu na kraj niza. Umetnuti trening nije odrađen, pa i ispred odrađenih postaje sljedeći.
    @discardableResult
    public func insertWorkouts(_ templates: [WorkoutTemplate], into schedule: Schedule, at index: Int? = nil) throws -> [ScheduleItem] {
        try recordLegacyProgress(of: schedule)
        var ordered = schedule.orderedItems
        let position = min(max(index ?? ordered.count, 0), ordered.count)
        let added = templates.map { template in
            let item = ScheduleItem(orderIndex: 0, kind: .workout, workoutTemplateId: template.id)
            context.insert(item)
            item.schedule = schedule
            return item
        }
        ordered.insert(contentsOf: added, at: position)
        for (order, item) in ordered.enumerated() { item.orderIndex = order }
        try updatePosition(of: schedule, items: ordered)
        try context.save()
        return added
    }

    @discardableResult
    public func addRestDay(to schedule: Schedule) throws -> ScheduleItem {
        try append(kind: .restDay, templateId: nil, to: schedule)
    }

    /// Briše raspored zajedno s njegovim izmjenama ciklusa. Izmjene nemaju vezu na raspored,
    /// pa bi inače ostale u bazi (i u iCloudu) zauvijek.
    public func delete(_ schedule: Schedule) throws {
        try deleteOverrides(of: schedule) { _ in true }
        context.delete(schedule)
        try context.save()
    }

    public func removeItem(_ item: ScheduleItem) throws {
        let schedule = item.schedule
        let removedIndex = schedule?.orderedItems.firstIndex { $0.id == item.id }
        context.delete(item)
        if let schedule {
            for (index, remaining) in schedule.orderedItems.filter({ $0.id != item.id }).enumerated() {
                remaining.orderIndex = index
            }
            if let removedIndex, removedIndex < schedule.currentPosition {
                schedule.currentPosition -= 1
            }
        }
        try context.save()
        if let schedule { try rollIfCycleComplete(schedule) }
    }

    /// Premješta stavke. Odrađeni treninzi ostaju odrađeni, a sljedeći je prvi neodrađeni u novom redoslijedu.
    public func moveItems(in schedule: Schedule, from source: IndexSet, to destination: Int) throws {
        try recordLegacyProgress(of: schedule)
        var ordered = schedule.orderedItems
        ordered.moveElements(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() { item.orderIndex = index }
        try updatePosition(of: schedule, items: ordered)
        try context.save()
    }

    /// Pokreće raspored ispočetka (prvi ciklus, prva stavka).
    public func restart(_ schedule: Schedule) throws {
        // Izmjene starog prolaza (preskakanja, zamjene) inače bi vrijedile i za novi ciklus 1.
        try deleteOverrides(of: schedule) { _ in true }
        schedule.currentCycle = 1
        schedule.currentPosition = 0
        schedule.isActive = true
        try context.save()
        try rollIfCycleComplete(schedule)
    }

    /// Uobičajena gornja granica broja ciklusa u uređivaču.
    public static let usualMaxCycleCount = 52

    /// Dopušteni broj ciklusa: ne manje od tekućeg ciklusa, a gornja granica raste s rasporedom koji je
    /// već prošao `usualMaxCycleCount` ciklusa (inače bi raspon bio prazan i `Stepper` bi srušio aplikaciju).
    public static func cycleCountRange(currentCycle: Int) -> ClosedRange<Int> {
        let lower = max(currentCycle, 1)
        return lower...max(usualMaxCycleCount, lower)
    }

    public func setActive(_ active: Bool, for schedule: Schedule) throws {
        schedule.isActive = active
        try context.save()
    }

    // MARK: Što je sljedeće

    /// Stavka na kojoj je raspored stao (može biti i rest dan), ili nil kad je ciklus na kraju.
    public func currentItem(of schedule: Schedule) -> ScheduleItem? {
        let items = schedule.orderedItems
        return items.indices.contains(schedule.currentPosition) ? items[schedule.currentPosition] : nil
    }

    /// Indeks sljedećeg treninga (ne rest dana, ne preskočenog) u tekućem ciklusu.
    public func nextWorkoutIndex(in schedule: Schedule) throws -> Int? {
        let items = schedule.orderedItems
        guard schedule.currentPosition < items.count else { return nil }
        let passed = try passedItemIds(of: schedule, cycle: schedule.currentCycle)
        for index in schedule.currentPosition..<items.count {
            let item = items[index]
            if item.kind == .workout, !passed.contains(item.id), try isPlayable(item) { return index }
        }
        return nil
    }

    /// Što "Započni" nudi: sljedeći neodrađeni trening aktivnog rasporeda. Stavke čiji je predložak
    /// obrisan se prelaze.
    public func nextWorkout(of schedule: Schedule) throws -> PlannedWorkout? {
        guard schedule.isActive else { return nil }
        let items = schedule.orderedItems
        let passed = try passedItemIds(of: schedule, cycle: schedule.currentCycle)
        let changes = try overrides(of: schedule, cycle: schedule.currentCycle)
        var index = schedule.currentPosition
        while index < items.count {
            let item = items[index]
            if item.kind == .workout, !passed.contains(item.id),
               let templateId = item.workoutTemplateId, let template = try template(withID: templateId) {
                return PlannedWorkout(
                    schedule: schedule, item: item, template: template, cycle: schedule.currentCycle,
                    exercises: effectiveExercises(of: template, overrides: changes.filter { $0.scheduleItemId == item.id })
                )
            }
            index += 1
        }
        return nil
    }

    /// Treninzi aktivnog rasporeda koje korisnik može pokrenuti umjesto sljedećeg, redom kao u nizu.
    /// Svaki predložak je jednom: kad se ponavlja u nizu, uzima se prva stavka koja u ovom ciklusu još
    /// nije odrađena (njezine izmjene ciklusa vrijede), inače prva u nizu. Kao i izvan rasporeda, nude se
    /// samo treninzi snage s vježbama (`TemplateStarter.startable`). Odrađeni trening se u ciklusu bilježi
    /// kao odrađen (`sessionFinished`), pa ga "Započni" više ne nudi.
    public func workoutChoices(of schedule: Schedule) throws -> [PlannedWorkout] {
        guard schedule.isActive else { return [] }
        let items = schedule.orderedItems
        let done = try doneItemIds(of: schedule)
        var chosen: [UUID: Int] = [:]
        var order: [UUID] = []
        for (index, item) in items.enumerated() where item.kind == .workout {
            guard let templateId = item.workoutTemplateId else { continue }
            if let existing = chosen[templateId] {
                if done.contains(items[existing].id) && !done.contains(item.id) {
                    chosen[templateId] = index
                }
            } else {
                chosen[templateId] = index
                order.append(templateId)
            }
        }
        let changes = try overrides(of: schedule, cycle: schedule.currentCycle)
        return try order.compactMap { templateId in
            guard let index = chosen[templateId], let template = try template(withID: templateId),
                  !TemplateStarter.startable([template]).isEmpty else { return nil }
            let item = items[index]
            return PlannedWorkout(
                schedule: schedule, item: item, template: template, cycle: schedule.currentCycle,
                exercises: effectiveExercises(of: template, overrides: changes.filter { $0.scheduleItemId == item.id })
            )
        }
    }

    /// Sljedeći trening svakog aktivnog rasporeda.
    public func upcomingWorkouts() throws -> [PlannedWorkout] {
        let schedules = try context.fetch(FetchDescriptor<Schedule>(sortBy: [SortDescriptor(\.createdAt)]))
        return try schedules.compactMap { try nextWorkout(of: $0) }
    }

    // MARK: Napredovanje

    /// Poziva se kad je trening završen. Bilježi trening kao odrađen u tekućem ciklusu: sljedeći trening
    /// ako je to on, inače prvu još neodrađenu stavku s tim treningom (trening odabran mimo reda).
    /// Vraća true kad je raspored napredovao.
    @discardableResult
    public func sessionFinished(_ session: Session) throws -> Bool {
        guard let scheduleId = session.scheduleId, let templateId = session.templateId,
              let schedule = try fetchSchedule(withID: scheduleId), schedule.isActive,
              let next = try nextWorkoutIndex(in: schedule) else { return false }
        try recordLegacyProgress(of: schedule)
        let items = schedule.orderedItems
        let passed = try passedItemIds(of: schedule, cycle: schedule.currentCycle)
        let index: Int
        if items[next].workoutTemplateId == templateId {
            index = next
        } else if let other = items.indices.first(where: {
            items[$0].kind == .workout && items[$0].workoutTemplateId == templateId && !passed.contains(items[$0].id)
        }) {
            index = other
        } else {
            return false
        }
        context.insert(CycleOverride(
            scheduleId: schedule.id, cycleNumber: schedule.currentCycle, scheduleItemId: items[index].id, kind: .completedWorkout
        ))
        try context.save()
        try updatePosition(of: schedule, items: items)
        try context.save()
        try rollIfCycleComplete(schedule)
        return true
    }

    /// Preskače sljedeći trening u ovom ciklusu. Poništava se s `unskip` dok raspored ne prođe tu stavku.
    @discardableResult
    public func skipNextWorkout(of schedule: Schedule) throws -> CycleOverride? {
        guard let index = try nextWorkoutIndex(in: schedule) else { return nil }
        let item = schedule.orderedItems[index]
        let change = CycleOverride(
            scheduleId: schedule.id, cycleNumber: schedule.currentCycle, scheduleItemId: item.id, kind: .skipWorkout
        )
        context.insert(change)
        try context.save()
        try rollIfCycleComplete(schedule)
        return change
    }

    /// Preskočeni treninzi tekućeg ciklusa, redom kao u nizu, s nazivom treninga.
    public func skippedWorkouts(of schedule: Schedule) throws -> [SkippedWorkout] {
        let skips = try overrides(of: schedule, cycle: schedule.currentCycle).filter { $0.kind == .skipWorkout }
        return try schedule.orderedItems.compactMap { item in
            guard let change = skips.first(where: { $0.scheduleItemId == item.id }) else { return nil }
            let name = try item.workoutTemplateId.flatMap { try template(withID: $0) }?.name
            return SkippedWorkout(change: change, templateName: name ?? "")
        }
    }

    /// Vraća preskočeni trening. Moguće samo dok je ciklus još tekući.
    public func unskip(_ change: CycleOverride, in schedule: Schedule) throws {
        guard change.kind == .skipWorkout, change.cycleNumber == schedule.currentCycle else { return }
        try recordLegacyProgress(of: schedule)
        context.delete(change)
        try context.save()
        // Vraćeni trening ispred pozicije ponovno je na redu.
        try updatePosition(of: schedule, items: schedule.orderedItems)
        try context.save()
    }

    // MARK: Privremene izmjene

    /// Izbacuje vježbu iz tekućeg ciklusa. Predložak i budući ciklusi ostaju nepromijenjeni.
    @discardableResult
    public func removeExercise(_ exercise: TemplateExercise, from planned: PlannedWorkout) throws -> CycleOverride {
        try clearOverrides(for: exercise, in: planned)
        let change = CycleOverride(
            scheduleId: planned.schedule.id, cycleNumber: planned.cycle, scheduleItemId: planned.item.id,
            kind: .removeExercise
        )
        change.targetExerciseKey = exercise.exercise.key
        context.insert(change)
        try context.save()
        return change
    }

    /// Zamjenjuje vježbu u tekućem ciklusu.
    @discardableResult
    public func replaceExercise(
        _ exercise: TemplateExercise, with ref: ExerciseRef, inputType: ExerciseInputType, in planned: PlannedWorkout
    ) throws -> CycleOverride {
        try clearOverrides(for: exercise, in: planned)
        let change = CycleOverride(
            scheduleId: planned.schedule.id, cycleNumber: planned.cycle, scheduleItemId: planned.item.id,
            kind: .replaceExercise
        )
        change.targetExerciseKey = exercise.exercise.key
        change.replacement = ref
        change.replacementInputType = inputType
        context.insert(change)
        try context.save()
        return change
    }

    /// Poništava izmjenu (izbacivanje ili zamjenu). Preskakanje se poništava s `unskip`.
    public func undo(_ change: CycleOverride) throws {
        context.delete(change)
        try context.save()
    }

    /// Vježbe predloška nakon izmjena: izbačene nema, zamijenjene su zamijenjene.
    public func effectiveExercises(of template: WorkoutTemplate, overrides: [CycleOverride]) -> [PlannedExercise] {
        template.orderedExercises.compactMap { exercise in
            let key = exercise.exercise.key
            let match = overrides.first { $0.targetExerciseKey == key && $0.kind != .skipWorkout }
            if let match, match.kind == .removeExercise { return nil }
            if let match, match.kind == .replaceExercise, let replacement = match.replacement {
                return PlannedExercise(
                    source: exercise.id, ref: replacement,
                    inputType: match.replacementInputType ?? exercise.inputType, isReplacement: true
                )
            }
            return PlannedExercise(
                source: exercise.id, ref: exercise.exercise, inputType: exercise.inputType, isReplacement: false
            )
        }
    }

    public func overrides(of schedule: Schedule, cycle: Int) throws -> [CycleOverride] {
        let id: UUID? = schedule.id
        let descriptor = FetchDescriptor<CycleOverride>(
            predicate: #Predicate { $0.scheduleId == id && $0.cycleNumber == cycle }
        )
        return try context.fetch(descriptor)
    }

    /// Briše izmjene rasporeda koje zadovoljavaju uvjet (bez spremanja).
    private func deleteOverrides(of schedule: Schedule, where shouldDelete: (CycleOverride) -> Bool) throws {
        let id: UUID? = schedule.id
        let descriptor = FetchDescriptor<CycleOverride>(predicate: #Predicate { $0.scheduleId == id })
        for change in try context.fetch(descriptor) where shouldDelete(change) {
            context.delete(change)
        }
    }

    // MARK: Pomoćno

    private func clearOverrides(for exercise: TemplateExercise, in planned: PlannedWorkout) throws {
        let key = exercise.exercise.key
        for existing in try overrides(of: planned.schedule, cycle: planned.cycle)
        where existing.scheduleItemId == planned.item.id && existing.targetExerciseKey == key {
            context.delete(existing)
        }
    }

    /// Kad u ciklusu nema više treninga, počinje sljedeći; nakon zadnjeg ciklusa raspored postaje neaktivan.
    /// Ciklus završava odmah nakon zadnjeg treninga, rest dani na kraju niza se ne čekaju.
    private func rollIfCycleComplete(_ schedule: Schedule) throws {
        guard schedule.isActive else { return }
        // Raspored bez ijednog treninga s postojećim predloškom nema ciklusa koji bi se mogli odraditi.
        guard try schedule.orderedItems.contains(where: { try isPlayable($0) }) else { return }
        while try nextWorkoutIndex(in: schedule) == nil {
            if let limit = schedule.cycleCount, schedule.currentCycle >= limit {
                schedule.isActive = false
                schedule.currentPosition = schedule.orderedItems.count
                try context.save()
                return
            }
            schedule.currentCycle += 1
            schedule.currentPosition = 0
            // Izmjene prošlih ciklusa više ništa ne mijenjaju, a inače bi se gomilale zauvijek.
            let current = schedule.currentCycle
            try deleteOverrides(of: schedule) { $0.cycleNumber < current }
            try context.save()
        }
    }

    /// Stavka je trening čiji predložak još postoji.
    private func isPlayable(_ item: ScheduleItem) throws -> Bool {
        guard item.kind == .workout, let templateId = item.workoutTemplateId else { return false }
        return try template(withID: templateId) != nil
    }

    @discardableResult
    private func append(kind: ScheduleItemKind, templateId: UUID?, to schedule: Schedule) throws -> ScheduleItem {
        let order = ((schedule.items ?? []).map(\.orderIndex).max() ?? -1) + 1
        let item = ScheduleItem(orderIndex: order, kind: kind, workoutTemplateId: templateId)
        context.insert(item)
        item.schedule = schedule
        try context.save()
        return item
    }

    private func template(withID id: UUID) throws -> WorkoutTemplate? {
        var descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchSchedule(withID id: UUID) throws -> Schedule? {
        var descriptor = FetchDescriptor<Schedule>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

// MARK: Odrađeni treninzi u ciklusu

extension ScheduleEngine {
    /// Stavke koje raspored u ciklusu prelazi: odrađene i preskočene.
    private func passedItemIds(of schedule: Schedule, cycle: Int) throws -> Set<UUID> {
        Set(try overrides(of: schedule, cycle: cycle)
            .filter { $0.kind == .skipWorkout || $0.kind == .completedWorkout }
            .compactMap(\.scheduleItemId))
    }

    /// Treninzi odrađeni u tekućem ciklusu: zabilježeni i (iz starijih verzija) oni ispred pozicije.
    private func doneItemIds(of schedule: Schedule) throws -> Set<UUID> {
        let recorded = try overrides(of: schedule, cycle: schedule.currentCycle)
            .filter { $0.kind == .completedWorkout }.compactMap(\.scheduleItemId)
        let items = schedule.orderedItems
        let beforePosition = items.prefix(min(schedule.currentPosition, items.count)).filter { $0.kind == .workout }.map(\.id)
        return Set(recorded).union(beforePosition)
    }

    /// Starije verzije pamtile su napredak samo pozicijom. Prije promjene redoslijeda treninzi ispred
    /// pozicije bilježe se kao odrađeni, da se ne izgube kad se poredak promijeni.
    private func recordLegacyProgress(of schedule: Schedule) throws {
        let items = schedule.orderedItems
        let passed = try passedItemIds(of: schedule, cycle: schedule.currentCycle)
        let missing = items.prefix(min(schedule.currentPosition, items.count))
            .filter { $0.kind == .workout && !passed.contains($0.id) }
        guard !missing.isEmpty else { return }
        for item in missing {
            context.insert(CycleOverride(
                scheduleId: schedule.id, cycleNumber: schedule.currentCycle, scheduleItemId: item.id, kind: .completedWorkout
            ))
        }
        try context.save()
    }

    /// Pozicija iza zadnjeg odrađenog ili preskočenog treninga prije prvog treninga koji je na redu.
    /// Dani odmora iza odrađenog treninga ostaju ispred nje (podsjetnik ih broji).
    private func updatePosition(of schedule: Schedule, items: [ScheduleItem]) throws {
        let passed = try passedItemIds(of: schedule, cycle: schedule.currentCycle)
        var position = 0
        for (index, item) in items.enumerated() {
            if passed.contains(item.id) {
                position = index + 1
            } else if try isPlayable(item) {
                break
            }
        }
        schedule.currentPosition = position
    }
}

/// Preskočeni trening tekućeg ciklusa, koji se može vratiti (`ScheduleEngine.unskip`).
public struct SkippedWorkout: Identifiable {
    public let change: CycleOverride
    public let templateName: String

    public var id: UUID { change.id }
}
