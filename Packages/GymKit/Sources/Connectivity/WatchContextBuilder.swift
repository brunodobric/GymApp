import Catalog
import Foundation
import Models
import Planning
import SwiftData
import Training
import Units

/// Slaže kontekst za sat iz baze na iPhoneu: sljedeće treninge rasporeda i predloške, s istim
/// serijama i pretpunjenim vrijednostima koje bi dobio trening pokrenut na iPhoneu (`TemplateStarter`).
public struct WatchContextBuilder {
    public let context: ModelContext
    /// Je li vježba kardio, po ključu `ExerciseRef.key` (`ExerciseInfoBuilder.isCardio` u aplikaciji).
    public let isCardio: (String) -> Bool
    /// Je li vježba složena, po ključu `ExerciseRef.key` (`ExerciseCatalog.isCompound` u aplikaciji).
    public let isCompound: (String) -> Bool?
    /// Korak težine vježbe u jedinici prikaza (`UserSettings.weightStep(for:catalog:custom:)` u aplikaciji).
    public let weightStep: (ExerciseRef) -> Double?

    /// Najviše predložaka u kontekstu (WatchConnectivity ima ograničenje veličine).
    public static let maxTemplates = 20

    public init(
        context: ModelContext, isCardio: @escaping (String) -> Bool = { _ in false },
        isCompound: @escaping (String) -> Bool? = { _ in nil },
        weightStep: @escaping (ExerciseRef) -> Double? = { _ in nil }
    ) {
        self.context = context
        self.isCardio = isCardio
        self.isCompound = isCompound
        self.weightStep = weightStep
    }

    public func make(now: Date = Date()) throws -> WatchContextPayload {
        let settings = try GymQueries(context: context).settings()
        let upcoming = try ScheduleEngine(context: context).upcomingWorkouts().map { planned in
            try payload(
                template: planned.template, exercises: planned.exercises,
                scheduleId: planned.schedule.id, scheduleName: planned.schedule.name
            )
        }
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.name)]))
            .filter { !($0.exercises ?? []).isEmpty }
            .prefix(Self.maxTemplates)
            .map { template in
                let exercises = template.orderedExercises.map {
                    PlannedExercise(source: $0.id, ref: $0.exercise, inputType: $0.inputType, isReplacement: false)
                }
                return try payload(template: template, exercises: exercises, scheduleId: nil, scheduleName: nil)
            }
        // Ne zove se `payload`, jer bi zasjenila metodu `payload(template:…)` iznad.
        var watchContext = WatchContextPayload(
            upcoming: upcoming, templates: Array(templates), weightUnit: settings.weightUnit,
            defaultRestSeconds: settings.defaultRestSeconds, savesToHealth: settings.wantsHealthKit, generatedAt: now
        )
        watchContext.accent = settings.accent
        watchContext.compoundRestSeconds = settings.compoundRestSeconds
        return watchContext
    }

    /// Samo sljedeći trening prvog aktivnog rasporeda, s planiranim serijama (za widgete na iPhoneu).
    public func nextWorkout() throws -> PlannedWorkoutPayload? {
        guard let planned = try ScheduleEngine(context: context).upcomingWorkouts().first else { return nil }
        return try payload(
            template: planned.template, exercises: planned.exercises,
            scheduleId: planned.schedule.id, scheduleName: planned.schedule.name
        )
    }

    func payload(
        template: WorkoutTemplate, exercises: [PlannedExercise], scheduleId: UUID?, scheduleName: String?
    ) throws -> PlannedWorkoutPayload {
        let sources = Dictionary(template.orderedExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let unit = (try? GymQueries(context: context).settings().weightUnit) ?? .kilograms
        // Superset postoji samo ako u planu ostanu barem dvije vježbe iz iste grupe (kao u `TemplateStarter`).
        var groupSizes: [UUID: Int] = [:]
        for planned in exercises {
            if let group = sources[planned.source]?.supersetGroupId { groupSizes[group, default: 0] += 1 }
        }
        var groupNumbers: [UUID: Int] = [:]
        let result = try exercises.map { planned -> PlannedExercisePayload in
            let source = sources[planned.source]
            var group: Int?
            if let id = source?.supersetGroupId, (groupSizes[id] ?? 0) >= 2 {
                group = groupNumbers[id] ?? groupNumbers.count
                groupNumbers[id] = group
            }
            let targets = planned.isReplacement ? [] : (source?.orderedSets ?? []).map(\.target)
            let previous = try previousSets(of: planned.ref, templateId: template.id)
            let plan = SetPlanner.plan(
                previous: previous, targets: targets, inputType: planned.inputType,
                weightStep: weightStep(planned.ref), unit: unit
            )
            let sets = plan.sets.map(PlannedSetPayload.init(values:))
            var payload = PlannedExercisePayload(
                exercise: planned.ref, inputType: planned.inputType, restSeconds: source?.restSeconds,
                supersetGroup: group, sets: sets, isCardio: isCardio(planned.ref.key),
                previous: previous.map(PlannedSetPayload.init(values:)), isCompound: isCompound(planned.ref.key),
                weightStep: weightStep(planned.ref)
            )
            payload.targetRepsMin = plan.repRange?.lower
            payload.targetRepsMax = plan.repRange?.upper
            payload.loadChangeKg = plan.loadChangeKg
            let note = planned.isReplacement ? "" : (source?.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            payload.notes = note.isEmpty ? nil : note
            return payload
        }
        return PlannedWorkoutPayload(
            templateId: template.id, scheduleId: scheduleId, name: template.name, scheduleName: scheduleName,
            kind: template.kind, exercises: result
        )
    }

    /// Serije nove vježbe po istim pravilima kao `WorkoutEngine.addExercise` i `TemplateStarter` (`SetPlanner`).
    public static func plannedSets(
        previous: [SetValues], targets: [SetTarget], inputType: ExerciseInputType,
        weightStep: Double? = nil, unit: WeightUnit = .kilograms
    ) -> [PlannedSetPayload] {
        SetPlanner.plan(previous: previous, targets: targets, inputType: inputType, weightStep: weightStep, unit: unit)
            .sets.map(PlannedSetPayload.init(values:))
    }

    /// Završene serije zadnjeg završenog izvođenja vježbe, prvo iz istog predloška (isto kao `WorkoutEngine`).
    private func previousSets(of ref: ExerciseRef, templateId: UUID?) throws -> [SetValues] {
        let key = ref.key
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false }
        )
        let performances = try context.fetch(descriptor)
            .compactMap { exercise -> (Date, UUID?, [SetValues])? in
                guard let owner = exercise.session, owner.state == .finished else { return nil }
                let sets = exercise.orderedSets.filter(\.isCompleted).map(\.values)
                return sets.isEmpty ? nil : (owner.startedAt, owner.templateId, sets)
            }
            .sorted { $0.0 > $1.0 }
        if let templateId, let same = performances.first(where: { $0.1 == templateId }) { return same.2 }
        return performances.first?.2 ?? []
    }
}
