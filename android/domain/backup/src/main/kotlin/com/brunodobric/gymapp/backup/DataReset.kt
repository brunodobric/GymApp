package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.model.GymStore

/**
 * "Obriši sve podatke": briše sve korisničke zapise na uređaju. Postavke se brišu zadnje i ponovno nastaju
 * kao zadane (pri prvom [GymStore.settings]). Djeca se brišu s roditeljima.
 */
object DataReset {
    fun deleteAll(store: GymStore) {
        store.sessions.toList().forEach(store::delete)
        store.templates.toList().forEach(store::delete)
        store.schedules.toList().forEach(store::delete)
        store.cycleOverrides.toList().forEach(store::delete)
        store.customExercises.toList().forEach(store::delete)
        store.bodyMeasurements.toList().forEach(store::delete)
        store.dashboardCards.toList().forEach(store::delete)
        store.settingsRecords.toList().forEach(store::delete)
        store.save()
    }
}
