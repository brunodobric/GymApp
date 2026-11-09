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
    /// Opcionalno da se mogu učitati kopije napravljene prije dodavanja ovog polja.
    var bodyMapFemale: Bool?
    var restNotificationEnabled: Bool?
    var startsWatchWorkout: Bool?
    var liveActivityFollowsApp: Bool?
    var liveActivityThemeRaw: String?
    var liveActivityAccentRaw: String?
    var prExcludedExercisesRaw: String?
    var statsDetailRaw: String?
    var sexRaw: String?
    var compoundRestSeconds: Int?

    init(_ model: UserSettings) {
        id = model.id
        weightUnitRaw = model.weightUnitRaw
        defaultRestSeconds = model.defaultRestSeconds
        themeRaw = model.themeRaw
        accentColorRaw = model.accentColorRaw
        effortScaleRaw = model.effortScaleRaw
        prEnabled = model.prEnabled
        trackedPRKindsRaw = model.trackedPRKindsRaw
        restEndSoundEnabled = model.restEndSoundEnabled
        availablePlatesRaw = model.availablePlatesRaw
        barbellWeightKg = model.barbellWeightKg
        goalRaw = model.goalRaw
        experienceRaw = model.experienceRaw
        equipmentRaw = model.equipmentRaw
        trainingDaysPerWeek = model.trainingDaysPerWeek
        onboardingCompleted = model.onboardingCompleted
        wantsHealthKit = model.wantsHealthKit
        notificationsEnabled = model.notificationsEnabled
        bodyMapFemale = model.bodyMapFemale
        restNotificationEnabled = model.restNotificationEnabled
        startsWatchWorkout = model.startsWatchWorkout
        liveActivityFollowsApp = model.liveActivityFollowsApp
        liveActivityThemeRaw = model.liveActivityThemeRaw
        liveActivityAccentRaw = model.liveActivityAccentRaw
        prExcludedExercisesRaw = model.prExcludedExercisesRaw
        statsDetailRaw = model.statsDetailRaw
        sexRaw = model.sexRaw
        compoundRestSeconds = model.compoundRestSeconds
    }

    func apply(to model: UserSettings) {
        model.id = id
        model.weightUnitRaw = weightUnitRaw
        model.defaultRestSeconds = defaultRestSeconds
        model.themeRaw = themeRaw
        model.accentColorRaw = accentColorRaw
        model.effortScaleRaw = effortScaleRaw
        model.prEnabled = prEnabled
        model.trackedPRKindsRaw = trackedPRKindsRaw
        model.restEndSoundEnabled = restEndSoundEnabled
        model.availablePlatesRaw = availablePlatesRaw
        model.barbellWeightKg = barbellWeightKg
        model.goalRaw = goalRaw
        model.experienceRaw = experienceRaw
        model.equipmentRaw = equipmentRaw
        model.trainingDaysPerWeek = trainingDaysPerWeek
        model.onboardingCompleted = onboardingCompleted
        model.wantsHealthKit = wantsHealthKit
        model.notificationsEnabled = notificationsEnabled
        model.bodyMapFemale = bodyMapFemale ?? false
        model.restNotificationEnabled = restNotificationEnabled ?? true
        model.startsWatchWorkout = startsWatchWorkout ?? true
        model.liveActivityFollowsApp = liveActivityFollowsApp ?? true
        model.liveActivityThemeRaw = liveActivityThemeRaw ?? "system"
        model.liveActivityAccentRaw = liveActivityAccentRaw ?? "blue"
        model.prExcludedExercisesRaw = prExcludedExercisesRaw ?? ""
        model.statsDetailRaw = statsDetailRaw ?? StatsDetail.basic.rawValue
        model.sexRaw = sexRaw ?? ""
        model.compoundRestSeconds = compoundRestSeconds ?? 150
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
    /// Nil u backupu iz verzije prije vrste vježbe.
    var kindRaw: String?
    var imageData: Data?
    var isArchived: Bool
    var createdAt: Date

    init(_ model: CustomExercise) {
        id = model.id
        name = model.name
        details = model.details
        categoryRaw = model.categoryRaw
        musclesRaw = model.musclesRaw
        equipmentRaw = model.equipmentRaw
        inputTypeRaw = model.inputTypeRaw
        kindRaw = model.kindRaw
        imageData = model.imageData
        isArchived = model.isArchived
        createdAt = model.createdAt
    }

    func make() -> CustomExercise {
        let model = CustomExercise(name: name)
        model.id = id
        model.details = details
        model.categoryRaw = categoryRaw
        model.musclesRaw = musclesRaw
        model.equipmentRaw = equipmentRaw
        model.inputTypeRaw = inputTypeRaw
        model.kindRaw = kindRaw ?? ""
        model.imageData = imageData
        model.isArchived = isArchived
        model.createdAt = createdAt
        return model
    }
}

struct TemplateSetDTO: Codable {
    var id: UUID
    var orderIndex: Int
    var kindRaw: String
    var targetWeightKg: Double?
    var targetReps: Int?
    /// Nema u starijim kopijama.
    var targetRepsMax: Int?
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
    /// Kardio plan (faza 10). Nedostaje u starijim kopijama.
    var cardioPlanRaw: String?
    var exercises: [TemplateExerciseDTO]

    init(_ template: WorkoutTemplate) {
        id = template.id
        name = template.name
        details = template.details
        kindRaw = template.kindRaw
        createdAt = template.createdAt
        cardioPlanRaw = template.cardioPlanRaw
        exercises = template.orderedExercises.map { exercise in
            TemplateExerciseDTO(
                id: exercise.id, orderIndex: exercise.orderIndex, catalogId: exercise.exerciseCatalogId, customId: exercise.exerciseCustomId,
                name: exercise.exerciseName, inputTypeRaw: exercise.inputTypeRaw, supersetGroupId: exercise.supersetGroupId,
                restSeconds: exercise.restSeconds, notes: exercise.notes,
                sets: exercise.orderedSets.map {
                    TemplateSetDTO(
                        id: $0.id, orderIndex: $0.orderIndex, kindRaw: $0.kindRaw,
                        targetWeightKg: $0.targetWeightKg, targetReps: $0.targetReps, targetRepsMax: $0.targetRepsMax
                    )
                }
            )
        }
    }

    func make(in context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: name)
        template.id = id
        template.details = details
        template.kindRaw = kindRaw
        template.createdAt = createdAt
        template.cardioPlanRaw = cardioPlanRaw
        context.insert(template)
        for item in exercises {
            let exercise = TemplateExercise(orderIndex: item.orderIndex, exercise: ExerciseRef(
                catalogId: item.catalogId, customExerciseId: item.customId, name: item.name
            ))
            exercise.id = item.id
            exercise.inputTypeRaw = item.inputTypeRaw
            exercise.supersetGroupId = item.supersetGroupId
            exercise.restSeconds = item.restSeconds
            exercise.notes = item.notes
            context.insert(exercise)
            exercise.template = template
            for setItem in item.sets {
                let templateSet = TemplateSet(orderIndex: setItem.orderIndex)
                templateSet.id = setItem.id
                templateSet.kindRaw = setItem.kindRaw
                templateSet.targetWeightKg = setItem.targetWeightKg
                templateSet.targetReps = setItem.targetReps
                templateSet.targetRepsMax = setItem.targetRepsMax
                context.insert(templateSet)
                templateSet.exercise = exercise
            }
        }
        return template
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

    init(_ schedule: Schedule) {
        id = schedule.id
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
        createdAt = schedule.createdAt
        items = schedule.orderedItems.map {
            ScheduleItemDTO(id: $0.id, orderIndex: $0.orderIndex, kindRaw: $0.kindRaw, workoutTemplateId: $0.workoutTemplateId)
        }
    }

    func make(in context: ModelContext) -> Schedule {
        let schedule = Schedule(name: name)
        schedule.id = id
        schedule.details = details
        schedule.cycleCount = cycleCount
        schedule.reminderModeRaw = reminderModeRaw
        schedule.weekdaysRaw = weekdaysRaw
        schedule.reminderMinutes = reminderMinutes
        schedule.reminderGapDays = reminderGapDays
        schedule.isActive = isActive
        schedule.currentCycle = currentCycle
        schedule.currentPosition = currentPosition
        schedule.createdAt = createdAt
        context.insert(schedule)
        for item in items {
            let scheduleItem = ScheduleItem(orderIndex: item.orderIndex, kind: .workout, workoutTemplateId: item.workoutTemplateId)
            scheduleItem.id = item.id
            scheduleItem.kindRaw = item.kindRaw
            context.insert(scheduleItem)
            scheduleItem.schedule = schedule
        }
        return schedule
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

    init(_ model: CycleOverride) {
        id = model.id
        scheduleId = model.scheduleId
        cycleNumber = model.cycleNumber
        scheduleItemId = model.scheduleItemId
        kindRaw = model.kindRaw
        targetExerciseKey = model.targetExerciseKey
        replacementCatalogId = model.replacementCatalogId
        replacementCustomId = model.replacementCustomId
        replacementName = model.replacementName
        replacementInputTypeRaw = model.replacementInputTypeRaw
    }

    func make() -> CycleOverride {
        let model = CycleOverride(
            scheduleId: scheduleId ?? UUID(), cycleNumber: cycleNumber,
            scheduleItemId: scheduleItemId ?? UUID(), kind: .skipWorkout
        )
        model.id = id
        model.scheduleId = scheduleId
        model.scheduleItemId = scheduleItemId
        model.kindRaw = kindRaw
        model.targetExerciseKey = targetExerciseKey
        model.replacementCatalogId = replacementCatalogId
        model.replacementCustomId = replacementCustomId
        model.replacementName = replacementName
        model.replacementInputTypeRaw = replacementInputTypeRaw
        return model
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
    /// Plan iz WorkoutKita (faza 10). Nedostaje u starijim kopijama.
    var workoutPlanId: UUID?
    var distanceMeters: Double?
    var averageHeartRate: Double?
    /// Napor treninga (session RPE). Nedostaje u starijim kopijama.
    var sessionRPE: Double?
    var lastActivityAt: Date
    var exercises: [SessionExerciseDTO]

    init(_ session: Session) {
        id = session.id
        templateId = session.templateId
        scheduleId = session.scheduleId
        name = session.name
        kindRaw = session.kindRaw
        startedAt = session.startedAt
        endedAt = session.endedAt
        controllingDeviceRaw = session.controllingDeviceRaw
        notes = session.notes
        activeEnergyKilocalories = session.activeEnergyKilocalories
        healthKitWorkoutId = session.healthKitWorkoutId
        isImportedFromWorkoutsApp = session.isImportedFromWorkoutsApp
        workoutPlanId = session.workoutPlanId
        distanceMeters = session.distanceMeters
        averageHeartRate = session.averageHeartRate
        sessionRPE = session.sessionRPE
        lastActivityAt = session.lastActivityAt
        exercises = session.orderedExercises.map { exercise in
            SessionExerciseDTO(
                id: exercise.id, orderIndex: exercise.orderIndex, catalogId: exercise.exerciseCatalogId, customId: exercise.exerciseCustomId,
                name: exercise.exerciseName, supersetGroupId: exercise.supersetGroupId, inputTypeRaw: exercise.inputTypeRaw,
                restSeconds: exercise.restSeconds, isRemoved: exercise.isRemoved,
                sets: exercise.orderedSets.map {
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
        let session = Session(name: name, startedAt: startedAt)
        session.id = id
        session.templateId = templateId
        session.scheduleId = scheduleId
        session.kindRaw = kindRaw
        session.endedAt = endedAt
        session.state = .finished
        session.controllingDeviceRaw = controllingDeviceRaw
        session.notes = notes
        session.activeEnergyKilocalories = activeEnergyKilocalories
        session.healthKitWorkoutId = healthKitWorkoutId
        session.isImportedFromWorkoutsApp = isImportedFromWorkoutsApp
        session.workoutPlanId = workoutPlanId
        session.distanceMeters = distanceMeters
        session.averageHeartRate = averageHeartRate
        session.sessionRPE = sessionRPE
        session.lastActivityAt = lastActivityAt
        context.insert(session)
        for item in exercises {
            let exercise = SessionExercise(orderIndex: item.orderIndex, exercise: ExerciseRef(
                catalogId: item.catalogId, customExerciseId: item.customId, name: item.name
            ))
            exercise.id = item.id
            exercise.supersetGroupId = item.supersetGroupId
            exercise.inputTypeRaw = item.inputTypeRaw
            exercise.restSeconds = item.restSeconds
            exercise.isRemoved = item.isRemoved
            context.insert(exercise)
            exercise.session = session
            for setItem in item.sets {
                let setLog = SetLog(orderIndex: setItem.orderIndex)
                setLog.id = setItem.id
                setLog.kindRaw = setItem.kindRaw
                setLog.weightKg = setItem.weightKg
                setLog.reps = setItem.reps
                setLog.extraWeightKg = setItem.extraWeightKg
                setLog.durationSeconds = setItem.durationSeconds
                setLog.distanceMeters = setItem.distanceMeters
                setLog.rpe = setItem.rpe
                setLog.completedAt = setItem.completedAt
                context.insert(setLog)
                setLog.exercise = exercise
            }
        }
        return session
    }
}

struct MeasurementDTO: Codable {
    var id: UUID
    var kindRaw: String
    var customName: String?
    var value: Double
    var date: Date
    var sourceRaw: String
    /// Nije postojalo u starijim kopijama, pa je opcionalno.
    var healthKitSampleId: UUID?

    init(_ model: BodyMeasurement) {
        id = model.id
        kindRaw = model.kindRaw
        customName = model.customName
        value = model.value
        date = model.date
        sourceRaw = model.sourceRaw
        healthKitSampleId = model.healthKitSampleId
    }

    func make() -> BodyMeasurement {
        let model = BodyMeasurement(kind: .custom, value: value, date: date)
        model.id = id
        model.kindRaw = kindRaw
        model.customName = customName
        model.sourceRaw = sourceRaw
        model.healthKitSampleId = healthKitSampleId
        return model
    }
}

struct DashboardCardDTO: Codable {
    var id: UUID
    var kindRaw: String
    var orderIndex: Int
    var settingsJSON: String

    init(_ model: DashboardCard) {
        id = model.id
        kindRaw = model.kindRaw
        orderIndex = model.orderIndex
        settingsJSON = model.settingsJSON
    }

    func make() -> DashboardCard {
        let model = DashboardCard(kindRaw: kindRaw, orderIndex: orderIndex)
        model.id = id
        model.settingsJSON = settingsJSON
        return model
    }
}
