package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.uppercaseString
import com.brunodobric.gymapp.units.WeightUnit

/**
 * Koji od više zapisa postavki vrijedi (`UserSettings.preferred(in:)` na iOS-u).
 * Prednost ima zapis s obavljenim onboardingom, zatim onaj koji se više razlikuje od zadanih
 * vrijednosti, zatim najmanji `id`. Pravilo je isto na svim uređajima.
 */
object UserSettingsChoice {
    fun preferred(all: List<UserSettings>): UserSettings? {
        if (all.size <= 1) return all.firstOrNull()
        val defaults = UserSettings()
        return all.minWithOrNull(
            compareByDescending<UserSettings> { it.onboardingCompleted }
                .thenByDescending { it.changeCount(defaults) }
                .thenBy { it.id.uppercaseString },
        )
    }

    /** Jedinica težine iz važećeg zapisa postavki, a bez postavki kilogrami. */
    fun weightUnit(all: List<UserSettings>): WeightUnit = preferred(all)?.weightUnit ?: WeightUnit.KILOGRAMS
}

/** Koliko se postavki razlikuje od zadanih. */
fun UserSettings.changeCount(defaults: UserSettings): Int = listOf(
    weightUnitRaw to defaults.weightUnitRaw,
    defaultRestSeconds to defaults.defaultRestSeconds,
    compoundRestSeconds to defaults.compoundRestSeconds,
    themeRaw to defaults.themeRaw,
    accentColorRaw to defaults.accentColorRaw,
    effortScaleRaw to defaults.effortScaleRaw,
    prEnabled to defaults.prEnabled,
    trackedPRKindsRaw to defaults.trackedPRKindsRaw,
    prExcludedExercisesRaw to defaults.prExcludedExercisesRaw,
    statsDetailRaw to defaults.statsDetailRaw,
    sexRaw to defaults.sexRaw,
    restEndSoundEnabled to defaults.restEndSoundEnabled,
    availablePlatesRaw to defaults.availablePlatesRaw,
    barbellWeightKg to defaults.barbellWeightKg,
    equipmentWeightStepsRaw to defaults.equipmentWeightStepsRaw,
    exerciseWeightStepsRaw to defaults.exerciseWeightStepsRaw,
    goalRaw to defaults.goalRaw,
    experienceRaw to defaults.experienceRaw,
    equipmentRaw to defaults.equipmentRaw,
    trainingDaysPerWeek to defaults.trainingDaysPerWeek,
    wantsHealthKit to defaults.wantsHealthKit,
    notificationsEnabled to defaults.notificationsEnabled,
    restNotificationEnabled to defaults.restNotificationEnabled,
    startsWatchWorkout to defaults.startsWatchWorkout,
    bodyMapFemale to defaults.bodyMapFemale,
    liveActivityFollowsApp to defaults.liveActivityFollowsApp,
    liveActivityThemeRaw to defaults.liveActivityThemeRaw,
    liveActivityAccentRaw to defaults.liveActivityAccentRaw,
).count { it.first != it.second }
