import Catalog
import Foundation
import Models
import SwiftData

extension TemplateEngine {
    /// Novi trening (predložak) iz odrađenog treninga: isti naziv, iste vježbe redom, pauze i supersetovi,
    /// a ciljevi serija su vrijednosti završenih serija. Odrađeni trening ostaje netaknut.
    @discardableResult
    public func createTemplate(from session: Session) throws -> WorkoutTemplate {
        let template = WorkoutTemplate(name: session.name, kind: .strength)
        context.insert(template)
        var groups: [UUID: UUID] = [:]
        let exercises = session.orderedExercises.filter { !$0.isRemoved }
        for (order, exercise) in exercises.enumerated() {
            let copy = TemplateExercise(orderIndex: order, exercise: exercise.exercise, inputType: exercise.inputType)
            copy.restSeconds = exercise.restSeconds
            if let group = exercise.supersetGroupId {
                if groups[group] == nil { groups[group] = UUID() }
                copy.supersetGroupId = groups[group]
            }
            context.insert(copy)
            copy.template = template
            let completed = exercise.orderedSets.filter(\.isCompleted)
            let sets = completed.isEmpty ? exercise.orderedSets : completed
            for (index, set) in sets.enumerated() {
                let target = TemplateSet(
                    orderIndex: index, kind: set.kind,
                    targetWeightKg: Self.targetWeight(of: set, inputType: exercise.inputType),
                    targetReps: Self.targetReps(of: set, inputType: exercise.inputType)
                )
                context.insert(target)
                target.exercise = copy
            }
            if sets.isEmpty {
                for index in 0..<Self.defaultSetCount {
                    let target = TemplateSet(orderIndex: index)
                    context.insert(target)
                    target.exercise = copy
                }
            }
        }
        // Superset s jednom vježbom (druga je bila izbačena) nema smisla.
        let members = Dictionary(grouping: template.orderedExercises.filter { $0.supersetGroupId != nil }) {
            $0.supersetGroupId
        }
        for (_, list) in members where list.count == 1 { list[0].supersetGroupId = nil }
        try context.save()
        return template
    }

    /// Ciljana težina predloška: težina, a kod vlastite težine dodatna težina ili pomoć (kao u `TemplateStarter`).
    private static func targetWeight(of set: SetLog, inputType: ExerciseInputType) -> Double? {
        switch inputType {
        case .weightReps: set.weightKg
        case .weightedBodyweight, .assisted: set.extraWeightKg
        case .bodyweight, .duration, .durationDistance: nil
        }
    }

    private static func targetReps(of set: SetLog, inputType: ExerciseInputType) -> Int? {
        switch inputType {
        case .weightReps, .bodyweight, .weightedBodyweight, .assisted: set.reps
        case .duration, .durationDistance: nil
        }
    }
}
