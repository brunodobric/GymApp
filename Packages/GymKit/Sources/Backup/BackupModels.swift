import Catalog
import Foundation
import Models
import SwiftData

/// Greške pri uvozu.
public enum BackupError: Error, Equatable {
    /// Datoteka nije sigurnosna kopija ove aplikacije.
    case unsupportedFormat
    /// Datoteka je iz novije verzije aplikacije.
    case newerVersion(Int)
    /// CSV nema očekivana zaglavlja ili je redak neispravan.
    case invalidCSV(line: Int)
}

/// Što je uvoz napravio. Zapisi s `id` koji već postoji se preskaču, pa je uvoz siguran i na već popunjenoj bazi.
public struct BackupImportResult: Equatable, Sendable {
    public var added = 0
    public var skipped = 0

    public init(added: Int = 0, skipped: Int = 0) {
        self.added = added
        self.skipped = skipped
    }
}

// MARK: - JSON zapis (puna sigurnosna kopija)

struct BackupFile: Codable {
    var format: String
    var version: Int
    var exportedAt: Date
    var settings: SettingsDTO?
    var customExercises: [CustomExerciseDTO]
    var templates: [TemplateDTO]
    var schedules: [ScheduleDTO]
    var cycleOverrides: [CycleOverrideDTO]
    var sessions: [SessionDTO]
    var measurements: [MeasurementDTO]
    var dashboardCards: [DashboardCardDTO]
}

struct SettingsDTO: Codable {
    var id: UUID
    var weightUnitRaw: String
    var defaultRestSeconds: Int
    var themeRaw: String
    var accentColorRaw: String
    var effortScaleRaw: String
    var prEnabled: Bool
    var trackedPRKindsRaw: String
    var restEndSoundEnabled: Bool
    var availablePlatesRaw: String
    var barbellWeightKg: Double
    var goalRaw: String
    var experienceRaw: String
    var equipmentRaw: String
    var trainingDaysPerWeek: Int?
    var onboardingCompleted: Bool
    var wantsHealthKit: Bool
    var notificationsEnabled: Bool

    init(_ s: UserSettings) {
        id = s.id
        weightUnitRaw = s.weightUnitRaw
        defaultRestSeconds = s.defaultRestSeconds
        themeRaw = s.themeRaw
        accentColorRaw = s.accentColorRaw
        effortScaleRaw = s.effortScaleRaw
        prEnabled = s.prEnabled
        trackedPRKindsRaw = s.trackedPRKindsRaw
        restEndSoundEnabled = s.restEndSoundEnabled
        availablePlatesRaw = s.availablePlatesRaw
        barbellWeightKg = s.barbellWeightKg
        goalRaw = s.goalRaw
        experienceRaw = s.experienceRaw
        equipmentRaw = s.equipmentRaw
        trainingDaysPerWeek = s.trainingDaysPerWeek
        onboardingCompleted = s.onboardingCompleted
        wantsHealthKit = s.wantsHealthKit
        notificationsEnabled = s.notificationsEnabled
    }

    func apply(to s: UserSettings) {
        s.id = id
        s.weightUnitRaw = weightUnitRaw
        s.defaultRestSeconds = defaultRestSeconds
        s.themeRaw = themeRaw
        s.accentColorRaw = accentColorRaw
        s.effortScaleRaw = effortScaleRaw
        s.prEnabled = prEnabled
        s.trackedPRKindsRaw = trackedPRKindsRaw
        s.restEndSoundEnabled = restEndSoundEnabled
        s.availablePlatesRaw = availablePlatesRaw
        s.barbellWeightKg = barbellWeightKg
        s.goalRaw = goalRaw
        s.experienceRaw = experienceRaw
        s.equipmentRaw = equipmentRaw
        s.trainingDaysPerWeek = trainingDaysPerWeek
        s.onboardingCompleted = onboardingCompleted
        s.wantsHealthKit = wantsHealthKit
        s.notificationsEnabled = notificationsEnabled
    }
}

struct CustomExerciseDTO: Codable {
    var id: UUID
    var name: String
    var details: String
    var categoryRaw: String
    var musclesRaw: String
    var equipmentRaw: String
    var inputTypeRaw: String
    var imageData: Data?
    var isArchived: Bool
    var createdAt: Date

    init(_ e: CustomExercise) {
        id = e.id
        name = e.name
        details = e.details
        categoryRaw = e.categoryRaw
        musclesRaw = e.musclesRaw
        equipmentRaw = e.equipmentRaw
        inputTypeRaw = e.inputTypeRaw
        imageData = e.imageData
        isArchived = e.isArchived
        createdAt = e.createdAt
    }

    func make() -> CustomExercise {
        let e = CustomExercise(name: name)
        e.id = id
        e.details = details
        e.categoryRaw = categoryRaw
        e.musclesRaw = musclesRaw
        e.equipmentRaw = equipmentRaw
        e.inputTypeRaw = inputTypeRaw
        e.imageData = imageData
        e.isArchived = isArchived
        e.createdAt = createdAt
        return e
    }
}

struct TemplateSetDTO: Codable {
    var id: UUID
    var orderIndex: Int
    var kindRaw: String
    var targetWeightKg: Double?
    var targetReps: Int?
}

struct TemplateExerciseDTO: Codable {
    var id: UUID
    var orderIndex: Int
    var catalogId: String?
    var customId: UUID?
    var name: String
    var inputTypeRaw: String
    var supersetGroupId: UUID?
    var restSeconds: Int?
    var notes: String
    var sets: [TemplateSetDTO]
}

struct TemplateDTO: Codable {
    var id: UUID
    var name: String
    var details: String
    var kindRaw: String
    var createdAt: Date
    var exercises: [TemplateExerciseDTO]

    init(_ t: WorkoutTemplate) {
        id = t.id
        name = t.name
        details = t.details
        kindRaw = t.kindRaw
        createdAt = t.createdAt
        exercises = t.orderedExercises.map { e in
            TemplateExerciseDTO(
                id: e.id, orderIndex: e.orderIndex, catalogId: e.exerciseCatalogId, customId: e.exerciseCustomId,
                name: e.exerciseName, inputTypeRaw: e.inputTypeRaw, supersetGroupId: e.supersetGroupId,
                restSeconds: e.restSeconds, notes: e.notes,
                sets: e.orderedSets.map {
                    TemplateSetDTO(
                        id: $0.id, orderIndex: $0.orderIndex, kindRaw: $0.kindRaw,
                        targetWeightKg: $0.targetWeightKg, targetReps: $0.targetReps
                    )
                }
            )
        }
    }

    func make(in context: ModelContext) -> WorkoutTemplate {
        let t = WorkoutTemplate(name: name)
        t.id = id
        t.details = details
        t.kindRaw = kindRaw
        t.createdAt = createdAt
        context.insert(t)
        for item in exercises {
            let e = TemplateExercise(orderIndex: item.orderIndex, exercise: ExerciseRef(
                catalogId: item.catalogId, customExerciseId: item.customId, name: item.name
            ))
            e.id = item.id
            e.inputTypeRaw = item.inputTypeRaw
            e.supersetGroupId = item.supersetGroupId
            e.restSeconds = item.restSeconds
            e.notes = item.notes
            context.insert(e)
            e.template = t
            for setItem in item.sets {
                let s = TemplateSet(orderIndex: setItem.orderIndex)
                s.id = setItem.id
                s.kindRaw = setItem.kindRaw
                s.targetWeightKg = setItem.targetWeightKg
                s.targetReps = setItem.targetReps
                context.insert(s)
                s.exercise = e
            }
        }
        return t
    }
}

struct ScheduleItemDTO: Codable {
    var id: UUID
    var orderIndex: Int
    var kindRaw: String
    var workoutTemplateId: UUID?
}

struct ScheduleDTO: Codable {
    var id: UUID
    var name: String
    var details: String
    var cycleCount: Int?
    var reminderModeRaw: String
    var weekdaysRaw: String
    var reminderMinutes: Int?
    var reminderGapDays: Int
    var isActive: Bool
    var currentCycle: Int
    var currentPosition: Int
    var createdAt: Date
    var items: [ScheduleItemDTO]

    init(_ s: Schedule) {
        id = s.id
        name = s.name
        details = s.details
        cycleCount = s.cycleCount
        reminderModeRaw = s.reminderModeRaw
        weekdaysRaw = s.weekdaysRaw
        reminderMinutes = s.reminderMinutes
        reminderGapDays = s.reminderGapDays
        isActive = s.isActive
        currentCycle = s.currentCycle
        currentPosition = s.currentPosition
        createdAt = s.createdAt
        items = s.orderedItems.map {
            ScheduleItemDTO(id: $0.id, orderIndex: $0.orderIndex, kindRaw: $0.kindRaw, workoutTemplateId: $0.workoutTemplateId)
        }
    }

    func make(in context: ModelContext) -> Schedule {
        let s = Schedule(name: name)
        s.id = id
        s.details = details
        s.cycleCount = cycleCount
        s.reminderModeRaw = reminderModeRaw
        s.weekdaysRaw = weekdaysRaw
        s.reminderMinutes = reminderMinutes
        s.reminderGapDays = reminderGapDays
        s.isActive = isActive
        s.currentCycle = currentCycle
        s.currentPosition = currentPosition
        s.createdAt = createdAt
        context.insert(s)
        for item in items {
            let i = ScheduleItem(orderIndex: item.orderIndex, kind: .workout, workoutTemplateId: item.workoutTemplateId)
            i.id = item.id
            i.kindRaw = item.kindRaw
            context.insert(i)
            i.schedule = s
        }
        return s
    }
}

struct CycleOverrideDTO: Codable {
    var id: UUID
    var scheduleId: UUID?
    var cycleNumber: Int
    var scheduleItemId: UUID?
    var kindRaw: String
    var targetExerciseKey: String?
    var replacementCatalogId: String?
    var replacementCustomId: UUID?
    var replacementName: String?
    var replacementInputTypeRaw: String?

    init(_ o: CycleOverride) {
        id = o.id
        scheduleId = o.scheduleId
        cycleNumber = o.cycleNumber
        scheduleItemId = o.scheduleItemId
        kindRaw = o.kindRaw
        targetExerciseKey = o.targetExerciseKey
        replacementCatalogId = o.replacementCatalogId
        replacementCustomId = o.replacementCustomId
        replacementName = o.replacementName
        replacementInputTypeRaw = o.replacementInputTypeRaw
    }

    func make() -> CycleOverride {
        let o = CycleOverride(
            scheduleId: scheduleId ?? UUID(), cycleNumber: cycleNumber,
            scheduleItemId: scheduleItemId ?? UUID(), kind: .skipWorkout
        )
        o.id = id
        o.scheduleId = scheduleId
        o.scheduleItemId = scheduleItemId
        o.kindRaw = kindRaw
        o.targetExerciseKey = targetExerciseKey
        o.replacementCatalogId = replacementCatalogId
        o.replacementCustomId = replacementCustomId
        o.replacementName = replacementName
        o.replacementInputTypeRaw = replacementInputTypeRaw
        return o
    }
}

struct SetLogDTO: Codable {
    var id: UUID
    var orderIndex: Int
    var kindRaw: String
    var weightKg: Double?
    var reps: Int?
    var extraWeightKg: Double?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var rpe: Double?
    var completedAt: Date?
}

struct SessionExerciseDTO: Codable {
    var id: UUID
    var orderIndex: Int
    var catalogId: String?
    var customId: UUID?
    var name: String
    var supersetGroupId: UUID?
    var inputTypeRaw: String
    var restSeconds: Int?
    var isRemoved: Bool
    var sets: [SetLogDTO]
}

struct SessionDTO: Codable {
    var id: UUID
    var templateId: UUID?
    var scheduleId: UUID?
    var name: String
    var kindRaw: String
    var startedAt: Date
    var endedAt: Date?
    var controllingDeviceRaw: String
    var notes: String
    var activeEnergyKilocalories: Double?
    var healthKitWorkoutId: UUID?
    var isImportedFromWorkoutsApp: Bool
    var distanceMeters: Double?
    var averageHeartRate: Double?
    var lastActivityAt: Date
    var exercises: [SessionExerciseDTO]

    init(_ s: Session) {
        id = s.id
        templateId = s.templateId
        scheduleId = s.scheduleId
        name = s.name
        kindRaw = s.kindRaw
        startedAt = s.startedAt
        endedAt = s.endedAt
        controllingDeviceRaw = s.controllingDeviceRaw
        notes = s.notes
        activeEnergyKilocalories = s.activeEnergyKilocalories
        healthKitWorkoutId = s.healthKitWorkoutId
        isImportedFromWorkoutsApp = s.isImportedFromWorkoutsApp
        distanceMeters = s.distanceMeters
        averageHeartRate = s.averageHeartRate
        lastActivityAt = s.lastActivityAt
        exercises = s.orderedExercises.map { e in
            SessionExerciseDTO(
                id: e.id, orderIndex: e.orderIndex, catalogId: e.exerciseCatalogId, customId: e.exerciseCustomId,
                name: e.exerciseName, supersetGroupId: e.supersetGroupId, inputTypeRaw: e.inputTypeRaw,
                restSeconds: e.restSeconds, isRemoved: e.isRemoved,
                sets: e.orderedSets.map {
                    SetLogDTO(
                        id: $0.id, orderIndex: $0.orderIndex, kindRaw: $0.kindRaw, weightKg: $0.weightKg,
                        reps: $0.reps, extraWeightKg: $0.extraWeightKg, durationSeconds: $0.durationSeconds,
                        distanceMeters: $0.distanceMeters, rpe: $0.rpe, completedAt: $0.completedAt
                    )
                }
            )
        }
    }

    func make(in context: ModelContext) -> Session {
        let s = Session(name: name, startedAt: startedAt)
        s.id = id
        s.templateId = templateId
        s.scheduleId = scheduleId
        s.kindRaw = kindRaw
        s.endedAt = endedAt
        s.state = .finished
        s.controllingDeviceRaw = controllingDeviceRaw
        s.notes = notes
        s.activeEnergyKilocalories = activeEnergyKilocalories
        s.healthKitWorkoutId = healthKitWorkoutId
        s.isImportedFromWorkoutsApp = isImportedFromWorkoutsApp
        s.distanceMeters = distanceMeters
        s.averageHeartRate = averageHeartRate
        s.lastActivityAt = lastActivityAt
        context.insert(s)
        for item in exercises {
            let e = SessionExercise(orderIndex: item.orderIndex, exercise: ExerciseRef(
                catalogId: item.catalogId, customExerciseId: item.customId, name: item.name
            ))
            e.id = item.id
            e.supersetGroupId = item.supersetGroupId
            e.inputTypeRaw = item.inputTypeRaw
            e.restSeconds = item.restSeconds
            e.isRemoved = item.isRemoved
            context.insert(e)
            e.session = s
            for setItem in item.sets {
                let l = SetLog(orderIndex: setItem.orderIndex)
                l.id = setItem.id
                l.kindRaw = setItem.kindRaw
                l.weightKg = setItem.weightKg
                l.reps = setItem.reps
                l.extraWeightKg = setItem.extraWeightKg
                l.durationSeconds = setItem.durationSeconds
                l.distanceMeters = setItem.distanceMeters
                l.rpe = setItem.rpe
                l.completedAt = setItem.completedAt
                context.insert(l)
                l.exercise = e
            }
        }
        return s
    }
}

struct MeasurementDTO: Codable {
    var id: UUID
    var kindRaw: String
    var customName: String?
    var value: Double
    var date: Date
    var sourceRaw: String

    init(_ m: BodyMeasurement) {
        id = m.id
        kindRaw = m.kindRaw
        customName = m.customName
        value = m.value
        date = m.date
        sourceRaw = m.sourceRaw
    }

    func make() -> BodyMeasurement {
        let m = BodyMeasurement(kind: .custom, value: value, date: date)
        m.id = id
        m.kindRaw = kindRaw
        m.customName = customName
        m.sourceRaw = sourceRaw
        return m
    }
}

struct DashboardCardDTO: Codable {
    var id: UUID
    var kindRaw: String
    var orderIndex: Int
    var settingsJSON: String

    init(_ c: DashboardCard) {
        id = c.id
        kindRaw = c.kindRaw
        orderIndex = c.orderIndex
        settingsJSON = c.settingsJSON
    }

    func make() -> DashboardCard {
        let c = DashboardCard(kindRaw: kindRaw, orderIndex: orderIndex)
        c.id = id
        c.settingsJSON = settingsJSON
        return c
    }
}
