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
    exerciseNotesRaw to defaults.exerciseNotesRaw,
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

/**
 * Uklanjanje duplikata nakon sinkronizacije (`Deduplication` na iOS-u). Graf nema dva zapisa s istim UUID-om, ali
 * svaki uređaj stvara svoje postavke i zadane kartice Početne, pa ih nakon spajanja može biti više.
 */
object Deduplication {

    /** Postavke i kartice Početne. Vraća broj obrisanih zapisa (sprema samo kad je nešto obrisano). */
    fun removeAll(store: GymStore): Int = removeDuplicateSettings(store) + removeDuplicateDashboardCards(store)

    /** Ostaje jedan zapis postavki, po istom pravilu na svim uređajima ([UserSettingsChoice.preferred]). */
    fun removeDuplicateSettings(store: GymStore): Int {
        val all = store.settingsRecords.toList()
        val kept = UserSettingsChoice.preferred(all) ?: return 0
        if (all.size <= 1) return 0
        all.filter { it !== kept }.forEach(store::delete)
        store.save()
        return all.size - 1
    }

    /**
     * Ista vrsta kartice dodana na dva uređaja: ostaje kartica s manjim `orderIndex` (pa manjim id-om), a redoslijed
     * se ponovno numerira. Kartice nepoznate vrste (iz novije verzije) se ne diraju.
     */
    fun removeDuplicateDashboardCards(store: GymStore): Int {
        val cards = store.dashboardCards.sortedWith(compareBy<DashboardCard> { it.orderIndex }.thenBy { it.id.uppercaseString })
        val seen = mutableSetOf<String>()
        val kept = mutableListOf<DashboardCard>()
        var removed = 0
        for (card in cards) {
            if (DashboardCardKind.fromRaw(card.kindRaw) != null && !seen.add(card.kindRaw)) {
                store.delete(card)
                removed++
            } else {
                kept += card
            }
        }
        if (removed == 0) return 0
        kept.forEachIndexed { index, card -> if (card.orderIndex != index) card.orderIndex = index }
        store.save()
        return removed
    }
}
