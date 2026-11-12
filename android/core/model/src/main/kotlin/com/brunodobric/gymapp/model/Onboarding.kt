package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightUnit
import java.time.Instant

/** Odgovori iz onboardinga. Sve osim jedinica i odgovora o zdravstvenim podacima je neobavezno. */
data class OnboardingAnswers(
    var goal: TrainingGoal? = null,
    /** Spol, za DOTS bodove i tijelo na prikazu mišića. */
    var sex: Sex? = null,
    var unit: WeightUnit = WeightUnit.KILOGRAMS,
    /** Visina u centimetrima. */
    var heightCm: Double? = null,
    /** Težina onako kako je unesena, u odabranoj jedinici. */
    var weight: Double? = null,
    var wantsHealthKit: Boolean = false,
    var experience: ExperienceLevel? = null,
    var equipment: List<Equipment> = emptyList(),
    var daysPerWeek: Int? = null,
) {
    /** Težina u kg ili null ako nije unesena ili je izvan razumnog raspona. */
    val weightKg: Double?
        get() = weight?.let { WeightConversion.kilograms(it, unit) }?.takeIf { it in WEIGHT_RANGE_KG }

    val validHeightCm: Double? get() = heightCm?.takeIf { it in HEIGHT_RANGE_CM }

    val validDaysPerWeek: Int? get() = daysPerWeek?.takeIf { it in DAYS_PER_WEEK_RANGE }

    companion object {
        /**
         * Odgovori iz postavki, kad se profil ispunjava naknadno (kartica na Početnoj). Težina i visina ostaju
         * prazne jer se upisuju kao nova mjerenja, a ne mijenjaju postojeća.
         */
        fun from(settings: UserSettings) = OnboardingAnswers(
            goal = settings.goal,
            sex = settings.sex,
            unit = settings.weightUnit,
            wantsHealthKit = settings.wantsHealthKit,
            experience = settings.experience,
            equipment = settings.equipment,
            daysPerWeek = settings.trainingDaysPerWeek,
        )

        val HEIGHT_RANGE_CM = 100.0..250.0
        val WEIGHT_RANGE_KG = 20.0..400.0
        val DAYS_PER_WEEK_RANGE = 1..7
    }
}

/** Primjenjuje odgovore iz onboardinga na postavke i tjelesna mjerenja. */
class OnboardingApplier(private val store: GymStore) {

    fun apply(answers: OnboardingAnswers, now: Instant = Instant.now()) {
        val settings = store.settings()
        settings.goal = answers.goal
        settings.weightUnit = answers.unit
        settings.wantsHealthKit = answers.wantsHealthKit
        settings.experience = answers.experience
        settings.equipment = answers.equipment
        settings.trainingDaysPerWeek = answers.validDaysPerWeek
        answers.sex?.let { sex ->
            settings.sex = sex
            settings.bodyMapFemale = sex == Sex.FEMALE
        }
        settings.onboardingCompleted = true
        answers.weightKg?.let { store.insert(BodyMeasurement(BodyMeasurementKind.WEIGHT, it, now)) }
        answers.validHeightCm?.let { store.insert(BodyMeasurement(BodyMeasurementKind.HEIGHT, it, now)) }
        store.save()
    }

    /**
     * "Preskoči" (i zatvaranje lista): sprema se samo da je onboarding obavljen i odgovor o zdravstvenim podacima,
     * jer je dozvola možda već dana dodirom na "Poveži".
     */
    fun skip(wantsHealthKit: Boolean = false) {
        val settings = store.settings()
        settings.wantsHealthKit = wantsHealthKit
        settings.onboardingCompleted = true
        store.save()
    }
}

/** Brzi odabir opreme u onboardingu i profilu: "Teretana" odabire sve jednim dodirom. */
enum class EquipmentPreset(val raw: String) {
    /** Teretana: sva oprema. */
    GYM("gym"),

    /** Kućna teretana: šipka sa stalkom i klupom, bučice, trake i šipka za zgibove (`OTHER`). */
    HOME_GYM("homeGym"),

    /** Bučice i trake. */
    DUMBBELLS("dumbbells"),

    /** Bez opreme: samo vlastita težina. */
    BODYWEIGHT_ONLY("bodyweightOnly"),
    ;

    val equipment: List<Equipment>
        get() = when (this) {
            GYM -> Equipment.entries
            HOME_GYM -> listOf(Equipment.BARBELL, Equipment.DUMBBELL, Equipment.BODYWEIGHT, Equipment.BANDS, Equipment.OTHER)
            DUMBBELLS -> listOf(Equipment.DUMBBELL, Equipment.BODYWEIGHT, Equipment.BANDS)
            BODYWEIGHT_ONLY -> listOf(Equipment.BODYWEIGHT)
        }

    companion object {
        /** Preset koji odgovara točno toj opremi, ili null za vlastiti odabir. */
        fun matching(equipment: List<Equipment>): EquipmentPreset? =
            entries.firstOrNull { it.equipment.toSet() == equipment.toSet() }
    }
}
