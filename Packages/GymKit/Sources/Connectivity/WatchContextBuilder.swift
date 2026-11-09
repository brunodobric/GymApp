import Catalog
import Foundation
import Models
import Planning
import SwiftData
import Training

/// Slaže kontekst za sat iz baze na iPhoneu: sljedeće treninge rasporeda i predloške, s istim
/// serijama i pretpunjenim vrijednostima koje bi dobio trening pokrenut na iPhoneu (`TemplateStarter`).
public struct WatchContextBuilder {
    public let context: ModelContext
    /// Je li vježba kardio, po ključu `ExerciseRef.key` (`ExerciseInfoBuilder.isCardio` u aplikaciji).
    public let isCardio: (String) -> Bool

    /// Najviše predložaka u kontekstu (WatchConnectivity ima ograničenje veličine).
    public static let maxTemplates = 20

    public init(context: ModelContext, isCardio: @escaping (String) -> Bool = { _ in false }) {
        self.context = context
        self.isCardio = isCardio
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
        var payload = WatchContextPayload(
            upcoming: upcoming, templates: Array(templates), weightUnit: settings.weightUnit,
            defaultRestSeconds: settings.defaultRestSeconds, savesToHealth: settings.wantsHealthKit, generatedAt: now
        )
        payload.accent = settings.accent
        return payload
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
            let targets = planned.isReplacement ? [] : (source?.orderedSets ?? []).map {
                SetTarget(kind: $0.kind, weightKg: $0.targetWeightKg, reps: $0.targetReps)
            }
            let previous = try previousSets(of: planned.ref)
            let sets = Self.plannedSets(previous: previous, targets: targets, inputType: planned.inputType)
            return PlannedExercisePayload(
                exercise: planned.ref, inputType: planned.inputType, restSeconds: source?.restSeconds,
                supersetGroup: group, sets: sets, isCardio: isCardio(planned.ref.key),
                previous: previous.map(PlannedSetPayload.init(values:))
            )
        }
        return PlannedWorkoutPayload(
            templateId: template.id, scheduleId: scheduleId, name: template.name, scheduleName: scheduleName,
            kind: template.kind, exercises: result
        )
    }

    public struct SetTarget: Equatable, Sendable {
        public var kind: SetKind
        public var weightKg: Double?
        public var reps: Int?

        public init(kind: SetKind, weightKg: Double? = nil, reps: Int? = nil) {
            self.kind = kind
            self.weightKg = weightKg
            self.reps = reps
        }
    }

    /// Serije nove vježbe po istim pravilima kao `WorkoutEngine.addExercise` i `TemplateStarter`:
    /// bez ciljeva onoliko warm-up i radnih serija koliko je bilo prošli put (inače tri radne),
    /// vrijednosti iz zadnjeg izvođenja, a ciljevi predloška nadjačavaju težinu i ponavljanja.
    public static func plannedSets(previous: [SetValues], targets: [SetTarget], inputType: ExerciseInputType) -> [PlannedSetPayload] {
        let kinds: [SetKind]
        if targets.isEmpty {
            let warmUps = previous.filter { $0.kind == .warmUp }.count
            let working = previous.filter { $0.kind == .working }.count
            kinds = Array(repeating: .warmUp, count: warmUps)
                + Array(repeating: .working, count: working > 0 ? working : WorkoutEngine.defaultWorkingSets)
        } else {
            kinds = targets.map(\.kind)
        }

        var result: [SetValues] = []
        for (index, kind) in kinds.enumerated() {
            let position = result.filter { $0.kind == kind }.count
            var values = SmartDefaults.defaults(forPosition: position, kind: kind, previous: previous)
                ?? result.last(where: { $0.kind == kind }).flatMap { SmartDefaults.defaults(forPosition: 0, kind: kind, previous: [$0]) }
                ?? SetValues(kind: kind)
            if index < targets.count {
                apply(targets[index], to: &values, inputType: inputType)
            }
            result.append(values)
        }
        return result.map(PlannedSetPayload.init(values:))
    }

    private static func apply(_ target: SetTarget, to values: inout SetValues, inputType: ExerciseInputType) {
        if let weight = target.weightKg {
            switch inputType {
            case .weightReps: values.weightKg = weight
            case .weightedBodyweight, .assisted: values.extraWeightKg = weight
            case .bodyweight, .duration, .durationDistance: break
            }
        }
        if let reps = target.reps {
            switch inputType {
            case .weightReps, .bodyweight, .weightedBodyweight, .assisted: values.reps = reps
            case .duration, .durationDistance: break
            }
        }
    }

    /// Završene serije zadnjeg završenog izvođenja vježbe (isto kao `WorkoutEngine`).
    private func previousSets(of ref: ExerciseRef) throws -> [SetValues] {
        let key = ref.key
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false }
        )
        return try context.fetch(descriptor)
            .compactMap { exercise -> (Date, [SetValues])? in
                guard let owner = exercise.session, owner.state == .finished else { return nil }
                let sets = exercise.orderedSets.filter(\.isCompleted).map(\.values)
                return sets.isEmpty ? nil : (owner.startedAt, sets)
            }
            .max { $0.0 < $1.0 }?.1 ?? []
    }
}
