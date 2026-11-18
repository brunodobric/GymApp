package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Sex
import com.brunodobric.gymapp.model.StatsDetail
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.model.UserSettings
import com.brunodobric.gymapp.training.PRKind
import java.time.Instant

/**
 * Postavke koje mijenjaju statistiku, kao vrijednost (`StatisticsSettings` na iOS-u). Promjena postavki
 * pokreće novi izračun i kad se podaci nisu promijenili.
 */
data class StatisticsSettings(
    val goal: TrainingGoal?,
    val plannedPerWeek: Int?,
    val sex: Sex?,
    val isPro: Boolean,
    val trackedKinds: Set<PRKind>,
    val excludedExercises: Set<String>,
) {
    companion object {
        fun of(settings: UserSettings?): StatisticsSettings = StatisticsSettings(
            goal = settings?.goal,
            plannedPerWeek = settings?.trainingDaysPerWeek,
            sex = settings?.sex,
            isPro = settings?.statsDetail == StatsDetail.PRO,
            trackedKinds = PRKind.tracked(settings),
            excludedExercises = settings?.prExcludedExerciseKeys.orEmpty(),
        )
    }
}

/**
 * Teški dio ekrana Statistika, izračunat odjednom (`StatisticsSnapshot` na iOS-u). Aplikacija ga slaže
 * nakon pokretanja i nakon svake izmjene podataka, pa je tab spreman prije nego što ga korisnik otvori.
 * Pregled razdoblja (tjedan, mjesec, godina s odabirom datuma) računa ekran sam, jer ovisi o odabiru.
 */
data class StatisticsSnapshot(
    val muscleDays: Int,
    /** Jesu li izračunate kartice detaljnog prikaza ([StatsDetail.PRO]). */
    val isPro: Boolean = false,
    val records: List<RecordEntry> = emptyList(),
    val heatmap: Map<String, RegionLoad> = emptyMap(),
    val trends: List<StrengthTrend> = emptyList(),
    val weekly: Pair<WeeklyReview, List<Suggestion>>? = null,
    val effort: EffortDistribution? = null,
    val intensity: IntensityDistribution? = null,
    val dots: DotsScore? = null,
)

object StatisticsSnapshotBuilder {
    /** Kartica Napor i intenzitet gleda zadnja četiri tjedna. */
    private const val EFFORT_WINDOW_SECONDS = 28L * 24 * 3600

    fun make(
        store: GymStore,
        catalog: ExerciseCatalog?,
        settings: StatisticsSettings,
        muscleDays: Int,
        now: Instant = Instant.now(),
    ): StatisticsSnapshot {
        val engine = StatisticsEngine(store)
        val records = engine.personalRecords(settings.trackedKinds, settings.excludedExercises)
        // Ostale kartice su samo u detaljnom prikazu, pa se u osnovnom ne računaju.
        if (!settings.isPro) return StatisticsSnapshot(muscleDays = muscleDays, records = records)
        val info = ExerciseInfoBuilder.provider(catalog, store.customExercises)
        val end = now.plusSeconds(1)
        val monthStart = now.minusSeconds(EFFORT_WINDOW_SECONDS)
        // DOTS uz spol i zadnju upisanu tjelesnu težinu.
        val bodyWeight = BodyTracking(store).latest(BodyMeasurementKind.WEIGHT)?.value
        val sex = settings.sex
        return StatisticsSnapshot(
            muscleDays = muscleDays,
            isPro = true,
            records = records,
            heatmap = heatmap(engine, info, muscleDays, now),
            trends = engine.strengthTrends(now = now, info = info),
            weekly = engine.weeklyReview(now = now, goal = settings.goal, plannedPerWeek = settings.plannedPerWeek, info = info),
            effort = engine.effortDistribution(monthStart, end),
            intensity = engine.intensityDistribution(monthStart, end),
            dots = if (sex != null && bodyWeight != null && bodyWeight > 0) engine.dotsScore(bodyWeight, sex, now = now) else null,
        )
    }

    /** Samo kartica Mišići, kad korisnik promijeni njeno razdoblje. */
    fun heatmap(store: GymStore, catalog: ExerciseCatalog?, days: Int, now: Instant = Instant.now()): Map<String, RegionLoad> =
        heatmap(StatisticsEngine(store), ExerciseInfoBuilder.provider(catalog, store.customExercises), days, now)

    private fun heatmap(engine: StatisticsEngine, info: ExerciseInfoProvider, days: Int, now: Instant): Map<String, RegionLoad> =
        engine.heatmap(now.minusSeconds(days * 24L * 3600), now.plusSeconds(1), info)
}
