import Catalog
import Foundation
import Models
import SwiftData

public enum PlanningError: Error, Equatable {
    case needsTwoExercises
}

/// Uređivanje predložaka treninga: vježbe, ciljane serije, supersetovi, pauze i redoslijed.
/// Svaka promjena odmah se sprema.
public struct TemplateEngine {
    public let context: ModelContext

    /// Broj radnih serija nove vježbe u predlošku.
    public static let defaultSetCount = 3

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Predlošci

    @discardableResult
    public func createTemplate(name: String, kind: WorkoutKind = .strength) throws -> WorkoutTemplate {
        let template = WorkoutTemplate(name: name, kind: kind)
        context.insert(template)
        try context.save()
        return template
    }

    /// Kopija predloška s novim id-evima (i novim grupama supersetova).
    @discardableResult
    public func duplicate(_ template: WorkoutTemplate, name: String) throws -> WorkoutTemplate {
        let copy = WorkoutTemplate(name: name, kind: template.kind)
        copy.details = template.details
        context.insert(copy)
        var groups: [UUID: UUID] = [:]
        for exercise in template.orderedExercises {
            let newExercise = TemplateExercise(
                orderIndex: exercise.orderIndex, exercise: exercise.exercise, inputType: exercise.inputType
            )
            newExercise.restSeconds = exercise.restSeconds
            newExercise.notes = exercise.notes
            if let group = exercise.supersetGroupId {
                if groups[group] == nil { groups[group] = UUID() }
                newExercise.supersetGroupId = groups[group]
            }
            context.insert(newExercise)
            newExercise.template = copy
            for set in exercise.orderedSets {
                let newSet = TemplateSet(
                    orderIndex: set.orderIndex, kind: set.kind,
                    targetWeightKg: set.targetWeightKg, targetReps: set.targetReps
                )
                context.insert(newSet)
                newSet.exercise = newExercise
            }
        }
        try context.save()
        return copy
    }

    /// Brisanje predloška ne dira odrađene treninge (oni su neovisna kopija) ni stavke rasporeda.
    public func delete(_ template: WorkoutTemplate) throws {
        context.delete(template)
        try context.save()
    }

    // MARK: Vježbe

    @discardableResult
    public func addExercise(
        _ ref: ExerciseRef, inputType: ExerciseInputType, to template: WorkoutTemplate,
        setCount: Int = TemplateEngine.defaultSetCount
    ) throws -> TemplateExercise {
        let order = ((template.exercises ?? []).map(\.orderIndex).max() ?? -1) + 1
        let exercise = TemplateExercise(orderIndex: order, exercise: ref, inputType: inputType)
        context.insert(exercise)
        exercise.template = template
        for index in 0..<max(setCount, 0) {
            let set = TemplateSet(orderIndex: index)
            context.insert(set)
            set.exercise = exercise
        }
        try context.save()
        return exercise
    }

    public func removeExercise(_ exercise: TemplateExercise) throws {
        let template = exercise.template
        let group = exercise.supersetGroupId
        context.delete(exercise)
        if let template {
            let rest = template.orderedExercises.filter { $0.id != exercise.id }
            for (index, item) in rest.enumerated() { item.orderIndex = index }
            // Superset s jednom vježbom nema smisla.
            let members = rest.filter { group != nil && $0.supersetGroupId == group }
            if members.count == 1 { members[0].supersetGroupId = nil }
        }
        try context.save()
    }

    /// Premješta vježbe kao SwiftUI `move(fromOffsets:toOffset:)`, koji ovdje nije dostupan.
    public func moveExercises(in template: WorkoutTemplate, from source: IndexSet, to destination: Int) throws {
        var ordered = template.orderedExercises
        let moving = source.sorted().map { ordered[$0] }
        let target = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { ordered.remove(at: index) }
        ordered.insert(contentsOf: moving, at: min(max(target, 0), ordered.count))
        for (index, exercise) in ordered.enumerated() { exercise.orderIndex = index }
        try context.save()
    }

    public func setRest(_ seconds: Int?, for exercise: TemplateExercise) throws {
        exercise.restSeconds = seconds
        try context.save()
    }

    // MARK: Supersetovi

    /// Spaja vježbe u superset i postavlja ih jednu do druge, na mjesto prve među njima.
    public func makeSuperset(_ exercises: [TemplateExercise], in template: WorkoutTemplate) throws {
        guard exercises.count >= 2 else { throw PlanningError.needsTwoExercises }
        let group = UUID()
        let selected = Set(exercises.map(\.id))
        let ordered = template.orderedExercises
        guard let anchor = ordered.firstIndex(where: { selected.contains($0.id) }) else { return }
        let members = ordered.filter { selected.contains($0.id) }
        let others = ordered.filter { !selected.contains($0.id) }
        let insertAt = min(anchor, others.count)
        let result = Array(others[..<insertAt]) + members + Array(others[insertAt...])
        for member in members { member.supersetGroupId = group }
        for (index, exercise) in result.enumerated() { exercise.orderIndex = index }
        try context.save()
    }

    public func removeFromSuperset(_ exercise: TemplateExercise) throws {
        let group = exercise.supersetGroupId
        exercise.supersetGroupId = nil
        if let template = exercise.template, let group {
            let rest = template.orderedExercises.filter { $0.supersetGroupId == group }
            if rest.count == 1 { rest[0].supersetGroupId = nil }
        }
        try context.save()
    }

    // MARK: Serije

    /// Nova serija preuzima ciljeve zadnje serije iste vrste.
    @discardableResult
    public func addSet(to exercise: TemplateExercise, kind: SetKind = .working) throws -> TemplateSet {
        let existing = exercise.orderedSets
        let set = TemplateSet(orderIndex: existing.count, kind: kind)
        if let last = existing.last(where: { $0.kind == kind }) {
            set.targetWeightKg = last.targetWeightKg
            set.targetReps = last.targetReps
        }
        context.insert(set)
        set.exercise = exercise
        try context.save()
        return set
    }

    public func removeSet(_ set: TemplateSet) throws {
        let exercise = set.exercise
        context.delete(set)
        if let exercise {
            for (index, remaining) in exercise.orderedSets.filter({ $0.id != set.id }).enumerated() {
                remaining.orderIndex = index
            }
        }
        try context.save()
    }

    public func setTargets(_ set: TemplateSet, weightKg: Double?, reps: Int?) throws {
        set.targetWeightKg = weightKg
        set.targetReps = reps
        try context.save()
    }
}
