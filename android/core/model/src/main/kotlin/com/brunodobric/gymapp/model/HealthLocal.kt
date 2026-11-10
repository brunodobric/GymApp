package com.brunodobric.gymapp.model

import java.time.Instant
import java.util.UUID

/**
 * Kardio trening iz Health Connecta (druga aplikacija ili sat), u lokalnoj bazi zdravstvenih podataka
 * (`HealthWorkout` na iOS-u). Ne ide u korisničku bazu, sigurnosnu kopiju ni sinkronizaciju.
 */
data class HealthWorkout(
    val id: UUID,
    /** Id zapisa u Health Connectu (sprječava dvostruki uvoz). */
    val recordId: String,
    val name: String,
    val startedAt: Instant,
    val endedAt: Instant,
    val activeEnergyKilocalories: Double? = null,
    val distanceMeters: Double? = null,
    val averageHeartRate: Double? = null,
) {
    /**
     * Trening za prikaz uz treninge iz korisničke baze (povijest). Ne umeće se ni u jednu bazu, a ima isti `id`,
     * pa ga ekrani prepoznaju po [Session.isImportedFromWorkoutsApp].
     */
    fun makeSession(): Session {
        val session = Session(name, WorkoutKind.CARDIO, startedAt)
        session.id = id
        session.endedAt = endedAt
        session.lastActivityAt = endedAt
        session.state = SessionState.FINISHED
        session.isImportedFromWorkoutsApp = true
        session.activeEnergyKilocalories = activeEnergyKilocalories
        session.distanceMeters = distanceMeters
        session.averageHeartRate = averageHeartRate
        return session
    }
}

/** Težina ili visina iz Health Connecta (`HealthMeasurement` na iOS-u). kg za težinu, cm za visinu. */
data class HealthMeasurement(
    val id: UUID,
    val recordId: String,
    val kind: BodyMeasurementKind,
    val value: Double,
    val date: Instant,
) {
    /** Mjerenje za prikaz uz ručna mjerenja. Ne umeće se ni u jednu bazu. */
    fun makeMeasurement(): BodyMeasurement {
        val measurement = BodyMeasurement(kind, value, date, MeasurementSource.HEALTH_KIT)
        measurement.id = id
        return measurement
    }
}

/**
 * Lokalni podaci iz Health Connecta za prikaz (`HealthLocalStore` na iOS-u). [GymStore.health] je zadano prazan;
 * aplikacija postavlja izvor koji čita datoteku na uređaju, a [GymStore.healthChanged] javlja promjenu ekranima.
 */
interface HealthLocalSource {
    val workouts: List<HealthWorkout>
    val measurements: List<HealthMeasurement>

    /** Briše uvezeni trening iz lokalne baze (u Health Connectu ostaje). */
    fun deleteWorkout(id: UUID)

    /** Briše mjerenje iz lokalne baze (u Health Connectu ostaje). */
    fun deleteMeasurement(id: UUID)

    object None : HealthLocalSource {
        override val workouts: List<HealthWorkout> = emptyList()
        override val measurements: List<HealthMeasurement> = emptyList()
        override fun deleteWorkout(id: UUID) = Unit
        override fun deleteMeasurement(id: UUID) = Unit
    }
}

/** Vlastiti treninzi i treninzi iz Health Connecta zajedno, od najnovijeg. */
fun mergedSessions(own: List<Session>, health: List<HealthWorkout>): List<Session> =
    (own + health.map { it.makeSession() }).sortedByDescending { it.startedAt }
