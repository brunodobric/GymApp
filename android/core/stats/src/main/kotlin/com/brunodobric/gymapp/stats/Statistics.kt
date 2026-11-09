package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.PersonalRecord
import com.brunodobric.gymapp.training.PersonalRecordDetector
import com.brunodobric.gymapp.training.RecordHistory
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.values
import java.time.Instant

/** Mišići i regije koje vježba opterećuje. Izvor je katalog ili vlastita vježba; pozivatelj ga daje po ključu vježbe. */
data class ExerciseInfo(
    val primary: List<Muscle> = emptyList(),
    val secondary: List<Muscle> = emptyList(),
    val primaryRegions: List<String> = emptyList(),
    val secondaryRegions: List<String> = emptyList(),
    /** Složena (više zglobova) ili izolacijska vježba iz kataloga. Null kad se ne zna (vlastita vježba). */
    val isCompound: Boolean? = null,
    /**
     * Kardio vježba. Ne broji se u serije po mišiću: 20 minuta trake nije serija za kvadricepse.
     * Njezino vrijeme i udaljenost idu u kardio dio treninga (`SessionCardio`).
     */
    val isCardio: Boolean = false,
)

/** Daje podatke o vježbi prema `ExerciseRef.key`. */
typealias ExerciseInfoProvider = (String) -> ExerciseInfo?

data class ExercisePoint(
    val date: Instant,
    /** Najveća težina radne serije (kg); 0 kad vježba nema težinu. */
    val bestWeightKg: Double,
    /** Ponavljanja najteže serije (uz istu težinu ona s najviše ponavljanja). Bez težine najviše ponavljanja. */
    val bestReps: Int,
    /** Najbolja pouzdana procjena 1RM (s RIR-om, do 12 ponavljanja do otkaza); null bez takve serije. */
    val estimatedOneRepMaxKg: Double?,
    val volumeKg: Double,
)

/** Opterećenje jedne regije u razdoblju grafa. */
data class MuscleLoad(
    /** Tonaža vježbi kojima je regija glavni mišić. */
    var volumeKg: Double = 0.0,
    /** Tvrde serije, pomoćne upola ([EffectiveSets]). */
    var sets: Double = 0.0,
)

enum class BucketSize { WEEK, MONTH }

/** Jedan tjedan ili mjesec: serije po regiji tijela i ukupna tonaža. */
data class VolumeBucket(
    val start: Instant,
    /** Ključ je regija tijela ([BodyRegion.all]). */
    val loads: MutableMap<String, MuscleLoad> = linkedMapOf(),
    /** Ukupna tonaža razdoblja; svaka serija broji se jednom, bez obzira na broj regija vježbe. */
    var totalVolumeKg: Double = 0.0,
    /** Ukupan broj tvrdih serija; svaka serija broji se jednom. */
    var totalSets: Int = 0,
) {
    /**
     * Dodaje tvrde serije snage iz treninga: tonaža i ukupan broj serija jednom po seriji, regije prema
     * [EffectiveSets] (pomoćne upola). Kardio vježbe se preskaču.
     */
    internal fun add(session: Session, info: ExerciseInfoProvider) {
        for (exercise in session.orderedExercises) {
            if (exercise.isRemoved) continue
            val details = info(exercise.exerciseKey) ?: continue
            if (details.isCardio) continue
            val sets = EffectiveSets.hardSets(exercise)
            if (sets.isEmpty()) continue
            val volume = sets.sumOf { SetMetrics.volume(it, exercise.inputType) }
            totalVolumeKg += volume
            totalSets += sets.size
            for ((region, share) in EffectiveSets.regionCounts(sets.size, details)) {
                val load = loads.getOrPut(region) { MuscleLoad() }
                load.sets += share.weighted
                if (share.primary > 0) load.volumeKg += volume
            }
        }
    }
}

data class FrequencyPoint(val weekStart: Instant, val sessions: Int)

data class RecordEntry(val date: Instant, val exerciseKey: String, val exerciseName: String, val record: PersonalRecord)

data class RegionLoad(
    /** Broj treninga u kojima je regija dobila barem jednu cijelu seriju (glavnu ili dvije pomoćne). */
    var sessions: Int = 0,
    var volumeKg: Double = 0.0,
    /** Tvrde serije u razdoblju, pomoćne upola. */
    var sets: Double = 0.0,
    /** Prosjek tvrdih serija tjedno u razdoblju. */
    var weeklySets: Double = 0.0,
    /** Prosjek treninga tjedno (prema [sessions]). */
    var sessionsPerWeek: Double = 0.0,
    var lastTrained: Instant? = null,
    /** Boja heatmapa 0...1 na fiksnoj skali ([LoadScale]). */
    var intensity: Double = 0.0,
) {
    /** Razina na tjednoj skali ([LoadScale.weeklyLevel]). */
    val weeklyLevel: Int get() = LoadScale.weeklyLevel(weeklySets)
}

/** Promjena snage jedne regije: prosjek mjesečnog nagiba procjene 1RM njenih glavnih vježbi. */
data class StrengthTrend(
    val region: String,
    /** Relativna promjena mjesečno (0,05 = +5 % mjesečno). */
    val change: Double,
    /** Broj vježbi koje su rađene u oba razdoblja. */
    val exercises: Int,
)

/** Statistika nad završenim treninzima. Računaju se samo završene radne serije; warm-up se nikad ne broji. */
class StatisticsEngine(val store: GymStore) {

    // MARK: Napredak vježbe

    /** Napredak jedne vježbe kroz vrijeme, od najstarijeg treninga. */
    fun progress(ref: ExerciseRef, formula: SetMetrics.OneRepMaxFormula = SetMetrics.OneRepMaxFormula.EPLEY): List<ExercisePoint> {
        val key = ref.key
        return store.sessions.asSequence()
            .filter { it.state == SessionState.FINISHED }
            .flatMap { session -> session.exercises.asSequence().filter { it.exerciseKey == key && !it.isRemoved }.map { session to it } }
            .mapNotNull { (session, exercise) -> point(exercise, session.startedAt, formula) }
            .sortedBy { it.date }
            .toList()
    }

    // MARK: Serije po mišićnoj skupini

    /**
     * Tvrde serije i tonaža po regiji tijela, za `count` tjedana ili mjeseci koji završavaju
     * onim koji sadrži `now` (od najstarijeg prema najnovijem).
     */
    fun volumeBuckets(
        size: BucketSize,
        count: Int,
        now: Instant = Instant.now(),
        calendar: StatsCalendar = StatsCalendar.system(),
        info: ExerciseInfoProvider,
    ): List<VolumeBucket> {
        val starts = bucketStarts(size, count, now, calendar)
        val first = starts.firstOrNull() ?: return emptyList()
        val end = interval(size, starts.last(), calendar).end
        val buckets = starts.associateWith { VolumeBucket(it) }
        for (session in store.finishedSessions(first, end)) {
            buckets[interval(size, session.startedAt, calendar).start]?.add(session, info)
        }
        return starts.mapNotNull { buckets[it] }
    }

    // MARK: Frekvencija

    /** Broj treninga po tjednu za zadnjih `weeks` tjedana. */
    fun frequency(weeks: Int, now: Instant = Instant.now(), calendar: StatsCalendar = StatsCalendar.system()): List<FrequencyPoint> {
        val starts = bucketStarts(BucketSize.WEEK, weeks, now, calendar)
        val first = starts.firstOrNull() ?: return emptyList()
        val end = calendar.weekInterval(starts.last()).end
        val counts = mutableMapOf<Instant, Int>()
        for (session in store.finishedSessions(first, end)) {
            val start = calendar.weekInterval(session.startedAt).start
            counts[start] = (counts[start] ?: 0) + 1
        }
        return starts.map { FrequencyPoint(it, counts[it] ?: 0) }
    }

    // MARK: Osobni rekordi

    /**
     * Svi rekordi postavljeni kroz povijest, od najnovijeg. Svaki trening se uspoređuje samo s ranijima.
     * Vježbe iz `excluded` (isključene u Postavkama) nemaju rekorda.
     */
    fun personalRecords(kinds: Set<PRKind> = PRKind.entries.toSet(), excluded: Set<String> = emptySet()): List<RecordEntry> {
        if (kinds.isEmpty()) return emptyList()
        val sessions = store.sessions.filter { it.state == SessionState.FINISHED }.sortedBy { it.startedAt }
        // Sažeta povijest daje iste rekorde, a ne raste s brojem treninga.
        val history = mutableMapOf<String, RecordHistory>()
        val entries = mutableListOf<RecordEntry>()
        for (session in sessions) {
            for (exercise in session.orderedExercises) {
                if (exercise.isRemoved) continue
                val done = exercise.orderedSets.filter { it.isCompleted }.map { it.values }
                val key = exercise.exerciseKey
                if (done.isEmpty() || key in excluded) continue
                val past = history.getOrPut(key) { RecordHistory() }
                val found = PersonalRecordDetector.records(done, past, exercise.inputType, kinds, session.startedAt)
                found.forEach { entries += RecordEntry(session.startedAt, key, exercise.exerciseName, it) }
                past.add(done, exercise.inputType, session.startedAt)
            }
        }
        return entries.reversed()
    }

    // MARK: Body heatmap

    /**
     * Opterećenje po regiji tijela u razdoblju: tvrde serije (pomoćne upola), prosjek serija tjedno i
     * učestalost. Boja je na fiksnoj tjednoj skali ([LoadScale.weeklyLevel]), ne relativna.
     * Ako je prvi trening u aplikaciji kasnije od `start`, tjedni se prosjek računa od tog treninga,
     * da novi korisnik ne dobije razvodnjen prosjek.
     */
    fun heatmap(start: Instant, end: Instant, info: ExerciseInfoProvider): Map<String, RegionLoad> {
        val result = LinkedHashMap<String, RegionLoad>()
        for (session in store.finishedSessions(start, end)) {
            val shares = LinkedHashMap<String, RegionShare>()
            val volumes = mutableMapOf<String, Double>()
            for (exercise in session.orderedExercises) {
                if (exercise.isRemoved) continue
                val details = info(exercise.exerciseKey) ?: continue
                if (details.isCardio) continue
                val sets = EffectiveSets.hardSets(exercise)
                if (sets.isEmpty()) continue
                val volume = sets.sumOf { SetMetrics.volume(it, exercise.inputType) }
                for ((region, share) in EffectiveSets.regionCounts(sets.size, details)) {
                    val total = shares.getOrPut(region) { RegionShare(0, 0) }
                    total.primary += share.primary
                    total.secondary += share.secondary
                    volumes[region] = (volumes[region] ?: 0.0) +
                        if (share.primary > 0) volume else volume * EffectiveSets.SECONDARY_WEIGHT
                }
            }
            for ((region, share) in shares) {
                val load = result.getOrPut(region) { RegionLoad() }
                load.sets += share.weighted
                load.volumeKg += volumes[region] ?: 0.0
                if (share.weighted >= 1) {
                    load.sessions += 1
                    load.lastTrained = maxOf(load.lastTrained ?: Instant.MIN, session.startedAt)
                }
            }
        }
        val weeks = weeksCovered(start, end)
        for (load in result.values) {
            load.weeklySets = load.sets / weeks
            load.sessionsPerWeek = load.sessions / weeks
            load.intensity = LoadScale.intensity(LoadScale.weeklyLevel(load.sets / weeks))
        }
        return result
    }

    /** Broj tjedana razdoblja za prosjek, najmanje 1. Počinje najranije s prvim treningom u aplikaciji. */
    internal fun weeksCovered(start: Instant, end: Instant): Double {
        val first = firstSessionDate() ?: start
        val from = maxOf(start, first)
        return maxOf(1.0, secondsBetween(from, end) / (7 * 24 * 3600))
    }

    /** Početak prvog završenog treninga u aplikaciji. */
    fun firstSessionDate(): Instant? =
        store.sessions.filter { it.state == SessionState.FINISHED }.minOfOrNull { it.startedAt }

    // MARK: Trend snage

    /**
     * Promjena snage po regiji: za svaku vježbu s težinom računa se mjesečni nagib procjene 1RM u zadnjih
     * `2 × weeks` tjedana ([TrendAnalysis], otporno na jedan loš ili iznimno dobar dan). Regija dobiva prosjek
     * nagiba vježbi kojima je glavni mišić. Broje se pouzdane serije (do 12 ponavljanja do otkaza).
     * Vježba treba barem [TrendAnalysis.MINIMUM_SESSIONS] izvođenja. Poredak: od najvećeg rasta.
     */
    fun strengthTrends(
        weeks: Int = 4,
        now: Instant = Instant.now(),
        info: ExerciseInfoProvider,
        formula: SetMetrics.OneRepMaxFormula = SetMetrics.OneRepMaxFormula.EPLEY,
    ): List<StrengthTrend> {
        val changes = LinkedHashMap<String, MutableList<Double>>()
        for (trend in exerciseTrends(weeks * 2, now, info, formula)) {
            val monthly = trend.trend.monthlyChange ?: continue
            if (trend.trend.status == ExerciseStatus.INSUFFICIENT_DATA) continue
            val details = info(trend.key) ?: continue
            for (region in details.primaryRegions) changes.getOrPut(region) { mutableListOf() } += monthly
        }
        return changes.map { (region, values) -> StrengthTrend(region, values.sum() / values.size, values.size) }
            .sortedWith(compareByDescending<StrengthTrend> { it.change }.thenBy { it.region })
    }

    // MARK: Pomoćno

    private fun interval(size: BucketSize, date: Instant, calendar: StatsCalendar): DateInterval =
        if (size == BucketSize.WEEK) calendar.weekInterval(date) else calendar.monthInterval(date)

    private fun bucketStarts(size: BucketSize, count: Int, now: Instant, calendar: StatsCalendar): List<Instant> {
        if (count <= 0) return emptyList()
        var current = interval(size, now, calendar).start
        val starts = ArrayDeque(listOf(current))
        while (starts.size < count) {
            val previous = if (size == BucketSize.WEEK) calendar.addWeeks(current, -1) else calendar.addMonths(current, -1)
            current = interval(size, previous, calendar).start
            starts.addFirst(current)
        }
        return starts.toList()
    }

    companion object {
        /** Točka napretka jednog izvođenja vježbe. Null kad nema završenih radnih serija. */
        internal fun point(exercise: SessionExercise, date: Instant, formula: SetMetrics.OneRepMaxFormula): ExercisePoint? {
            val sets = exercise.orderedSets.filter { it.isCompleted }.map { it.values }.filter { it.kind == SetKind.WORKING }
            if (sets.isEmpty()) return null
            val type = exercise.inputType
            var bestWeight = 0.0
            var bestReps = 0
            var oneRepMax: Double? = null
            for (set in sets) {
                // Težina i ponavljanja iz iste serije, da redak ne pokaže "85 kg × 7" kad je 85 kg dignuto 5 puta.
                val load = SetMetrics.load(set, type) ?: 0.0
                val reps = set.reps ?: 0
                if (load > bestWeight || (load == bestWeight && reps > bestReps)) {
                    bestWeight = load
                    bestReps = reps
                }
                // Samo pouzdane serije (do 12 ponavljanja do otkaza), s RIR-om iz RPE-a.
                SetMetrics.strengthEstimate(set, type, formula)?.let { oneRepMax = maxOf(oneRepMax ?: 0.0, it) }
            }
            val volume = sets.sumOf { SetMetrics.volume(it, type) }
            return ExercisePoint(date, bestWeight, bestReps, oneRepMax, volume)
        }
    }
}
