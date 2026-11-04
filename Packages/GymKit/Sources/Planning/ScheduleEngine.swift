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
/// `currentPosition` je indeks sljedeće stavke koja se razmatra; rest dani i preskočeni treninzi se prelaze.
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
    /// Bez `index` idu na kraj niza. Pozicija rasporeda prati stavku na kojoj je stao, kao kod premještanja.
    @discardableResult
    public func insertWorkouts(_ templates: [WorkoutTemplate], into schedule: Schedule, at index: Int? = nil) throws -> [ScheduleItem] {
        var ordered = schedule.orderedItems
        let currentId = currentItem(of: schedule)?.id
        let position = min(max(index ?? ordered.count, 0), ordered.count)
        let added = templates.map { template in
            let item = ScheduleItem(orderIndex: 0, kind: .workout, workoutTemplateId: template.id)
            context.insert(item)
            item.schedule = schedule
            return item
        }
        ordered.insert(contentsOf: added, at: position)
        for (order, item) in ordered.enumerated() { item.orderIndex = order }
        if let currentId, let current = ordered.firstIndex(where: { $0.id == currentId }) {
            schedule.currentPosition = current
        }
        try context.save()
        return added
    }

    @discardableResult
    public func addRestDay(to schedule: Schedule) throws -> ScheduleItem {
        try append(kind: .restDay, templateId: nil, to: schedule)
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

    public func moveItems(in schedule: Schedule, from source: IndexSet, to destination: Int) throws {
        var ordered = schedule.orderedItems
        let currentId = currentItem(of: schedule)?.id
        let moving = source.sorted().map { ordered[$0] }
        let target = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { ordered.remove(at: index) }
        ordered.insert(contentsOf: moving, at: min(max(target, 0), ordered.count))
        for (index, item) in ordered.enumerated() { item.orderIndex = index }
        // Pozicija prati stavku na kojoj je raspored stao.
        if let currentId, let index = ordered.firstIndex(where: { $0.id == currentId }) {
            schedule.currentPosition = index
        }
        try context.save()
    }

    /// Pokreće raspored ispočetka (prvi ciklus, prva stavka).
    public func restart(_ schedule: Schedule) throws {
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
        let skipped = try skippedItemIds(of: schedule, cycle: schedule.currentCycle)
        for index in schedule.currentPosition..<items.count {
            let item = items[index]
            if item.kind == .workout, !skipped.contains(item.id), try isPlayable(item) { return index }
        }
        return nil
    }

    /// Što "Započni" nudi: sljedeći neodrađeni trening aktivnog rasporeda. Stavke čiji je predložak
    /// obrisan se prelaze.
    public func nextWorkout(of schedule: Schedule) throws -> PlannedWorkout? {
        guard schedule.isActive else { return nil }
        let items = schedule.orderedItems
        let skipped = try skippedItemIds(of: schedule, cycle: schedule.currentCycle)
        let changes = try overrides(of: schedule, cycle: schedule.currentCycle)
        var index = schedule.currentPosition
        while index < items.count {
            let item = items[index]
            if item.kind == .workout, !skipped.contains(item.id),
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

    /// Sljedeći trening svakog aktivnog rasporeda.
    public func upcomingWorkouts() throws -> [PlannedWorkout] {
        let schedules = try context.fetch(FetchDescriptor<Schedule>(sortBy: [SortDescriptor(\.createdAt)]))
        return try schedules.compactMap { try nextWorkout(of: $0) }
    }

    // MARK: Napredovanje

    /// Poziva se kad je trening završen. Napreduje samo ako je to bio sljedeći trening rasporeda.
    /// Vraća true kad je raspored napredovao.
    @discardableResult
    public func sessionFinished(_ session: Session) throws -> Bool {
        guard let scheduleId = session.scheduleId, let templateId = session.templateId,
              let schedule = try fetchSchedule(withID: scheduleId), schedule.isActive,
              let index = try nextWorkoutIndex(in: schedule) else { return false }
        let item = schedule.orderedItems[index]
        guard item.workoutTemplateId == templateId else { return false }
        schedule.currentPosition = index + 1
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

    /// Vraća preskočeni trening. Moguće samo dok je ciklus još tekući.
    public func unskip(_ change: CycleOverride, in schedule: Schedule) throws {
        guard change.kind == .skipWorkout, change.cycleNumber == schedule.currentCycle else { return }
        context.delete(change)
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
        let id = schedule.id
        return try context.fetch(FetchDescriptor<CycleOverride>())
            .filter { $0.scheduleId == id && $0.cycleNumber == cycle }
    }

    // MARK: Pomoćno

    private func skippedItemIds(of schedule: Schedule, cycle: Int) throws -> Set<UUID> {
        Set(try overrides(of: schedule, cycle: cycle).filter { $0.kind == .skipWorkout }.compactMap(\.scheduleItemId))
    }

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
