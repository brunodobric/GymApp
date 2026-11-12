package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.units.WeightUnit
import java.util.UUID

/**
 * Korak težine: razmak između dviju susjednih težina na kotačiću i na gumbima + i −.
 *
 * Korak ovisi o opremi vježbe, a vježba može imati vlastiti korak. Korak je u jedinici prikaza (kg ili lbs),
 * pa kilogrami i funte imaju odvojene postavke. Same težine i dalje se spremaju u kilogramima.
 */
class WeightStepSettings(equipmentRaw: String = "", exercisesRaw: String = "") {
    data class Key(val id: String, val unit: WeightUnit)

    /** Korak po opremi, ključ je `Equipment.raw`. */
    private val equipment: MutableMap<Key, Double> = decode(equipmentRaw)

    /** Korak po vježbi, ključ je `ExerciseRef.key`. */
    private val exercises: MutableMap<Key, Double> = decode(exercisesRaw)

    /** Korak opreme: postavka korisnika ili zadani korak. */
    fun step(equipment: Equipment?, unit: WeightUnit): Double {
        val kind = equipment ?: Equipment.OTHER
        return this.equipment[Key(kind.raw, unit)] ?: defaultStep(kind, unit)
    }

    /** Vlastiti korak vježbe, null kad vježba prati korak opreme. */
    fun override(exerciseKey: String, unit: WeightUnit): Double? = exercises[Key(exerciseKey, unit)]

    /** Korak koji vrijedi za vježbu: njezin vlastiti, inače korak opreme. */
    fun step(exerciseKey: String, equipment: Equipment?, unit: WeightUnit): Double =
        override(exerciseKey, unit) ?: step(equipment, unit)

    /** Postavlja korak opreme. Zadani korak (ili null) briše postavku. */
    fun setStep(step: Double?, equipment: Equipment, unit: WeightUnit) {
        val key = Key(equipment.raw, unit)
        if (step != null && step > 0 && step != defaultStep(equipment, unit)) this.equipment[key] = step else this.equipment.remove(key)
    }

    /** Postavlja vlastiti korak vježbe. Null vraća vježbu na korak opreme. */
    fun setOverride(step: Double?, exerciseKey: String, unit: WeightUnit) {
        if (exerciseKey.isEmpty()) return
        val key = Key(exerciseKey, unit)
        if (step != null && step > 0) exercises[key] = step else exercises.remove(key)
    }

    /** Vježbe s vlastitim korakom u jedinici [unit]: ključ vježbe i korak. */
    fun overrides(unit: WeightUnit): Map<String, Double> =
        exercises.filterKeys { it.unit == unit }.mapKeys { it.key.id }

    /** Ima li ijedna oprema korak različit od zadanog u jedinici [unit] ("Vrati zadane korake"). */
    fun hasEquipmentSteps(unit: WeightUnit): Boolean = equipment.keys.any { it.unit == unit }

    val equipmentRaw: String get() = encode(equipment)
    val exercisesRaw: String get() = encode(exercises)

    override fun equals(other: Any?): Boolean =
        other is WeightStepSettings && equipment == other.equipment && exercises == other.exercises

    override fun hashCode(): Int = 31 * equipment.hashCode() + exercises.hashCode()

    companion object {
        /** Koraci koji se mogu odabrati u postavkama i na vježbi. */
        fun choices(unit: WeightUnit): List<Double> = when (unit) {
            WeightUnit.KILOGRAMS -> listOf(0.5, 1.0, 1.25, 2.0, 2.5, 4.0, 5.0, 10.0)
            WeightUnit.POUNDS -> listOf(1.0, 2.5, 5.0, 10.0, 15.0, 20.0)
        }

        /** Zadani korak opreme: bučice po 2 kg, sprave i sajla po 5 kg, girje po 4 kg, ostalo 2,5 kg. */
        fun defaultStep(equipment: Equipment?, unit: WeightUnit): Double {
            val kind = equipment ?: Equipment.OTHER
            return when (unit) {
                WeightUnit.KILOGRAMS -> when (kind) {
                    Equipment.DUMBBELL -> 2.0
                    Equipment.CABLE, Equipment.MACHINE -> 5.0
                    Equipment.KETTLEBELL -> 4.0
                    else -> 2.5
                }
                WeightUnit.POUNDS -> when (kind) {
                    Equipment.CABLE, Equipment.MACHINE -> 10.0
                    else -> 5.0
                }
            }
        }

        // Zapis je tekst, isti kao na iOS-u: "dumbbell@kilograms=2.0,machine@pounds=10.0".
        internal fun encode(values: Map<Key, Double>): String =
            values.map { (key, value) -> "${key.id}@${key.unit.raw}=${swiftDoubleString(value)}" }
                .sorted()
                .joinToString(",")

        internal fun decode(raw: String): MutableMap<Key, Double> {
            val result = LinkedHashMap<Key, Double>()
            for (entry in raw.split(",")) {
                val parts = entry.split("=", limit = 2)
                if (parts.size != 2) continue
                val value = parts[1].toDoubleOrNull()?.takeIf { it > 0 } ?: continue
                val target = parts[0].split("@").filter { it.isNotEmpty() }
                if (target.size != 2) continue
                val unit = WeightUnit.fromRaw(target[1]) ?: continue
                result[Key(target[0], unit)] = value
            }
            return result
        }

        /** Oprema vježbe iz kataloga ili vlastite vježbe. Null kad vježba nije nađena ili nema opremu. */
        fun equipment(exercise: ExerciseRef, catalog: ExerciseCatalog?, custom: List<CustomExercise>): Equipment? = when {
            exercise.catalogId != null -> catalog?.exercise(exercise.catalogId)?.equipment
            exercise.customExerciseId != null -> custom.firstOrNull { it.id == exercise.customExerciseId }?.equipment
            else -> null
        }

        /** Korak težine po vježbi za mjesta bez ekrana (obavijest u tijeku). Sve se čita jednom. */
        fun resolver(settings: UserSettings?, catalog: ExerciseCatalog?, custom: List<CustomExercise>): (ExerciseRef) -> Double {
            val steps = settings?.weightSteps ?: WeightStepSettings()
            val unit = settings?.weightUnit ?: WeightUnit.KILOGRAMS
            val customEquipment: Map<UUID, Equipment?> = custom.reversed().associate { it.id to it.equipment }
            return { exercise ->
                val equipment = when {
                    exercise.catalogId != null -> catalog?.exercise(exercise.catalogId)?.equipment
                    exercise.customExerciseId != null -> customEquipment[exercise.customExerciseId]
                    else -> null
                }
                steps.step(exercise.key, equipment, unit)
            }
        }
    }
}

/** Koraci težine po opremi i po vježbi. */
var UserSettings.weightSteps: WeightStepSettings
    get() = WeightStepSettings(equipmentWeightStepsRaw, exerciseWeightStepsRaw)
    set(value) {
        equipmentWeightStepsRaw = value.equipmentRaw
        exerciseWeightStepsRaw = value.exercisesRaw
    }

/** Korak težine za vježbu u jedinici korisnika. */
fun UserSettings.weightStep(exercise: ExerciseRef, catalog: ExerciseCatalog?, custom: List<CustomExercise>): Double =
    weightSteps.step(exercise.key, WeightStepSettings.equipment(exercise, catalog, custom), weightUnit)
