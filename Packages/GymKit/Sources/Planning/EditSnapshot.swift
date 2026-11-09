import Foundation
import Models
import SwiftData

/// Stanje rasporeda prije uređivanja, za "Izađi bez spremanja".
///
/// Uređivač sprema svaku promjenu odmah (premještanje, dodavanje, prekidači), pa se odustajanje ne može
/// riješiti s `rollback`. Snimka pamti polja rasporeda, njegov niz i izmjene ciklusa, a `restore` ih vraća.
public struct ScheduleSnapshot {
    private struct Item {
        let id: UUID
        let orderIndex: Int
        let kindRaw: String
        let workoutTemplateId: UUID?
    }

    private struct Change {
        let id: UUID
        let cycleNumber: Int
        let scheduleItemId: UUID?
        let kindRaw: String
        let targetExerciseKey: String?
        let replacementCatalogId: String?
        let replacementCustomId: UUID?
        let replacementName: String?
        let replacementInputTypeRaw: String?
    }

    private let name: String
    private let details: String
    private let cycleCount: Int?
    private let reminderModeRaw: String
    private let weekdaysRaw: String
    private let reminderMinutes: Int?
    private let reminderGapDays: Int
    private let isActive: Bool
    private let currentCycle: Int
    private let currentPosition: Int
    private let items: [Item]
    private let changes: [Change]

    public init(_ schedule: Schedule, context: ModelContext) throws {
        name = schedule.name
        details = schedule.details
        cycleCount = schedule.cycleCount
        reminderModeRaw = schedule.reminderModeRaw
        weekdaysRaw = schedule.weekdaysRaw
        reminderMinutes = schedule.reminderMinutes
        reminderGapDays = schedule.reminderGapDays
        isActive = schedule.isActive
        currentCycle = schedule.currentCycle
        currentPosition = schedule.currentPosition
        items = schedule.orderedItems.map {
            Item(id: $0.id, orderIndex: $0.orderIndex, kindRaw: $0.kindRaw, workoutTemplateId: $0.workoutTemplateId)
        }
        changes = try Self.overrides(of: schedule, in: context).map {
            Change(
                id: $0.id, cycleNumber: $0.cycleNumber, scheduleItemId: $0.scheduleItemId, kindRaw: $0.kindRaw,
                targetExerciseKey: $0.targetExerciseKey, replacementCatalogId: $0.replacementCatalogId,
                replacementCustomId: $0.replacementCustomId, replacementName: $0.replacementName,
                replacementInputTypeRaw: $0.replacementInputTypeRaw
            )
        }
    }

    /// Vraća raspored na stanje iz snimke i sprema.
    public func restore(_ schedule: Schedule, in context: ModelContext) throws {
        schedule.name = name
        schedule.details = details
        schedule.cycleCount = cycleCount
        schedule.reminderModeRaw = reminderModeRaw
        schedule.weekdaysRaw = weekdaysRaw
        schedule.reminderMinutes = reminderMinutes
        schedule.reminderGapDays = reminderGapDays
        schedule.isActive = isActive
        schedule.currentCycle = currentCycle
        schedule.currentPosition = currentPosition

        // Postojeće stavke se ažuriraju (zadržavaju identitet), dodane se brišu, obrisane stvaraju iznova.
        var existing = Dictionary((schedule.items ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in items {
            let model: ScheduleItem
            if let found = existing.removeValue(forKey: item.id) {
                model = found
            } else {
                model = ScheduleItem(orderIndex: item.orderIndex, kind: .workout)
                model.id = item.id
                context.insert(model)
                model.schedule = schedule
            }
            model.orderIndex = item.orderIndex
            model.kindRaw = item.kindRaw
            model.workoutTemplateId = item.workoutTemplateId
        }
        for extra in existing.values { context.delete(extra) }

        for change in try Self.overrides(of: schedule, in: context) { context.delete(change) }
        for change in changes {
            let model = CycleOverride(
                scheduleId: schedule.id, cycleNumber: change.cycleNumber,
                scheduleItemId: change.scheduleItemId ?? UUID(), kind: .skipWorkout
            )
            model.id = change.id
            model.scheduleItemId = change.scheduleItemId
            model.kindRaw = change.kindRaw
            model.targetExerciseKey = change.targetExerciseKey
            model.replacementCatalogId = change.replacementCatalogId
            model.replacementCustomId = change.replacementCustomId
            model.replacementName = change.replacementName
            model.replacementInputTypeRaw = change.replacementInputTypeRaw
            context.insert(model)
        }
        try context.save()
    }

    private static func overrides(of schedule: Schedule, in context: ModelContext) throws -> [CycleOverride] {
        let id: UUID? = schedule.id
        return try context.fetch(FetchDescriptor<CycleOverride>(predicate: #Predicate { $0.scheduleId == id }))
    }
}

/// Stanje treninga (predloška) prije uređivanja, za "Izađi bez spremanja": naziv, plan i vježbe sa serijama.
public struct TemplateSnapshot {
    private struct SetValue {
        let id: UUID
        let orderIndex: Int
        let kindRaw: String
        let targetWeightKg: Double?
        let targetReps: Int?
        let targetRepsMax: Int?
    }

    private struct ExerciseValue {
        let id: UUID
        let orderIndex: Int
        let catalogId: String?
        let customId: UUID?
        let name: String
        let inputTypeRaw: String
        let supersetGroupId: UUID?
        let restSeconds: Int?
        let notes: String
        let sets: [SetValue]
    }

    private let name: String
    private let details: String
    private let kindRaw: String
    private let exercises: [ExerciseValue]

    public init(_ template: WorkoutTemplate) {
        name = template.name
        details = template.details
        kindRaw = template.kindRaw
        exercises = template.orderedExercises.map { exercise in
            ExerciseValue(
                id: exercise.id, orderIndex: exercise.orderIndex, catalogId: exercise.exerciseCatalogId,
                customId: exercise.exerciseCustomId, name: exercise.exerciseName, inputTypeRaw: exercise.inputTypeRaw,
                supersetGroupId: exercise.supersetGroupId, restSeconds: exercise.restSeconds, notes: exercise.notes,
                sets: exercise.orderedSets.map {
                    SetValue(
                        id: $0.id, orderIndex: $0.orderIndex, kindRaw: $0.kindRaw,
                        targetWeightKg: $0.targetWeightKg, targetReps: $0.targetReps, targetRepsMax: $0.targetRepsMax
                    )
                }
            )
        }
    }

    /// Vraća trening na stanje iz snimke i sprema.
    public func restore(_ template: WorkoutTemplate, in context: ModelContext) throws {
        template.name = name
        template.details = details
        template.kindRaw = kindRaw

        var existing = Dictionary((template.exercises ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in exercises {
            let exercise: TemplateExercise
            if let found = existing.removeValue(forKey: value.id) {
                exercise = found
            } else {
                exercise = TemplateExercise(orderIndex: value.orderIndex, exercise: ExerciseRef(
                    catalogId: value.catalogId, customExerciseId: value.customId, name: value.name
                ))
                exercise.id = value.id
                context.insert(exercise)
                exercise.template = template
            }
            exercise.orderIndex = value.orderIndex
            exercise.exerciseCatalogId = value.catalogId
            exercise.exerciseCustomId = value.customId
            exercise.exerciseName = value.name
            exercise.inputTypeRaw = value.inputTypeRaw
            exercise.supersetGroupId = value.supersetGroupId
            exercise.restSeconds = value.restSeconds
            exercise.notes = value.notes
            restoreSets(value.sets, of: exercise, in: context)
        }
        for extra in existing.values { context.delete(extra) }
        try context.save()
    }

    private func restoreSets(_ sets: [SetValue], of exercise: TemplateExercise, in context: ModelContext) {
        var existing = Dictionary((exercise.sets ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in sets {
            let model: TemplateSet
            if let found = existing.removeValue(forKey: value.id) {
                model = found
            } else {
                model = TemplateSet(orderIndex: value.orderIndex)
                model.id = value.id
                context.insert(model)
                model.exercise = exercise
            }
            model.orderIndex = value.orderIndex
            model.kindRaw = value.kindRaw
            model.targetWeightKg = value.targetWeightKg
            model.targetReps = value.targetReps
            model.targetRepsMax = value.targetRepsMax
        }
        for extra in existing.values { context.delete(extra) }
    }
}
