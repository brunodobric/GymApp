import Catalog
import Foundation
import Models

// Snimka treninga koja putuje između iPhonea i Watcha (specifikacija, odjeljak 6).
// Uređaj koji vodi trening šalje cijelu snimku nakon svake promjene, a drugi je primjenjuje
// ako je novija od onoga što već ima (zadnja promjena pobjeđuje). Sve vrijednosti su obične
// strukture bez veze s bazom, pa se sat može služiti njima bez SwiftData.

public struct SetSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var orderIndex: Int
    public var kind: SetKind
    /// Težina uvijek u kilogramima.
    public var weightKg: Double?
    public var reps: Int?
    public var extraWeightKg: Double?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rpe: Double?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        orderIndex: Int,
        kind: SetKind = .working,
        weightKg: Double? = nil,
        reps: Int? = nil,
        extraWeightKg: Double? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rpe: Double? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.extraWeightKg = extraWeightKg
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rpe = rpe
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }
}

public struct ExerciseSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var orderIndex: Int
    public var exercise: ExerciseRef
    public var inputType: ExerciseInputType
    public var supersetGroupId: UUID?
    public var restSeconds: Int?
    public var isRemoved: Bool
    public var sets: [SetSnapshot]

    public init(
        id: UUID = UUID(),
        orderIndex: Int,
        exercise: ExerciseRef,
        inputType: ExerciseInputType,
        supersetGroupId: UUID? = nil,
        restSeconds: Int? = nil,
        isRemoved: Bool = false,
        sets: [SetSnapshot] = []
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exercise = exercise
        self.inputType = inputType
        self.supersetGroupId = supersetGroupId
        self.restSeconds = restSeconds
        self.isRemoved = isRemoved
        self.sets = sets
    }

    public var orderedSets: [SetSnapshot] { sets.sorted { $0.orderIndex < $1.orderIndex } }

    public var isFullyCompleted: Bool { sets.allSatisfy(\.isCompleted) }

    /// Ista vježba bez serija: za usporedbu promjena na razini vježbe.
    var withoutSets: ExerciseSnapshot {
        var copy = self
        copy.sets = []
        return copy
    }
}

public struct SessionSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: WorkoutKind
    public var templateId: UUID?
    public var scheduleId: UUID?
    public var startedAt: Date
    public var endedAt: Date?
    public var state: SessionState
    public var controllingDevice: DeviceRole
    public var notes: String
    public var restTimerStartedAt: Date?
    public var restTimerEndsAt: Date?
    /// Samo iz HealthKita (sat je mjerio).
    public var activeEnergyKilocalories: Double?
    public var averageHeartRate: Double?
    public var healthKitWorkoutId: UUID?
    public var distanceMeters: Double?
    /// Trenutak zadnje promjene (`Session.lastActivityAt`). Starija snimka nikad ne prepisuje noviju.
    public var updatedAt: Date
    public var exercises: [ExerciseSnapshot]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: WorkoutKind = .strength,
        templateId: UUID? = nil,
        scheduleId: UUID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        state: SessionState = .active,
        controllingDevice: DeviceRole,
        notes: String = "",
        restTimerStartedAt: Date? = nil,
        restTimerEndsAt: Date? = nil,
        activeEnergyKilocalories: Double? = nil,
        averageHeartRate: Double? = nil,
        healthKitWorkoutId: UUID? = nil,
        distanceMeters: Double? = nil,
        updatedAt: Date,
        exercises: [ExerciseSnapshot] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.templateId = templateId
        self.scheduleId = scheduleId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
        self.controllingDevice = controllingDevice
        self.notes = notes
        self.restTimerStartedAt = restTimerStartedAt
        self.restTimerEndsAt = restTimerEndsAt
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.averageHeartRate = averageHeartRate
        self.healthKitWorkoutId = healthKitWorkoutId
        self.distanceMeters = distanceMeters
        self.updatedAt = updatedAt
        self.exercises = exercises
    }

    public var orderedExercises: [ExerciseSnapshot] { exercises.sorted { $0.orderIndex < $1.orderIndex } }

    /// Vježbe koje se prikazuju (bez izbačenih), po redoslijedu.
    public var visibleExercises: [ExerciseSnapshot] { orderedExercises.filter { !$0.isRemoved } }

    public var completedSetCount: Int {
        visibleExercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }

    public func exercise(withID id: UUID) -> ExerciseSnapshot? {
        exercises.first { $0.id == id }
    }

    /// Vježba kojoj serija pripada.
    public func exercise(containingSet setID: UUID) -> ExerciseSnapshot? {
        exercises.first { $0.sets.contains { $0.id == setID } }
    }

    public func set(withID id: UUID) -> SetSnapshot? {
        for exercise in exercises {
            if let set = exercise.sets.first(where: { $0.id == id }) { return set }
        }
        return nil
    }

    /// Je li ova snimka novija od zadane (zadnja promjena pobjeđuje). Jednako vrijeme se prihvaća,
    /// jer isti uređaj može poslati dvije promjene u istoj milisekundi.
    public func isNewer(than date: Date) -> Bool {
        updatedAt >= date
    }
}
