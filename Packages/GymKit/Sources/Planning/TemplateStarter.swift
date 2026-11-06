import Catalog
import Foundation
import Models
import SwiftData
import Training

/// Pokretanje treninga iz predloška: podaci se kopiraju u `Session`, koji nakon toga ne ovisi o predlošku.
public struct TemplateStarter {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Pokreće sljedeći trening rasporeda, s izmjenama tekućeg ciklusa.
    @discardableResult
    public func start(_ planned: PlannedWorkout, now: Date = Date()) throws -> Session {
        try begin(planned.template, exercises: planned.exercises, scheduleId: planned.schedule.id, now: now)
    }

    /// Treninzi koji se mogu pokrenuti izvan rasporeda, poredani po nazivu: samo treninzi snage s barem jednom vježbom.
    /// Kardio se ne pokreće u aplikaciji nego na satu, a trening bez vježbi je isto što i prazan trening.
    public static func startable(_ templates: [WorkoutTemplate]) -> [WorkoutTemplate] {
        templates
            .filter { $0.kind == .strength && !($0.exercises ?? []).isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Pokreće predložak izvan rasporeda.
    @discardableResult
    public func start(_ template: WorkoutTemplate, now: Date = Date()) throws -> Session {
        let exercises = template.orderedExercises.map {
            PlannedExercise(source: $0.id, ref: $0.exercise, inputType: $0.inputType, isReplacement: false)
        }
        return try begin(template, exercises: exercises, scheduleId: nil, now: now)
    }

    private func begin(
        _ template: WorkoutTemplate, exercises: [PlannedExercise], scheduleId: UUID?, now: Date
    ) throws -> Session {
        let engine = WorkoutEngine(context: context)
        let session = try engine.startSession(
            name: template.name, kind: template.kind, templateId: template.id, scheduleId: scheduleId, now: now
        )
        let sources = Dictionary(uniqueKeysWithValues: template.orderedExercises.map { ($0.id, $0) })
        var groupOrder: [UUID] = []
        var groups: [UUID: [SessionExercise]] = [:]

        for planned in exercises {
            let source = sources[planned.source]
            let created = try engine.addExercise(
                planned.ref, inputType: planned.inputType, to: session, restSeconds: source?.restSeconds, now: now
            )
            // Ciljevi pripadaju originalnoj vježbi: zamijenjena vježba zadržava serije iz svoje povijesti.
            if let source, !planned.isReplacement, !source.orderedSets.isEmpty {
                try applyTargets(source.orderedSets, to: created, engine: engine, now: now)
            }
            if let group = source?.supersetGroupId {
                if groups[group] == nil { groupOrder.append(group) }
                groups[group, default: []].append(created)
            }
        }
        for group in groupOrder {
            if let members = groups[group], members.count >= 2 {
                try engine.makeSuperset(members, in: session, now: now)
            }
        }
        try context.save()
        return session
    }

    /// Serije vježbe postaju točno one iz predloška; prazni ciljevi ostaju kakve ih daju smart defaulti.
    private func applyTargets(
        _ targets: [TemplateSet], to exercise: SessionExercise, engine: WorkoutEngine, now: Date
    ) throws {
        for set in exercise.orderedSets { try engine.removeSet(set, now: now) }
        for target in targets {
            let set = try engine.addSet(to: exercise, kind: target.kind, now: now)
            if let weight = target.targetWeightKg {
                switch exercise.inputType {
                case .weightReps: set.weightKg = weight
                case .weightedBodyweight, .assisted: set.extraWeightKg = weight
                case .bodyweight, .duration, .durationDistance: break
                }
            }
            if let reps = target.targetReps {
                switch exercise.inputType {
                case .weightReps, .bodyweight, .weightedBodyweight, .assisted: set.reps = reps
                case .duration, .durationDistance: break
                }
            }
        }
    }
}
