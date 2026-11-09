package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.catalog.uppercaseString
import com.brunodobric.gymapp.model.BodyMeasurement
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.CustomExercise
import com.brunodobric.gymapp.model.CycleOverride
import com.brunodobric.gymapp.model.CycleOverrideKind
import com.brunodobric.gymapp.model.DashboardCard
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.ScheduleItem
import com.brunodobric.gymapp.model.ScheduleItemKind
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.StatsDetail
import com.brunodobric.gymapp.model.TemplateExercise
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.UUIDSerializer
import com.brunodobric.gymapp.model.UserSettings
import com.brunodobric.gymapp.model.WorkoutTemplate
import java.time.Instant
import java.util.Base64
import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

// Zapis JSON kopije, polje po polje kao `BackupModels.swift` na iOS-u, da se kopija može prenijeti između platformi.

/**
 * Datum kao na iOS-u (`JSONEncoder` sa zadanom strategijom): sekunde od 1. 1. 2001. kao decimalni broj.
 * Pretvara se preko mikrosekundi, koliko točnosti `Double` ovdje stvarno nosi.
 */
object AppleDateSerializer : KSerializer<Instant> {
    /** 1. 1. 2001. 00:00 UTC u sekundama od 1970. */
    const val REFERENCE_EPOCH_SECONDS = 978_307_200L

    override val descriptor = PrimitiveSerialDescriptor("AppleDate", PrimitiveKind.DOUBLE)

    /** Zaokružuje na mikrosekundu, pa uvoz pa izvoz daje isti broj. */
    fun toDouble(value: Instant): Double {
        val micros = Math.round(value.nano / 1_000.0)
        return (value.epochSecond - REFERENCE_EPOCH_SECONDS) + micros / 1_000_000.0
    }

    fun fromDouble(seconds: Double): Instant {
        val micros = Math.round(seconds * 1_000_000)
        return Instant.ofEpochSecond(REFERENCE_EPOCH_SECONDS + Math.floorDiv(micros, 1_000_000L), Math.floorMod(micros, 1_000_000L) * 1_000)
    }

    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeDouble(toDouble(value))
    override fun deserialize(decoder: Decoder): Instant = fromDouble(decoder.decodeDouble())
}

/** Bajtovi kao Base64 tekst (kao `Data` u `JSONEncoder`u). */
object Base64Serializer : KSerializer<ByteArray> {
    override val descriptor = PrimitiveSerialDescriptor("Base64", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: ByteArray) = encoder.encodeString(Base64.getEncoder().encodeToString(value))
    override fun deserialize(decoder: Decoder): ByteArray = Base64.getDecoder().decode(decoder.decodeString())
}

private typealias Id = @Serializable(with = UUIDSerializer::class) UUID
private typealias Date = @Serializable(with = AppleDateSerializer::class) Instant
private typealias Bytes = @Serializable(with = Base64Serializer::class) ByteArray

@Serializable
internal data class BackupFile(
    val format: String,
    val version: Int,
    val exportedAt: Date,
    val settings: SettingsDTO? = null,
    val customExercises: List<CustomExerciseDTO> = emptyList(),
    val templates: List<TemplateDTO> = emptyList(),
    val schedules: List<ScheduleDTO> = emptyList(),
    val cycleOverrides: List<CycleOverrideDTO> = emptyList(),
    val sessions: List<SessionDTO> = emptyList(),
    val measurements: List<MeasurementDTO> = emptyList(),
    val dashboardCards: List<DashboardCardDTO> = emptyList(),
)

@Serializable
internal data class SettingsDTO(
    val id: Id,
    val weightUnitRaw: String,
    val defaultRestSeconds: Int,
    val themeRaw: String,
    val accentColorRaw: String,
    val effortScaleRaw: String,
    val prEnabled: Boolean,
    val trackedPRKindsRaw: String,
    val restEndSoundEnabled: Boolean,
    val availablePlatesRaw: String,
    val barbellWeightKg: Double,
    val goalRaw: String,
    val experienceRaw: String,
    val equipmentRaw: String,
    val trainingDaysPerWeek: Int? = null,
    val onboardingCompleted: Boolean,
    val wantsHealthKit: Boolean,
    val notificationsEnabled: Boolean,
    // Opcionalno da se mogu učitati kopije napravljene prije dodavanja ovih polja.
    val bodyMapFemale: Boolean? = null,
    val restNotificationEnabled: Boolean? = null,
    val startsWatchWorkout: Boolean? = null,
    val liveActivityFollowsApp: Boolean? = null,
    val liveActivityThemeRaw: String? = null,
    val liveActivityAccentRaw: String? = null,
    val prExcludedExercisesRaw: String? = null,
    val statsDetailRaw: String? = null,
    val sexRaw: String? = null,
    val compoundRestSeconds: Int? = null,
    val equipmentWeightStepsRaw: String? = null,
    val exerciseWeightStepsRaw: String? = null,
) {
    constructor(model: UserSettings) : this(
        id = model.id,
        weightUnitRaw = model.weightUnitRaw,
        defaultRestSeconds = model.defaultRestSeconds,
        themeRaw = model.themeRaw,
        accentColorRaw = model.accentColorRaw,
        effortScaleRaw = model.effortScaleRaw,
        prEnabled = model.prEnabled,
        trackedPRKindsRaw = model.trackedPRKindsRaw,
        restEndSoundEnabled = model.restEndSoundEnabled,
        availablePlatesRaw = model.availablePlatesRaw,
        barbellWeightKg = model.barbellWeightKg,
        goalRaw = model.goalRaw,
        experienceRaw = model.experienceRaw,
        equipmentRaw = model.equipmentRaw,
        trainingDaysPerWeek = model.trainingDaysPerWeek,
        onboardingCompleted = model.onboardingCompleted,
        wantsHealthKit = model.wantsHealthKit,
        notificationsEnabled = model.notificationsEnabled,
        bodyMapFemale = model.bodyMapFemale,
        restNotificationEnabled = model.restNotificationEnabled,
        startsWatchWorkout = model.startsWatchWorkout,
        liveActivityFollowsApp = model.liveActivityFollowsApp,
        liveActivityThemeRaw = model.liveActivityThemeRaw,
        liveActivityAccentRaw = model.liveActivityAccentRaw,
        prExcludedExercisesRaw = model.prExcludedExercisesRaw,
        statsDetailRaw = model.statsDetailRaw,
        sexRaw = model.sexRaw,
        compoundRestSeconds = model.compoundRestSeconds,
        equipmentWeightStepsRaw = model.equipmentWeightStepsRaw,
        exerciseWeightStepsRaw = model.exerciseWeightStepsRaw,
    )

    fun apply(model: UserSettings) {
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
        model.bodyMapFemale = bodyMapFemale ?: false
        model.restNotificationEnabled = restNotificationEnabled ?: true
        model.startsWatchWorkout = startsWatchWorkout ?: true
        model.liveActivityFollowsApp = liveActivityFollowsApp ?: true
        model.liveActivityThemeRaw = liveActivityThemeRaw ?: "system"
        model.liveActivityAccentRaw = liveActivityAccentRaw ?: "blue"
        model.prExcludedExercisesRaw = prExcludedExercisesRaw ?: ""
        model.statsDetailRaw = statsDetailRaw ?: StatsDetail.BASIC.raw
        model.sexRaw = sexRaw ?: ""
        model.compoundRestSeconds = compoundRestSeconds ?: 150
        model.equipmentWeightStepsRaw = equipmentWeightStepsRaw ?: ""
        model.exerciseWeightStepsRaw = exerciseWeightStepsRaw ?: ""
    }
}

@Serializable
internal class CustomExerciseDTO(
    val id: Id,
    val name: String,
    val details: String,
    val categoryRaw: String,
    val musclesRaw: String,
    val equipmentRaw: String,
    val inputTypeRaw: String,
    /** Null u kopiji iz verzije prije vrste vježbe. */
    val kindRaw: String? = null,
    /** Slika je u kopiji kao bajtovi; u aplikaciji je zasebna datoteka (`imageFile`). */
    val imageData: Bytes? = null,
    val isArchived: Boolean,
    val createdAt: Date,
) {
    constructor(model: CustomExercise, imageData: ByteArray?) : this(
        model.id, model.name, model.details, model.categoryRaw, model.musclesRaw, model.equipmentRaw,
        model.inputTypeRaw, model.kindRaw, imageData, model.isArchived, model.createdAt,
    )

    fun make(saveImage: (UUID, ByteArray) -> String?): CustomExercise {
        val model = CustomExercise(id)
        model.name = name
        model.details = details
        model.categoryRaw = categoryRaw
        model.musclesRaw = musclesRaw
        model.equipmentRaw = equipmentRaw
        model.inputTypeRaw = inputTypeRaw
        model.kindRaw = kindRaw ?: ""
        model.imageFile = imageData?.let { saveImage(id, it) }
        model.isArchived = isArchived
        model.createdAt = createdAt
        return model
    }
}

@Serializable
internal data class TemplateSetDTO(
    val id: Id,
    val orderIndex: Int,
    val kindRaw: String,
    val targetWeightKg: Double? = null,
    val targetReps: Int? = null,
    /** Nema u starijim kopijama. */
    val targetRepsMax: Int? = null,
)

@Serializable
internal data class TemplateExerciseDTO(
    val id: Id,
    val orderIndex: Int,
    val catalogId: String? = null,
    val customId: Id? = null,
    val name: String,
    val inputTypeRaw: String,
    val supersetGroupId: Id? = null,
    val restSeconds: Int? = null,
    val notes: String,
    val sets: List<TemplateSetDTO>,
)

@Serializable
internal data class TemplateDTO(
    val id: Id,
    val name: String,
    val details: String,
    val kindRaw: String,
    val createdAt: Date,
    val exercises: List<TemplateExerciseDTO>,
) {
    constructor(template: WorkoutTemplate) : this(
        template.id, template.name, template.details, template.kindRaw, template.createdAt,
        template.orderedExercises.map { exercise ->
            TemplateExerciseDTO(
                exercise.id, exercise.orderIndex, exercise.exerciseCatalogId, exercise.exerciseCustomId,
                exercise.exerciseName, exercise.inputTypeRaw, exercise.supersetGroupId, exercise.restSeconds, exercise.notes,
                exercise.orderedSets.map {
                    TemplateSetDTO(it.id, it.orderIndex, it.kindRaw, it.targetWeightKg, it.targetReps, it.targetRepsMax)
                },
            )
        },
    )

    fun make(store: GymStore): WorkoutTemplate {
        val template = WorkoutTemplate(id)
        template.name = name
        template.details = details
        template.kindRaw = kindRaw
        template.createdAt = createdAt
        store.insert(template)
        for (item in exercises) {
            val exercise = TemplateExercise(item.orderIndex, ExerciseRef(item.catalogId, item.customId, item.name))
            exercise.id = item.id
            exercise.inputTypeRaw = item.inputTypeRaw
            exercise.supersetGroupId = item.supersetGroupId
            exercise.restSeconds = item.restSeconds
            exercise.notes = item.notes
            template.add(exercise)
            for (setItem in item.sets) {
                val set = TemplateSet(setItem.orderIndex)
                set.id = setItem.id
                set.kindRaw = setItem.kindRaw
                set.targetWeightKg = setItem.targetWeightKg
                set.targetReps = setItem.targetReps
                set.targetRepsMax = setItem.targetRepsMax
                exercise.add(set)
            }
        }
        return template
    }
}

@Serializable
internal data class ScheduleItemDTO(
    val id: Id,
    val orderIndex: Int,
    val kindRaw: String,
    val workoutTemplateId: Id? = null,
)

@Serializable
internal data class ScheduleDTO(
    val id: Id,
    val name: String,
    val details: String,
    val cycleCount: Int? = null,
    val reminderModeRaw: String,
    val weekdaysRaw: String,
    val reminderMinutes: Int? = null,
    val reminderGapDays: Int,
    val isActive: Boolean,
    val currentCycle: Int,
    val currentPosition: Int,
    val createdAt: Date,
    val items: List<ScheduleItemDTO>,
) {
    constructor(schedule: Schedule) : this(
        schedule.id, schedule.name, schedule.details, schedule.cycleCount, schedule.reminderModeRaw, schedule.weekdaysRaw,
        schedule.reminderMinutes, schedule.reminderGapDays, schedule.isActive, schedule.currentCycle,
        schedule.currentPosition, schedule.createdAt,
        schedule.orderedItems.map { ScheduleItemDTO(it.id, it.orderIndex, it.kindRaw, it.workoutTemplateId) },
    )

    fun make(store: GymStore): Schedule {
        val schedule = Schedule(id)
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
        schedule.createdAt = createdAt
        store.insert(schedule)
        for (item in items) {
            val scheduleItem = ScheduleItem(item.orderIndex, ScheduleItemKind.WORKOUT, item.workoutTemplateId)
            scheduleItem.id = item.id
            scheduleItem.kindRaw = item.kindRaw
            schedule.add(scheduleItem)
        }
        return schedule
    }
}

@Serializable
internal data class CycleOverrideDTO(
    val id: Id,
    val scheduleId: Id? = null,
    val cycleNumber: Int,
    val scheduleItemId: Id? = null,
    val kindRaw: String,
    val targetExerciseKey: String? = null,
    val replacementCatalogId: String? = null,
    val replacementCustomId: Id? = null,
    val replacementName: String? = null,
    val replacementInputTypeRaw: String? = null,
) {
    constructor(model: CycleOverride) : this(
        model.id, model.scheduleId, model.cycleNumber, model.scheduleItemId, model.kindRaw, model.targetExerciseKey,
        model.replacementCatalogId, model.replacementCustomId, model.replacementName, model.replacementInputTypeRaw,
    )

    fun make(): CycleOverride {
        val model = CycleOverride(UUID.randomUUID(), cycleNumber, UUID.randomUUID(), CycleOverrideKind.SKIP_WORKOUT)
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

@Serializable
internal data class SetLogDTO(
    val id: Id,
    val orderIndex: Int,
    val kindRaw: String,
    val weightKg: Double? = null,
    val reps: Int? = null,
    val extraWeightKg: Double? = null,
    val durationSeconds: Int? = null,
    val distanceMeters: Double? = null,
    val rpe: Double? = null,
    val completedAt: Date? = null,
)

@Serializable
internal data class SessionExerciseDTO(
    val id: Id,
    val orderIndex: Int,
    val catalogId: String? = null,
    val customId: Id? = null,
    val name: String,
    val supersetGroupId: Id? = null,
    val inputTypeRaw: String,
    val restSeconds: Int? = null,
    val isRemoved: Boolean,
    val sets: List<SetLogDTO>,
)

@Serializable
internal data class SessionDTO(
    val id: Id,
    val templateId: Id? = null,
    val scheduleId: Id? = null,
    val name: String,
    val kindRaw: String,
    val startedAt: Date,
    val endedAt: Date? = null,
    val controllingDeviceRaw: String,
    val notes: String,
    val activeEnergyKilocalories: Double? = null,
    val healthKitWorkoutId: Id? = null,
    val isImportedFromWorkoutsApp: Boolean,
    val distanceMeters: Double? = null,
    val averageHeartRate: Double? = null,
    /** Napor treninga (session RPE). Nedostaje u starijim kopijama. */
    val sessionRPE: Double? = null,
    val lastActivityAt: Date,
    val exercises: List<SessionExerciseDTO>,
) {
    constructor(session: Session) : this(
        id = session.id,
        templateId = session.templateId,
        scheduleId = session.scheduleId,
        name = session.name,
        kindRaw = session.kindRaw,
        startedAt = session.startedAt,
        endedAt = session.endedAt,
        controllingDeviceRaw = session.controllingDeviceRaw,
        notes = session.notes,
        activeEnergyKilocalories = session.activeEnergyKilocalories,
        healthKitWorkoutId = session.healthKitWorkoutId,
        isImportedFromWorkoutsApp = session.isImportedFromWorkoutsApp,
        distanceMeters = session.distanceMeters,
        averageHeartRate = session.averageHeartRate,
        sessionRPE = session.sessionRPE,
        lastActivityAt = session.lastActivityAt,
        exercises = session.orderedExercises.map { exercise ->
            SessionExerciseDTO(
                exercise.id, exercise.orderIndex, exercise.exerciseCatalogId, exercise.exerciseCustomId, exercise.exerciseName,
                exercise.supersetGroupId, exercise.inputTypeRaw, exercise.restSeconds, exercise.isRemoved,
                exercise.orderedSets.map {
                    SetLogDTO(
                        it.id, it.orderIndex, it.kindRaw, it.weightKg, it.reps, it.extraWeightKg, it.durationSeconds,
                        it.distanceMeters, it.rpe, it.completedAt,
                    )
                },
            )
        },
    )

    fun make(store: GymStore): Session {
        val session = Session(id)
        session.name = name
        session.startedAt = startedAt
        session.templateId = templateId
        session.scheduleId = scheduleId
        session.kindRaw = kindRaw
        session.endedAt = endedAt
        session.state = SessionState.FINISHED
        session.controllingDeviceRaw = controllingDeviceRaw
        session.notes = notes
        session.activeEnergyKilocalories = activeEnergyKilocalories
        session.healthKitWorkoutId = healthKitWorkoutId
        session.isImportedFromWorkoutsApp = isImportedFromWorkoutsApp
        session.distanceMeters = distanceMeters
        session.averageHeartRate = averageHeartRate
        session.sessionRPE = sessionRPE
        session.lastActivityAt = lastActivityAt
        store.insert(session)
        for (item in exercises) {
            val exercise = SessionExercise(item.orderIndex, ExerciseRef(item.catalogId, item.customId, item.name))
            exercise.id = item.id
            exercise.supersetGroupId = item.supersetGroupId
            exercise.inputTypeRaw = item.inputTypeRaw
            exercise.restSeconds = item.restSeconds
            exercise.isRemoved = item.isRemoved
            session.add(exercise)
            for (setItem in item.sets) {
                val set = SetLog(setItem.orderIndex)
                set.id = setItem.id
                set.kindRaw = setItem.kindRaw
                set.weightKg = setItem.weightKg
                set.reps = setItem.reps
                set.extraWeightKg = setItem.extraWeightKg
                set.durationSeconds = setItem.durationSeconds
                set.distanceMeters = setItem.distanceMeters
                set.rpe = setItem.rpe
                set.completedAt = setItem.completedAt
                exercise.add(set)
            }
        }
        return session
    }
}

@Serializable
internal data class MeasurementDTO(
    val id: Id,
    val kindRaw: String,
    val customName: String? = null,
    val value: Double,
    val date: Date,
    val sourceRaw: String,
    /** Nije postojalo u starijim kopijama, pa je opcionalno. */
    val healthKitSampleId: Id? = null,
) {
    constructor(model: BodyMeasurement) : this(
        model.id, model.kindRaw, model.customName, model.value, model.date, model.sourceRaw, model.healthKitSampleId,
    )

    fun make(): BodyMeasurement {
        val model = BodyMeasurement(BodyMeasurementKind.CUSTOM, value, date)
        model.id = id
        model.kindRaw = kindRaw
        model.customName = customName
        model.sourceRaw = sourceRaw
        model.healthKitSampleId = healthKitSampleId
        return model
    }
}

@Serializable
internal data class DashboardCardDTO(
    val id: Id,
    val kindRaw: String,
    val orderIndex: Int,
    val settingsJSON: String,
) {
    constructor(model: DashboardCard) : this(model.id, model.kindRaw, model.orderIndex, model.settingsJSON)

    fun make(): DashboardCard {
        val model = DashboardCard(kindRaw, orderIndex)
        model.id = id
        model.settingsJSON = settingsJSON
        return model
    }
}

/** Redoslijed kao na iOS-u (`uuidString`): UUID velikim slovima. */
internal val UUID.sortKey: String get() = uppercaseString
