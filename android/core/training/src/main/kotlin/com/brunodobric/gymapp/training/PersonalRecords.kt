package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.UserSettings
import java.time.Instant

/** Vrste osobnih rekorda. Glavni rekord snage je procjena 1RM. */
enum class PRKind(val raw: String) {
    /** Procjena 1RM iz pouzdane serije (s RIR-om, do 12 ponavljanja do otkaza). */
    ESTIMATED_ONE_REP_MAX("estimatedOneRepMax"),

    /** Najteža serija s barem toliko ponavljanja (1, 3, 5, 8, 10, 12 ili 15). */
    REP_MAX("repMax"),

    /** Najveća težina s barem jednim ponavljanjem: miljokaz. */
    MAX_WEIGHT("maxWeight"),

    /** Najveća tonaža vježbe u jednom treningu. */
    EXERCISE_VOLUME("exerciseVolume"),

    /** Najviše ponavljanja u seriji (vlastita težina) ili uz istu ili manju pomoć (potpomognute). */
    MAX_REPS("maxReps"),
    LOWEST_ASSISTANCE("lowestAssistance"),
    LONGEST_DURATION("longestDuration"),
    LONGEST_DISTANCE("longestDistance"),
    ;

    companion object {
        /**
         * Tipovi koje korisnik uključuje u Postavkama: "maxWeight" je snaga (1RM, najveća težina, pomoć),
         * "maxReps" ponavljanja (rasponi, trajanje i udaljenost), a "maxVolume" tonaža vježbe u treningu.
         */
        fun kindsFromSettings(raw: List<String>): Set<PRKind> {
            val result = mutableSetOf<PRKind>()
            for (item in raw) {
                when (item) {
                    "maxWeight" -> result += listOf(ESTIMATED_ONE_REP_MAX, MAX_WEIGHT, LOWEST_ASSISTANCE)
                    "maxVolume" -> result += EXERCISE_VOLUME
                    "maxReps" -> result += listOf(REP_MAX, MAX_REPS, LONGEST_DURATION, LONGEST_DISTANCE)
                }
            }
            return result
        }

        /** Tipovi koji se stvarno prate: prazno kad su rekordi isključeni u Postavkama. */
        fun tracked(settings: UserSettings?): Set<PRKind> {
            if (settings == null) return entries.toSet()
            return if (settings.prEnabled) kindsFromSettings(settings.trackedPRKinds) else emptySet()
        }
    }
}

data class PersonalRecord(
    val kind: PRKind,
    /** kg, ponavljanja, sekunde ili metri, ovisno o vrsti. Volumen je kg. */
    val value: Double,
    /** Dosadašnji najbolji rezultat. */
    val previousBest: Double?,
    /** Raspon ponavljanja za [PRKind.REP_MAX]. */
    val reps: Int? = null,
    /** Ide li rekord u sažetak treninga. */
    val showsInSummary: Boolean = true,
)

/**
 * Ranija izvođenja jedne vježbe, sažeta na ono što odlučuje o rekordu. Izvođenja se dodaju od najstarijeg.
 *
 * Vježba nema rekorda dok nema barem [CALIBRATION_SESSIONS] ranijih izvođenja, a nakon pauze od
 * [PAUSE_INTERVAL_SECONDS] ni prva dva izvođenja ne daju rekord.
 */
class RecordHistory() {
    /** Sažete radne serije ([PersonalRecordDetector.condensed]). */
    var sets: List<SetValues> = emptyList()
        private set

    /** Najveća tonaža vježbe u jednom treningu. */
    var bestSessionVolume: Double = 0.0
        private set

    /** Broj izvođenja s barem jednom radnom serijom. */
    var sessionCount: Int = 0
        private set
    var lastDate: Instant? = null
        private set

    /** Koliko još izvođenja nakon povratka s pauze ne daje rekord. */
    private var cooldown = 0

    /** Povijest iz izvođenja od najstarijeg prema najnovijem, bez datuma (pauza se tada ne prepoznaje). */
    constructor(sessions: List<List<SetValues>>, inputType: ExerciseInputType) : this() {
        sessions.forEach { add(it, inputType, null) }
    }

    /** Povijest s nesažetim serijama, za provjeru da sažimanje ne mijenja rekorde. */
    internal constructor(uncondensed: List<SetValues>, bestSessionVolume: Double, sessionCount: Int) : this() {
        sets = uncondensed.filter { it.kind == SetKind.WORKING }
        this.bestSessionVolume = bestSessionVolume
        this.sessionCount = sessionCount
    }

    /** Smije li izvođenje na [date] dati rekord. */
    fun allowsRecords(date: Instant?): Boolean = sessionCount >= CALIBRATION_SESSIONS && cooldown == 0 && !isReturn(date)

    /** Je li izvođenje na [date] prvo nakon pauze. */
    fun isReturn(date: Instant?): Boolean {
        val last = lastDate
        if (date == null || last == null) return false
        return secondsBetween(last, date) >= PAUSE_INTERVAL_SECONDS
    }

    fun add(session: List<SetValues>, inputType: ExerciseInputType, date: Instant?) {
        val working = session.filter { it.kind == SetKind.WORKING }
        if (working.isEmpty()) return
        if (isReturn(date)) cooldown = 1 else if (cooldown > 0) cooldown--
        sessionCount++
        if (date != null) lastDate = maxOf(lastDate ?: date, date)
        val volume = working.sumOf { SetMetrics.volume(it, inputType) }
        bestSessionVolume = maxOf(bestSessionVolume, volume)
        sets = PersonalRecordDetector.condensed(sets + working)
    }

    fun copy(): RecordHistory = RecordHistory().also {
        it.sets = sets
        it.bestSessionVolume = bestSessionVolume
        it.sessionCount = sessionCount
        it.lastDate = lastDate
        it.cooldown = cooldown
    }

    override fun equals(other: Any?): Boolean = other is RecordHistory && sets == other.sets &&
        bestSessionVolume == other.bestSessionVolume && sessionCount == other.sessionCount &&
        lastDate == other.lastDate && cooldown == other.cooldown

    override fun hashCode(): Int = listOf(sets, bestSessionVolume, sessionCount, lastDate, cooldown).hashCode()

    companion object {
        const val CALIBRATION_SESSIONS = 3
        const val PAUSE_INTERVAL_SECONDS = 6 * 7 * 24 * 3600.0
    }
}

/**
 * Prepoznavanje osobnih rekorda (samo radne serije). Rekord vrijedi samo kad je napredak veći od praga,
 * da sitni pomaci (0,5 kg na 140 kg) ne budu rekordi.
 */
object PersonalRecordDetector {
    private const val EPSILON = 1e-9

    /** Rasponi ponavljanja za [PRKind.REP_MAX]. */
    val repRanges = listOf(1, 3, 5, 8, 10, 12, 15)

    /** Najmanji relativni napredak za rekord (1 %). */
    const val MINIMUM_RELATIVE_GAIN = 0.01

    /** Najmanji napredak težine za rekord. */
    const val MINIMUM_LOAD_GAIN_KG = 0.5

    /** Najveća težina ide u sažetak samo ako je procjena 1RM tog treninga barem ovoliki udio najbolje. */
    const val MILESTONE_TOLERANCE = 0.97

    /**
     * @param current završene serije vježbe u ovom treningu
     * @param history ranija izvođenja iste vježbe
     * @param date početak ovog treninga (za pravilo povratka nakon pauze)
     */
    fun records(
        current: List<SetValues>,
        history: RecordHistory,
        inputType: ExerciseInputType,
        kinds: Set<PRKind> = PRKind.entries.toSet(),
        date: Instant? = null,
    ): List<PersonalRecord> {
        val now = current.filter { it.kind == SetKind.WORKING }
        if (now.isEmpty() || !history.allowsRecords(date)) return emptyList()
        val past = history.sets

        val result = mutableListOf<PersonalRecord>()
        fun durations(sets: List<SetValues>) = sets.map { (it.durationSeconds ?: 0).toDouble() }
        fun distances(sets: List<SetValues>) = sets.map { it.distanceMeters ?: 0.0 }
        when (inputType) {
            ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT -> {
                result += oneRepMaxRecord(now, past, inputType)
                result += repMaxRecord(now, past, inputType)
                result += weightRecord(now, past, inputType)
                result += exerciseVolumeRecord(now, history, inputType)
            }
            ExerciseInputType.BODYWEIGHT -> result += bodyweightRepsRecord(now, past)
            ExerciseInputType.ASSISTED -> {
                result += assistanceRecord(now, past)
                result += assistedRepsRecord(now, past)
            }
            ExerciseInputType.DURATION ->
                result += longestRecord(PRKind.LONGEST_DURATION, durations(now), durations(past), 1.0)
            ExerciseInputType.DURATION_DISTANCE -> {
                result += longestRecord(PRKind.LONGEST_DURATION, durations(now), durations(past), 1.0)
                result += longestRecord(PRKind.LONGEST_DISTANCE, distances(now), distances(past), 1.0)
            }
        }
        return result.filter { it.kind in kinds }
    }

    /** Je li [new] dovoljno bolji od [old]: barem 1 % i barem [minimumAbsolute]. */
    fun isSignificant(new: Double, old: Double, minimumAbsolute: Double): Boolean {
        if (old <= 0) return false
        return new >= old * (1 + MINIMUM_RELATIVE_GAIN) - EPSILON && new - old >= minimumAbsolute - EPSILON
    }

    /**
     * Sažima serije na one koje mogu odlučiti o rekordu: Pareto granicu (opterećenje, ponavljanja) za težinu
     * i dodatnu težinu u oba smjera te seriju s najvećom procjenom 1RM, volumenom, trajanjem i udaljenošću.
     * Rekordi sa sažetim serijama isti su kao s punima.
     */
    fun condensed(input: List<SetValues>): List<SetValues> {
        val sets = input.filter { it.kind == SetKind.WORKING }
        if (sets.isEmpty()) return emptyList()
        val keep = sortedSetOf<Int>()
        val loads: List<(SetValues) -> Double> = listOf({ it.weightKg ?: 0.0 }, { it.extraWeightKg ?: 0.0 })
        for (load in loads) {
            keep += frontier(sets, load, heavierIsBetter = true)
            keep += frontier(sets, load, heavierIsBetter = false)
        }
        val measures = mutableListOf<(SetValues) -> Double>()
        ExerciseInputType.entries.forEach { type -> measures += { SetMetrics.volume(it, type) } }
        listOf(ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT).forEach { type ->
            measures += { SetMetrics.strengthEstimate(it, type) ?: 0.0 }
        }
        measures += { (it.durationSeconds ?: 0).toDouble() }
        measures += { it.distanceMeters ?: 0.0 }
        for (measure in measures) {
            sets.indices.maxByOrNull { measure(sets[it]) }?.let { keep += it }
        }
        return keep.map { sets[it] }
    }

    /** Indeksi serija koje nijedna druga ne nadmašuje i opterećenjem i ponavljanjima. */
    private fun frontier(sets: List<SetValues>, load: (SetValues) -> Double, heavierIsBetter: Boolean): List<Int> {
        val byLoad = if (heavierIsBetter) compareByDescending<Int> { load(sets[it]) } else compareBy { load(sets[it]) }
        val order = sets.indices.sortedWith(byLoad.thenByDescending { sets[it].reps ?: 0 })
        val result = mutableListOf<Int>()
        var bestReps = Int.MIN_VALUE
        for (index in order) {
            val reps = sets[index].reps ?: 0
            if (reps > bestReps) {
                result += index
                bestReps = reps
            }
        }
        return result
    }

    private fun bestOneRepMax(sets: List<SetValues>, type: ExerciseInputType): Double =
        sets.mapNotNull { SetMetrics.strengthEstimate(it, type) }.maxOrNull() ?: 0.0

    private fun oneRepMaxRecord(now: List<SetValues>, past: List<SetValues>, type: ExerciseInputType): List<PersonalRecord> {
        val best = bestOneRepMax(now, type)
        val before = bestOneRepMax(past, type)
        if (!isSignificant(best, before, MINIMUM_LOAD_GAIN_KG)) return emptyList()
        return listOf(PersonalRecord(PRKind.ESTIMATED_ONE_REP_MAX, best, before))
    }

    /** Najveći teret među serijama s barem [reps] ponavljanja. */
    private fun heaviest(sets: List<SetValues>, type: ExerciseInputType, reps: Int): Double =
        sets.filter { (it.reps ?: 0) >= reps }.mapNotNull { SetMetrics.load(it, type) }.maxOrNull() ?: 0.0

    /** Jedan rekord po rasponu ponavljanja: najviši raspon u kojem je ovaj trening nadmašio raniji najbolji. */
    private fun repMaxRecord(now: List<SetValues>, past: List<SetValues>, type: ExerciseInputType): List<PersonalRecord> {
        for (reps in repRanges.reversed()) {
            val best = heaviest(now, type, reps)
            val before = heaviest(past, type, reps)
            if (isSignificant(best, before, MINIMUM_LOAD_GAIN_KG)) {
                return listOf(PersonalRecord(PRKind.REP_MAX, best, before, reps = reps))
            }
        }
        return emptyList()
    }

    private fun weightRecord(now: List<SetValues>, past: List<SetValues>, type: ExerciseInputType): List<PersonalRecord> {
        val best = heaviest(now, type, 1)
        val before = heaviest(past, type, 1)
        if (!isSignificant(best, before, MINIMUM_LOAD_GAIN_KG)) return emptyList()
        // Teža serija s manje ponavljanja nije nužno napredak: u sažetak ide samo uz blizu najbolju procjenu 1RM.
        val strength = bestOneRepMax(now, type)
        val bestStrength = bestOneRepMax(past, type)
        val shows = bestStrength <= 0 || strength >= bestStrength * MILESTONE_TOLERANCE
        return listOf(PersonalRecord(PRKind.MAX_WEIGHT, best, before, showsInSummary = shows))
    }

    private fun exerciseVolumeRecord(now: List<SetValues>, history: RecordHistory, type: ExerciseInputType): List<PersonalRecord> {
        val total = now.sumOf { SetMetrics.volume(it, type) }
        val before = history.bestSessionVolume
        if (!isSignificant(total, before, 1.0)) return emptyList()
        return listOf(PersonalRecord(PRKind.EXERCISE_VOLUME, total, before, showsInSummary = false))
    }

    private fun bodyweightRepsRecord(now: List<SetValues>, past: List<SetValues>): List<PersonalRecord> {
        val best = now.maxOfOrNull { it.reps ?: 0 } ?: 0
        val before = past.maxOfOrNull { it.reps ?: 0 } ?: 0
        if (before <= 0 || best <= before) return emptyList()
        return listOf(PersonalRecord(PRKind.MAX_REPS, best.toDouble(), before.toDouble()))
    }

    /** Ponavljanja uz istu ili manju pomoć od ranijih. */
    private fun assistedRepsRecord(now: List<SetValues>, past: List<SetValues>): List<PersonalRecord> {
        var best: Pair<Int, Int>? = null
        for (set in now) {
            val reps = set.reps ?: 0
            val help = set.extraWeightKg ?: 0.0
            if (reps < 1) continue
            val previous = past.filter { (it.extraWeightKg ?: 0.0) <= help + EPSILON }.maxOfOrNull { it.reps ?: 0 } ?: 0
            if (previous > 0 && reps > previous && reps > (best?.first ?: 0)) best = reps to previous
        }
        val (reps, previous) = best ?: return emptyList()
        return listOf(PersonalRecord(PRKind.MAX_REPS, reps.toDouble(), previous.toDouble()))
    }

    private fun assistanceRecord(now: List<SetValues>, past: List<SetValues>): List<PersonalRecord> {
        val best = now.filter { (it.reps ?: 0) >= 1 }.minOfOrNull { it.extraWeightKg ?: 0.0 } ?: return emptyList()
        val before = past.filter { (it.reps ?: 0) >= 1 }.minOfOrNull { it.extraWeightKg ?: 0.0 } ?: return emptyList()
        if (best > before - MINIMUM_LOAD_GAIN_KG + EPSILON) return emptyList()
        return listOf(PersonalRecord(PRKind.LOWEST_ASSISTANCE, best, before))
    }

    private fun longestRecord(kind: PRKind, now: List<Double>, past: List<Double>, minimum: Double): List<PersonalRecord> {
        val best = now.maxOrNull() ?: 0.0
        val before = past.maxOrNull() ?: 0.0
        if (!isSignificant(best, before, minimum)) return emptyList()
        return listOf(PersonalRecord(kind, best, before))
    }
}
