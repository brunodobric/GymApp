package com.brunodobric.gymapp.health

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.WorkoutKind
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Vrsta aktivnosti u Health Connectu (`HealthActivity` na iOS-u). Aplikacija je pretvara u
 * `ExerciseSessionRecord.EXERCISE_TYPE_*` i `ExerciseSegment.EXERCISE_SEGMENT_TYPE_*`.
 */
enum class HealthActivity {
    STRENGTH_TRAINING,
    MIXED_CARDIO,
    ;

    val isCardio: Boolean get() = this == MIXED_CARDIO

    companion object {
        /** Vrsta pod kojom se trening iz aplikacije sprema. */
        fun forExport(kind: WorkoutKind): HealthActivity = when (kind) {
            WorkoutKind.STRENGTH -> STRENGTH_TRAINING
            WorkoutKind.CARDIO -> MIXED_CARDIO
        }
    }
}

/** Dio treninga: snaga ili kardio, od [start] do [end]. */
data class HealthWorkoutSegment(val activity: HealthActivity, val start: Instant, val end: Instant) {
    val duration: Duration get() = Duration.between(start, end)
}

/**
 * Trening koji treba spremiti u Health Connect (`HealthWorkoutExport` na iOS-u). Na iOS-u je svaki dio zaseban
 * trening u Zdravlju; u Health Connectu je to jedan `ExerciseSessionRecord` s dijelovima (`ExerciseSegment`),
 * a podjela vremena je ista.
 */
data class HealthWorkoutExport(
    val sessionId: java.util.UUID,
    val name: String,
    /** Dijelovi redom po vremenu; uvijek barem jedan. */
    val segments: List<HealthWorkoutSegment>,
) {
    /** Vrsta glavnog dijela. */
    val activity: HealthActivity get() = segments[primaryIndex].activity
    val start: Instant get() = segments.first().start
    val end: Instant get() = segments.last().end

    /** Glavni dio: najdulji dio snage, a bez snage najdulji dio. */
    val primaryIndex: Int
        get() {
            val strength = segments.indices.filter { !segments[it].activity.isCardio }
            val candidates = strength.ifEmpty { segments.indices.toList() }
            return candidates.maxByOrNull { segments[it].duration } ?: 0
        }

    companion object {
        /** Kardio blokovi razmaknuti najviše ovoliko su jedan kardio dio (prijelaz sa sprave na spravu). */
        val CARDIO_JOIN_GAP: Duration = Duration.ofMinutes(5)

        /** Kraći dio od ovoga ne ide kao zaseban dio. */
        val MINIMUM_SEGMENT: Duration = Duration.ofMinutes(1)

        /**
         * Spremaju se samo završeni treninzi koje je vodio telefon, koji nisu već u Zdravlju na iPhoneu (kopija s
         * iOS-a) i nisu iz njega uvezeni. Kardio vježbe (`isCardio` po ključu vježbe) postaju kardio dijelovi u vremenu
         * svojih serija (kvačica minus trajanje serije), a snaga ostaje u razmacima između njih.
         */
        fun make(session: Session, isCardio: (String) -> Boolean = { false }): HealthWorkoutExport? {
            val end = session.endedAt ?: return null
            if (session.state != SessionState.FINISHED || session.controllingDevice != DeviceRole.PHONE ||
                session.healthRecordedByWatch || session.healthKitWorkoutId != null ||
                session.isImportedFromWorkoutsApp || end <= session.startedAt
            ) {
                return null
            }
            return HealthWorkoutExport(session.id, session.name, segments(session, session.startedAt, end, isCardio))
        }

        internal fun segments(session: Session, start: Instant, end: Instant, isCardio: (String) -> Boolean): List<HealthWorkoutSegment> {
            val whole = listOf(HealthWorkoutSegment(HealthActivity.forExport(session.kind), start, end))
            if (session.kind != WorkoutKind.STRENGTH) return whole

            val cardio = mutableListOf<Pair<Instant, Instant>>()
            val strengthSets = mutableListOf<Instant>()
            for (exercise in session.orderedExercises.filter { !it.isRemoved }) {
                val done = exercise.orderedSets.filter { it.isCompleted }
                if (!isCardio(exercise.exerciseKey)) {
                    strengthSets += done.mapNotNull { it.completedAt }
                    continue
                }
                for (set in done) {
                    val finished = set.completedAt ?: continue
                    val seconds = set.durationSeconds?.takeIf { it > 0 } ?: continue
                    val from = maxOf(start, finished.minusSeconds(seconds.toLong()))
                    val to = minOf(end, finished)
                    if (to > from) cardio += from to to
                }
            }
            if (cardio.isEmpty()) return whole
            if (strengthSets.isEmpty()) return listOf(HealthWorkoutSegment(HealthActivity.MIXED_CARDIO, start, end))

            // Kardio blokovi: bliski se spajaju, a blok blizu početka ili kraja treninga dobiva i taj rub.
            val blocks = mutableListOf<Pair<Instant, Instant>>()
            for (interval in cardio.sortedBy { it.first }) {
                val last = blocks.lastOrNull()
                if (last != null && Duration.between(last.second, interval.first) <= CARDIO_JOIN_GAP) {
                    blocks[blocks.lastIndex] = last.first to maxOf(last.second, interval.second)
                } else {
                    blocks += interval
                }
            }
            if (Duration.between(start, blocks.first().first) <= CARDIO_JOIN_GAP) blocks[0] = start to blocks[0].second
            if (Duration.between(blocks.last().second, end) <= CARDIO_JOIN_GAP) blocks[blocks.lastIndex] = blocks.last().first to end

            // Snaga je u razmacima između kardio blokova, ako je u razmaku označena barem jedna serija snage.
            val result = mutableListOf<HealthWorkoutSegment>()
            var cursor = start
            fun addStrength(limit: Instant) {
                if (Duration.between(cursor, limit) < MINIMUM_SEGMENT) return
                if (strengthSets.none { it > cursor && it <= limit }) return
                result += HealthWorkoutSegment(HealthActivity.STRENGTH_TRAINING, cursor, limit)
            }
            for ((blockStart, blockEnd) in blocks) {
                addStrength(blockStart)
                if (Duration.between(blockStart, blockEnd) >= MINIMUM_SEGMENT) {
                    result += HealthWorkoutSegment(HealthActivity.MIXED_CARDIO, blockStart, blockEnd)
                }
                cursor = maxOf(cursor, blockEnd)
            }
            addStrength(end)
            return result.ifEmpty { whole }
        }
    }
}

/** Koliko daleko unatrag ide prvi izvoz nakon povezivanja (`HealthImportWindow` na iOS-u). */
object HealthImportWindow {
    const val WORKOUT_DAYS = 30
    const val BODY_DAYS = 365

    fun start(days: Int, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant =
        LocalDate.ofInstant(now, zone).minusDays(days.toLong()).atStartOfDay(zone).toInstant()
}
