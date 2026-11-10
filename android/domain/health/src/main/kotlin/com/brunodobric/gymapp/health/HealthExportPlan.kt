package com.brunodobric.gymapp.health

import com.brunodobric.gymapp.model.BodyMeasurement
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.MeasurementSource
import com.brunodobric.gymapp.model.Session
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** Težina koja ide u Health Connect kao `WeightRecord`; [id] je id mjerenja i `clientRecordId` zapisa. */
data class HealthWeightExport(val id: UUID, val kilograms: Double, val time: Instant) {
    val fingerprint: String get() = "${time.toEpochMilli()}|$kilograms"
}

/** Otisak sadržaja treninga: kad se promijeni (ime, vrijeme, dijelovi), zapis se upisuje ponovno. */
val HealthWorkoutExport.fingerprint: String
    get() = buildString {
        append(name.hashCode())
        for (segment in segments) append("|${segment.activity.name}:${segment.start.toEpochMilli()}-${segment.end.toEpochMilli()}")
    }

/**
 * Što je aplikacija već upisala u Health Connect: id zapisa i otisak sadržaja. Čuva se samo na uređaju (ne ide u
 * sigurnosnu kopiju ni sinkronizaciju), pa nova instalacija prvim izvozom upisuje iste zapise preko `clientRecordId`.
 */
data class HealthLedger(val workouts: Map<UUID, String> = emptyMap(), val weights: Map<UUID, String> = emptyMap()) {
    /** Redak po zapisu: vrsta, id i otisak odvojeni tabulatorom. */
    fun encode(): String = buildString {
        workouts.toSortedMap().forEach { (id, print) -> append("w\t$id\t$print\n") }
        weights.toSortedMap().forEach { (id, print) -> append("m\t$id\t$print\n") }
    }

    companion object {
        /** Neispravni retci se preskaču: najgore se zapis upiše još jednom. */
        fun decode(text: String): HealthLedger {
            val workouts = mutableMapOf<UUID, String>()
            val weights = mutableMapOf<UUID, String>()
            for (line in text.lineSequence()) {
                val parts = line.split('\t')
                if (parts.size != 3) continue
                val id = runCatching { UUID.fromString(parts[1]) }.getOrNull() ?: continue
                when (parts[0]) {
                    "w" -> workouts[id] = parts[2]
                    "m" -> weights[id] = parts[2]
                }
            }
            return HealthLedger(workouts, weights)
        }
    }
}

/** Promjene za Health Connect: što upisati, što obrisati i kako izgleda zapis nakon uspjeha. */
data class HealthExportPlan(
    val workouts: List<HealthWorkoutExport>,
    val weights: List<HealthWeightExport>,
    val deletedWorkouts: List<UUID>,
    val deletedWeights: List<UUID>,
    val ledger: HealthLedger,
) {
    val isEmpty: Boolean get() = workouts.isEmpty() && weights.isEmpty() && deletedWorkouts.isEmpty() && deletedWeights.isEmpty()
}

/**
 * Usklađuje bazu s onim što je već u Health Connectu. Novi trening ili težina ide u Health Connect ako je unutar
 * prozora prvog izvoza ([HealthImportWindow]), a već upisani zapis prati izmjene i brisanje u aplikaciji i kad je stariji.
 * Težine iz Zdravlja (kopija s iPhonea) se ne vraćaju natrag.
 */
object HealthExportPlanner {
    fun plan(
        sessions: List<Session>,
        measurements: List<BodyMeasurement>,
        ledger: HealthLedger,
        isCardio: (String) -> Boolean = { false },
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): HealthExportPlan {
        val workoutStart = HealthImportWindow.start(HealthImportWindow.WORKOUT_DAYS, now, zone)
        val eligible = sessions.mapNotNull { HealthWorkoutExport.make(it, isCardio) }
            .filter { it.sessionId in ledger.workouts || it.end >= workoutStart }
        val workouts = eligible.associateBy { it.sessionId }

        val weightStart = HealthImportWindow.start(HealthImportWindow.BODY_DAYS, now, zone)
        val weights = measurements
            .filter {
                it.kind == BodyMeasurementKind.WEIGHT && it.source == MeasurementSource.MANUAL && it.value > 0 &&
                    (it.id in ledger.weights || it.date >= weightStart)
            }
            .map { HealthWeightExport(it.id, it.value, it.date) }
            .associateBy { it.id }

        return HealthExportPlan(
            workouts = eligible.filter { ledger.workouts[it.sessionId] != it.fingerprint }.sortedBy { it.start },
            weights = weights.values.filter { ledger.weights[it.id] != it.fingerprint }.sortedBy { it.time },
            deletedWorkouts = ledger.workouts.keys.filter { it !in workouts }.sorted(),
            deletedWeights = ledger.weights.keys.filter { it !in weights }.sorted(),
            ledger = HealthLedger(
                workouts.mapValues { it.value.fingerprint },
                weights.mapValues { it.value.fingerprint },
            ),
        )
    }
}
