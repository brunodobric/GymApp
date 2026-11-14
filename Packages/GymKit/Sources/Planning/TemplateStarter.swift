import Catalog
import Foundation
import Models
import SwiftData
import Training
import Units

/// Pokretanje treninga iz predloška: podaci se kopiraju u `Session`, koji nakon toga ne ovisi o predlošku.
public struct TemplateStarter {
    public let context: ModelContext
    /// Korak težine vježbe u jedinici korisnika, za prijedlog veće težine (`SetPlanner`).
    /// Nil: korak iz postavki bez opreme vježbe (aplikacija predaje korak s opremom iz kataloga).
    public let weightStep: ((ExerciseRef) -> Double)?

    public init(context: ModelContext, weightStep: ((ExerciseRef) -> Double)? = nil) {
        self.context = context
        self.weightStep = weightStep
    }

    /// Pokreće sljedeći trening rasporeda, s izmjenama tekućeg ciklusa.
    @discardableResult
    public func start(_ planned: PlannedWorkout, now: Date = Date()) throws -> Session {
        try begin(planned.template, exercises: planned.exercises, scheduleId: planned.schedule.id, now: now)
    }

    /// Treninzi koji se mogu pokrenuti izvan rasporeda, poredani po nazivu: samo treninzi snage s barem jednom vježbom.
    /// Trening bez vježbi je isto što i prazan trening.
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
        let settings = try? GymQueries(context: context).settings()
        let unit = settings?.weightUnit ?? .kilograms
        let step = weightStep ?? WeightStepSettings.resolver(settings: settings, catalog: nil, custom: [])
        let session = try engine.startSession(
            name: template.name, kind: template.kind, templateId: template.id, scheduleId: scheduleId, now: now
        )
        let sources = Dictionary(uniqueKeysWithValues: template.orderedExercises.map { ($0.id, $0) })
        var groupOrder: [UUID] = []
        var groups: [UUID: [SessionExercise]] = [:]

        for planned in exercises {
            let source = sources[planned.source]
            // Ciljevi pripadaju originalnoj vježbi: zamijenjena vježba zadržava serije iz svoje povijesti.
            let targets = planned.isReplacement ? [] : (source?.orderedSets ?? []).map(\.target)
            let created = try engine.addExercise(
                planned.ref, inputType: planned.inputType, to: session, restSeconds: source?.restSeconds,
                targets: targets, weightStep: step(planned.ref), unit: unit, now: now
            )
            if let source, !planned.isReplacement {
                created.notes = source.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let group = source?.supersetGroupId {
                if groupOrder.contains(group) == false { groupOrder.append(group) }
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
}
