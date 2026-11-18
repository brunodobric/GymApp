package com.brunodobric.gymapp.ui.statistics

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.stats.StatisticsSettings
import com.brunodobric.gymapp.stats.StatisticsSnapshot
import com.brunodobric.gymapp.stats.StatisticsSnapshotBuilder
import com.brunodobric.gymapp.ui.rememberStoreRevision
import java.time.LocalDate
import kotlinx.coroutines.delay

/**
 * Statistika izračunata unaprijed (`StatisticsStore` na iOS-u), da je tab Statistika spreman čim ga korisnik
 * otvori. Prije se sve računalo pri svakom ulasku na tab.
 *
 * `GymStore` se čita s glavne niti, pa se i ovo računa na njoj, ali dok je korisnik na drugom tabu: nakon
 * pokretanja i nakon izmjene podataka ili postavki, uz kratku odgodu da se više spremanja spoji u jedno.
 */
class StatisticsCache(private val services: AppServices) {
    /** Zadnji izračun; null dok prvi ne završi. */
    var snapshot by mutableStateOf<StatisticsSnapshot?>(null)
        private set

    /** Razdoblje kartice Mišići u danima. Promjena računa samo tu karticu. */
    var muscleDays by mutableIntStateOf(MUSCLE_PERIODS.first())
        private set

    private data class Key(val revision: Long, val day: LocalDate, val settings: StatisticsSettings)

    private var computedKey: Key? = null

    /** Novi izračun ako su se od zadnjeg promijenili podaci, dan ili postavke. */
    fun refresh(revision: Long, settings: StatisticsSettings) {
        val key = Key(revision, LocalDate.now(), settings)
        if (key == computedKey) return
        computedKey = key
        snapshot = StatisticsSnapshotBuilder.make(services.store, services.catalog, settings, muscleDays)
    }

    fun changeMuscleDays(days: Int) {
        if (days == muscleDays) return
        muscleDays = days
        val current = snapshot ?: return
        if (!current.isPro) return
        snapshot = current.copy(
            muscleDays = days,
            heatmap = StatisticsSnapshotBuilder.heatmap(services.store, services.catalog, days),
        )
    }

    companion object {
        /** Odgoda nakon spremanja, kao `DataVersion.debounce` na iOS-u. */
        const val DEBOUNCE_MILLIS = 800L
    }
}

/**
 * Preračun statistike u korijenu aplikacije (ne na ekranu Statistika). Za vrijeme treninga svaka serija
 * sprema bazu, a završeni treninzi se ne mijenjaju, pa se statistika preračuna tek nakon treninga.
 */
@Composable
fun StatisticsPrecompute(services: AppServices) {
    val revision = rememberStoreRevision(services.store)
    val settings = StatisticsSettings.of(services.store.settings())
    LaunchedEffect(revision, settings) {
        // Odgoda i pri pokretanju, da prvi prikaz Početne ne čeka na statistiku.
        delay(StatisticsCache.DEBOUNCE_MILLIS)
        if (services.statistics.snapshot != null && services.store.activeSession() != null) return@LaunchedEffect
        services.statistics.refresh(revision, settings)
    }
}
