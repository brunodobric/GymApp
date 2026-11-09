package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.RawValued
import kotlin.math.abs
import kotlin.math.round

// Vrijednosti se u bazi spremaju kao tekst (raw, isti kao rawValue na iOS-u), a modeli ih izlažu preko
// računanih svojstava. Tako se novi slučajevi mogu dodati bez migracije, a kopija je ista na obje platforme.

enum class SetKind(override val raw: String) : RawValued { WORKING("working"), WARM_UP("warmUp") }

enum class WorkoutKind(override val raw: String) : RawValued { STRENGTH("strength"), CARDIO("cardio") }

enum class SessionState(override val raw: String) : RawValued {
    ACTIVE("active"), FINISHED("finished"), DISCARDED("discarded")
}

enum class DeviceRole(override val raw: String) : RawValued { PHONE("phone"), WATCH("watch") }

enum class ScheduleItemKind(override val raw: String) : RawValued { WORKOUT("workout"), REST_DAY("restDay") }

enum class ReminderMode(override val raw: String) : RawValued { FIXED_DAYS("fixedDays"), FLEXIBLE("flexible") }

enum class CycleOverrideKind(override val raw: String) : RawValued {
    SKIP_WORKOUT("skipWorkout"),
    REMOVE_EXERCISE("removeExercise"),
    REPLACE_EXERCISE("replaceExercise"),

    /** Trening iz niza odrađen u ovom ciklusu. Starije verzije ga čitaju kao preskakanje. */
    COMPLETED_WORKOUT("completedWorkout"),
}

enum class BodyMeasurementKind(override val raw: String) : RawValued {
    WEIGHT("weight"), HEIGHT("height"), WAIST("waist"), CHEST("chest"), ARM("arm"), LEG("leg"), CUSTOM("custom")
}

enum class MeasurementSource(override val raw: String) : RawValued { MANUAL("manual"), HEALTH_KIT("healthKit") }

/** Cilj treninga iz onboardinga. */
enum class TrainingGoal(override val raw: String) : RawValued {
    HYPERTROPHY("hypertrophy"), STRENGTH("strength"), RECOMPOSITION("recomposition"), GENERAL_FITNESS("generalFitness")
}

enum class ExperienceLevel(override val raw: String) : RawValued {
    BEGINNER("beginner"), INTERMEDIATE("intermediate"), ADVANCED("advanced")
}

/** Tema aplikacije: prati sustav ili je uvijek svijetla odnosno tamna. */
enum class AppTheme(override val raw: String) : RawValued { SYSTEM("system"), LIGHT("light"), DARK("dark") }

/**
 * Naglasna boja aplikacije. `blue` je zadana Apolon plava. Zelene, crvene i narančaste nema jer znače
 * završenu seriju, brisanje i zagrijavanje: spremljena stara vrijednost čita se kao zadana.
 */
enum class AccentChoice(override val raw: String) : RawValued {
    BLUE("blue"), INDIGO("indigo"), PURPLE("purple"), PINK("pink"), TEAL("teal"), GRAPHITE("graphite")
}

/** Razina statistike: osnovna ili detaljna (Pro). */
enum class StatsDetail(override val raw: String) : RawValued { BASIC("basic"), PRO("pro") }

/** Spol za izračune koji ga trebaju (DOTS bodovi). Neobavezan. */
enum class Sex(override val raw: String) : RawValued { FEMALE("female"), MALE("male") }

enum class EffortScale(override val raw: String) : RawValued { RPE("rpe"), RIR("rir") }

/** RPE se uvijek sprema kao broj od 1 do 10 u koracima od 0,5. RIR je izveden: RIR = 10 − RPE. */
object RPE {
    val range = 1.0..10.0
    const val STEP = 0.5

    fun isValid(value: Double): Boolean {
        if (value !in range) return false
        val steps = value / STEP
        return abs(steps - round(steps)) < 1e-9
    }

    /** Ponavljanja u rezervi za prikaz kad je odabran RIR. */
    fun rirFromRpe(rpe: Double): Double = 10 - rpe

    fun rpeFromRir(rir: Double): Double = 10 - rir
}
