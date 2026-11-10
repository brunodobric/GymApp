package com.brunodobric.gymapp.widgets

import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.units.WeightUnit
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.time.Instant
import java.util.Locale
import java.util.UUID

/**
 * Podaci za widgete (`WidgetSnapshot` na iOS-u): aplikacija ih slaže iz baze ([WidgetSnapshotBuilder]) i sprema
 * u datoteku ([WidgetSnapshotStore]), a widget ih samo čita i crta. Težina je u kg, a jedinica za prikaz ide uz nju.
 * Tekstovi koji ovise o jeziku (vrijednost rekorda) dolaze već oblikovani iz aplikacije.
 */
@Serializable
data class WidgetSnapshot(
    @Serializable(InstantSerializer::class) val generatedAt: Instant,
    /** Naglasna boja iz Postavki (`AccentChoice.raw`). */
    val accent: String = "blue",
    val weightUnit: String = WeightUnit.KILOGRAMS.raw,
    /** Trening u tijeku; dok traje, widget sljedećeg treninga nudi nastavak. */
    val activeWorkout: ActiveWorkout? = null,
    val nextWorkout: NextWorkout? = null,
    val week: Week? = null,
    val bodyWeight: BodyWeight? = null,
    val lastWorkout: LastWorkout? = null,
    val latestRecord: Record? = null,
) {
    val unit: WeightUnit get() = WeightUnit.fromRaw(weightUnit) ?: WeightUnit.KILOGRAMS

    @Serializable
    data class ActiveWorkout(val name: String, @Serializable(InstantSerializer::class) val startedAt: Instant)

    /** Sljedeći trening prvog aktivnog rasporeda, s planom prvih vježbi. */
    @Serializable
    class NextWorkout private constructor(
        val name: String,
        val scheduleName: String?,
        val exerciseCount: Int,
        /** Najviše [MAX_EXERCISES] prvih vježbi. */
        val exercises: List<PlannedExercise>,
    ) {
        /** Vježbe koje nisu u popisu ("+3 vježbe"). */
        val remainingExercises: Int get() = maxOf(0, exerciseCount - exercises.size)

        override fun equals(other: Any?): Boolean = other is NextWorkout && name == other.name &&
            scheduleName == other.scheduleName && exerciseCount == other.exerciseCount && exercises == other.exercises

        override fun hashCode(): Int = listOf(name, scheduleName, exerciseCount, exercises).hashCode()

        companion object {
            const val MAX_EXERCISES = 3

            operator fun invoke(name: String, scheduleName: String?, exerciseCount: Int, exercises: List<PlannedExercise>) =
                NextWorkout(name, scheduleName, exerciseCount, exercises.take(MAX_EXERCISES))
        }
    }

    /** Plan jedne vježbe: broj radnih serija i vrijednosti prve radne serije. */
    @Serializable
    data class PlannedExercise(
        val name: String,
        val workingSets: Int,
        val reps: Int? = null,
        val weightKg: Double? = null,
        val durationSeconds: Int? = null,
    ) {
        /** Kratki opis plana, npr. "4 × 8 · 80 kg", "3 × 12" ili "3 × 0:45". Prazno bez serija. */
        fun summary(unit: WeightUnit, locale: Locale = Locale.getDefault()): String {
            if (workingSets <= 0) return ""
            val parts = mutableListOf<String>()
            parts += when {
                reps != null && reps > 0 -> "$workingSets × $reps"
                durationSeconds != null && durationSeconds > 0 -> "$workingSets × ${DurationInput.format(durationSeconds)}"
                else -> "$workingSets ×"
            }
            if (weightKg != null && weightKg > 0) parts += WeightFormatter(unit, locale).string(weightKg)
            return parts.joinToString(" · ")
        }
    }

    /** Vrsta treninga za ikonu. */
    @Serializable
    enum class Mix {
        @SerialName("strength") STRENGTH,
        @SerialName("cardio") CARDIO,
        @SerialName("mixed") MIXED,
    }

    @Serializable
    class LastWorkout private constructor(
        val name: String,
        @Serializable(InstantSerializer::class) val startedAt: Instant,
        val durationSeconds: Int?,
        val mix: Mix,
        val hardSets: Int,
        /** Najviše dva istaknuta rekorda, s vrijednošću oblikovanom u aplikaciji. */
        val highlights: List<Highlight>,
    ) {
        override fun equals(other: Any?): Boolean = other is LastWorkout && name == other.name &&
            startedAt == other.startedAt && durationSeconds == other.durationSeconds && mix == other.mix &&
            hardSets == other.hardSets && highlights == other.highlights

        override fun hashCode(): Int = listOf(name, startedAt, durationSeconds, mix, hardSets, highlights).hashCode()

        companion object {
            operator fun invoke(
                name: String,
                startedAt: Instant,
                durationSeconds: Int?,
                mix: Mix,
                hardSets: Int,
                highlights: List<Highlight>,
            ) = LastWorkout(name, startedAt, durationSeconds, mix, hardSets, highlights.take(2))
        }
    }

    @Serializable
    data class Highlight(val exercise: String, val value: String)

    /** Najnoviji osobni rekord (najznačajniji iz zadnjeg treninga s rekordom). */
    @Serializable
    data class Record(
        val exercise: String,
        val value: String,
        @Serializable(InstantSerializer::class) val date: Instant,
        /** Trening u kojem je rekord postavljen (dodir na widget ga otvara). */
        val sessionId: String? = null,
    ) {
        val session: UUID? get() = sessionId?.let { runCatching { UUID.fromString(it) }.getOrNull() }
    }

    /** Tjelesna težina: zadnja vrijednost, promjena u 30 dana i vrijednosti za krivulju. */
    @Serializable
    class BodyWeight private constructor(
        val latestKg: Double,
        @Serializable(InstantSerializer::class) val date: Instant,
        val changeKg: Double?,
        /** Vrijednosti (kg) zadnjih mjerenja, od najstarije, najviše [MAX_POINTS]. */
        val points: List<Double>,
    ) {
        /** Točke krivulje između 0 (najniža) i 1 (najviša). Ravna krivulja je na sredini; manje od dvije točke nema krivulje. */
        val normalizedPoints: List<Double>
            get() {
                val values = points.filter { it.isFinite() }
                if (values.size < 2) return emptyList()
                val low = values.min()
                val high = values.max()
                if (high - low <= 0.000_1) return values.map { 0.5 }
                return values.map { (it - low) / (high - low) }
            }

        override fun equals(other: Any?): Boolean = other is BodyWeight && latestKg == other.latestKg &&
            date == other.date && changeKg == other.changeKg && points == other.points

        override fun hashCode(): Int = listOf(latestKg, date, changeKg, points).hashCode()

        companion object {
            const val MAX_POINTS = 30

            operator fun invoke(latestKg: Double, date: Instant, changeKg: Double?, points: List<Double>) =
                BodyWeight(latestKg, date, changeKg, points.takeLast(MAX_POINTS))
        }
    }

    /** Tekući tjedan kao na kartici Ovaj tjedan (`WeekProgress`). */
    @Serializable
    data class Week(
        @Serializable(InstantSerializer::class) val start: Instant,
        val days: List<Day>,
        val sessions: Int,
        val goal: Int?,
        val streakWeeks: Int,
        val hardSets: Int = 0,
        val cardioSeconds: Int = 0,
        val totalSeconds: Int = 0,
    ) {
        @Serializable
        data class Day(
            @Serializable(InstantSerializer::class) val date: Instant,
            val strength: Boolean = false,
            val cardio: Boolean = false,
        ) {
            val isTrained: Boolean get() = strength || cardio

            val mix: Mix?
                get() = when {
                    strength && cardio -> Mix.MIXED
                    strength -> Mix.STRENGTH
                    cardio -> Mix.CARDIO
                    else -> null
                }
        }

        /** Udio cilja (0 do 1); null bez cilja. */
        val goalFraction: Double? get() = goal?.takeIf { it > 0 }?.let { minOf(sessions.toDouble() / it, 1.0) }

        /** Koliko treninga treba da se tjedan broji u niz (bez cilja: jedan). */
        internal val weeklyTarget: Int get() = maxOf(goal ?: 1, 1)

        /**
         * Tjedan kakav je u trenutku [now]. Snimka je složena ranije, pa widget koji ostane do idućeg tjedna mora
         * pokazati prazan tjedan: niz se nastavlja samo ako je upravo završeni tjedan ispunio cilj, a prazan
         * tjedan između prekida ga.
         */
        fun current(now: Instant, calendar: StatsCalendar = StatsCalendar.system()): Week {
            val weekStart = calendar.weekInterval(now).start
            if (weekStart <= start || calendar.date(weekStart) == calendar.date(start)) return this
            val isNextWeek = calendar.date(calendar.addWeeks(weekStart, -1)) == calendar.date(start)
            val continues = isNextWeek && sessions >= weeklyTarget
            return empty(weekStart, sessions = 0, goal = goal, streakWeeks = if (continues) streakWeeks else 0, calendar = calendar)
        }

        companion object {
            /** Normalizira cilj: 0 ili manje znači bez cilja. */
            fun of(
                start: Instant,
                days: List<Day>,
                sessions: Int,
                goal: Int?,
                streakWeeks: Int,
                hardSets: Int = 0,
                cardioSeconds: Int = 0,
                totalSeconds: Int = 0,
            ) = Week(start, days, sessions, goal?.takeIf { it > 0 }, streakWeeks, hardSets, cardioSeconds, totalSeconds)

            /** Tjedan s praznim danima od [start]. */
            fun empty(
                start: Instant,
                sessions: Int,
                goal: Int?,
                streakWeeks: Int,
                calendar: StatsCalendar = StatsCalendar.system(),
            ): Week = of(start, (0L until 7).map { Day(calendar.addDays(start, it)) }, sessions, goal, streakWeeks)
        }
    }

    companion object {
        /** Prazna snimka (prije prvog pokretanja aplikacije). */
        val EMPTY = WidgetSnapshot(generatedAt = Instant.EPOCH)

        /** Primjer za pregled widgeta. */
        fun sample(now: Instant = Instant.now(), calendar: StatsCalendar = StatsCalendar.system()): WidgetSnapshot {
            val start = calendar.weekInterval(now).start
            val empty = Week.empty(start, sessions = 2, goal = 3, streakWeeks = 3, calendar = calendar)
            val days = empty.days.mapIndexed { index, day ->
                day.copy(strength = index == 0 || index == 3, cardio = index == 2)
            }
            val yesterday = now.minusSeconds(86_400)
            return WidgetSnapshot(
                generatedAt = now,
                nextWorkout = NextWorkout(
                    "Push", "Push / Pull / Legs", 6,
                    listOf(
                        PlannedExercise("Bench press", 4, reps = 8, weightKg = 80.0),
                        PlannedExercise("Military press", 3, reps = 10, weightKg = 45.0),
                        PlannedExercise("Dips", 3, reps = 12),
                    ),
                ),
                week = empty.copy(days = days, hardSets = 38, cardioSeconds = 2_700, totalSeconds = 7_800),
                bodyWeight = BodyWeight(82.4, now, -0.6, listOf(83.2, 83.0, 83.1, 82.8, 82.9, 82.6, 82.7, 82.4)),
                lastWorkout = LastWorkout("Legs", yesterday, 3_840, Mix.MIXED, 18, listOf(Highlight("Squat", "120 kg × 5"))),
                latestRecord = Record("Squat", "120 kg × 5", yesterday),
            )
        }
    }
}

/** Datumi u widgetu: "danas", "prije N dana" i ponoći za osvježavanje. */
object WidgetDates {
    /** Broj kalendarskih dana od [date] do [now] (0 = danas, 1 = jučer). Budući datum daje 0. */
    fun daysAgo(date: Instant, now: Instant, calendar: StatsCalendar = StatsCalendar.system()): Int {
        val days = java.time.temporal.ChronoUnit.DAYS.between(calendar.date(date), calendar.date(now))
        return maxOf(0, days.toInt())
    }

    /** Početak idućeg dana nakon [now] (widget se tada osvježava: danas, tjedan i "prije N dana" se mijenjaju). */
    fun nextMidnight(after: Instant, calendar: StatsCalendar = StatsCalendar.system()): Instant =
        calendar.startOfDay(calendar.date(after).plusDays(1))
}

/** Instant kao ISO 8601 tekst: čita se natrag bez gubitka, pa ista snimka nije promjena. */
internal object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
    override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
}
