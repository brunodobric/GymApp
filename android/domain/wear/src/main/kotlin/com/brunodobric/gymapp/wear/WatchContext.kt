package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.InstantSerializer
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.UUIDSerializer
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.training.CardioPart
import com.brunodobric.gymapp.training.RestDefaults
import com.brunodobric.gymapp.training.SessionMix
import com.brunodobric.gymapp.training.SetValues
import com.brunodobric.gymapp.training.SmartDefaults
import com.brunodobric.gymapp.units.WeightUnit
import com.brunodobric.gymapp.widgets.WidgetSnapshot
import java.time.Instant
import java.util.UUID
import kotlin.math.roundToInt
import kotlinx.serialization.Serializable

// Zadnje stanje koje mobitel šalje satu (`WatchContextPayload` na iOS-u, specifikacija, odjeljak 6): sljedeći
// treninzi i predlošci s pretpunjenim serijama (smart defaults), jedinica i zadana pauza. Sat ga sprema, pa trening
// može započeti i kad mobitel nije u blizini.

@Serializable
data class PlannedSetPayload(
    @Serializable(SetKindSerializer::class) val kind: SetKind = SetKind.WORKING,
    val weightKg: Double? = null,
    val reps: Int? = null,
    val extraWeightKg: Double? = null,
    val durationSeconds: Int? = null,
    val distanceMeters: Double? = null,
) {
    constructor(values: SetValues) : this(
        values.kind, values.weightKg, values.reps, values.extraWeightKg, values.durationSeconds, values.distanceMeters,
    )

    val values: SetValues get() = SetValues(kind, weightKg, reps, extraWeightKg, durationSeconds, distanceMeters)
}

@Serializable
data class PlannedExercisePayload(
    @Serializable(ExerciseRefSerializer::class) val exercise: ExerciseRef,
    @Serializable(InputTypeSerializer::class) val inputType: ExerciseInputType,
    val restSeconds: Int? = null,
    /** Vježbe s istim brojem čine superset (broj vrijedi samo unutar jednog plana). */
    val supersetGroup: Int? = null,
    val sets: List<PlannedSetPayload> = emptyList(),
    /** Kardio vježba (katalog ili vlastita vježba u kategoriji kardio). */
    val isCardio: Boolean = false,
    /** Završene serije zadnjeg izvođenja, za redak "prošli put" na satu. */
    val previous: List<PlannedSetPayload> = emptyList(),
    /** Složena vježba iz kataloga (zadana pauza, [RestDefaults]). null kad se ne zna. */
    val isCompound: Boolean? = null,
    /** Korak težine vježbe u jedinici prikaza (`WeightStepSettings`). */
    val weightStep: Double? = null,
    val targetRepsMin: Int? = null,
    val targetRepsMax: Int? = null,
    /** Prijedlog veće težine u kg (dvostruka progresija, `SetPlanner`). */
    val loadChangeKg: Double? = null,
    /** Bilješka uz vježbu iz predloška. */
    val notes: String? = null,
)

@Serializable
data class PlannedWorkoutPayload(
    @Serializable(UUIDSerializer::class) val templateId: UUID? = null,
    @Serializable(UUIDSerializer::class) val scheduleId: UUID? = null,
    val name: String,
    /** Naziv rasporeda kad je ovo njegov sljedeći trening. */
    val scheduleName: String? = null,
    @Serializable(WorkoutKindSerializer::class) val kind: WorkoutKind = WorkoutKind.STRENGTH,
    val exercises: List<PlannedExercisePayload> = emptyList(),
) {
    val id: String get() = "${scheduleId ?: "-"}/${templateId ?: name}"

    /** Vrsta treninga iz vježbi, kao `SessionCardio.mix(template)` na mobitelu. */
    val mix: SessionMix get() = mixOf(exercises.map { it.isCardio })

    /**
     * Približno trajanje u minutama, zaokruženo na 5: rad serija (trajanje kardio serije ili 45 s), odmor između
     * serija i minuta za prijelaz na sljedeću vježbu. Vježba bez vlastite pauze odmara prema vrsti ([RestDefaults]).
     * null za trening bez serija.
     */
    fun estimatedMinutes(restDefaults: RestDefaults): Int? {
        var seconds = 0
        var setCount = 0
        exercises.forEachIndexed { index, exercise ->
            if (index > 0) seconds += EXERCISE_CHANGE_SECONDS
            val rest = maxOf(0, exercise.restSeconds ?: restDefaults.seconds(listOf(exercise.isCompound)))
            exercise.sets.forEachIndexed { setIndex, set ->
                seconds += set.durationSeconds?.takeIf { it > 0 } ?: ASSUMED_SET_SECONDS
                if (setIndex < exercise.sets.size - 1) seconds += rest
                setCount++
            }
        }
        if (setCount == 0) return null
        val minutes = seconds / 60.0
        return maxOf(5, (minutes / 5).roundToInt() * 5)
    }

    companion object {
        /** Rad jedne serije bez upisanog trajanja (snaga), u sekundama. */
        const val ASSUMED_SET_SECONDS = 45

        /** Prijelaz na sljedeću vježbu (namještanje sprave), u sekundama. */
        const val EXERCISE_CHANGE_SECONDS = 60
    }
}

/** Vrsta iz oznaka "je li kardio" po vježbi: bez kardija snaga, samo kardio kardio, inače oboje. */
fun mixOf(cardioFlags: List<Boolean>): SessionMix {
    val cardio = cardioFlags.count { it }
    return when {
        cardio == 0 -> SessionMix.STRENGTH
        cardio == cardioFlags.size -> SessionMix.CARDIO
        else -> SessionMix.MIXED
    }
}

@Serializable
data class WatchContextPayload(
    /** Sljedeći trening svakog aktivnog rasporeda. */
    val upcoming: List<PlannedWorkoutPayload> = emptyList(),
    /** Predlošci izvan rasporeda (za trening koji nije na redu). */
    val templates: List<PlannedWorkoutPayload> = emptyList(),
    /** `WeightUnit.raw`. */
    val weightUnit: String = WeightUnit.KILOGRAMS.raw,
    /** Zadana pauza za izolacijske i ostale vježbe. */
    val defaultRestSeconds: Int = 90,
    /** Zadana pauza za složene vježbe. */
    val compoundRestSeconds: Int = 150,
    /** Korisnik je uključio Health Connect: sat mjeri puls i kalorije za trening. */
    val savesToHealth: Boolean = false,
    @Serializable(InstantSerializer::class) val generatedAt: Instant = Instant.EPOCH,
    /** Tekući tjedan za komplikaciju tjednog cilja (isti kao u widgetima na mobitelu). */
    val week: WidgetSnapshot.Week? = null,
    /** Zadnja tjelesna težina u kg, za komplikaciju težine. */
    val bodyWeightKg: Double? = null,
    /** Naglasna boja iz postavki (`AccentChoice.raw`). */
    val accent: String = "blue",
) {
    val unit: WeightUnit get() = WeightUnit.fromRaw(weightUnit) ?: WeightUnit.KILOGRAMS

    /** Zadane pauze s mobitela. */
    val restDefaults: RestDefaults get() = RestDefaults(compoundRestSeconds, defaultRestSeconds)

    private val allPlannedExercises: List<PlannedExercisePayload> get() = (upcoming + templates).flatMap { it.exercises }

    /** Je li vježba složena, prema vježbama u treninzima koje je poslao mobitel. null za nepoznatu vježbu. */
    fun isCompound(exercise: ExerciseRef): Boolean? =
        allPlannedExercises.firstOrNull { it.exercise.key == exercise.key && it.isCompound != null }?.isCompound

    /** Je li vježba kardio, prema vježbama u treninzima koje je poslao mobitel. Nepoznata vježba nije kardio. */
    fun isCardio(exercise: ExerciseRef): Boolean = allPlannedExercises.any { it.exercise.key == exercise.key && it.isCardio }

    /**
     * Vrijednosti iz zadnjeg izvođenja za seriju na danom mjestu (redni broj među serijama iste vrste), po istom
     * pravilu kao "prošli put" na mobitelu ([SmartDefaults]). null kad vježba nije bila odrađena.
     */
    fun previousSet(exercise: ExerciseRef, kind: SetKind, position: Int): SetValues? {
        val previous = allPlannedExercises.firstOrNull { it.exercise.key == exercise.key && it.previous.isNotEmpty() }?.previous
            ?: return null
        return SmartDefaults.defaults(position, kind, previous.map { it.values })
    }

    companion object {
        /** Kad sat još nije dobio ništa od mobitela. */
        val EMPTY = WatchContextPayload()
    }
}

/** Vrsta za sažetak, kao `SessionCardio.mix(session)`: snaga s odrađenim samo kardio vježbama je kardio. */
fun SessionSnapshot.mix(isCardio: (ExerciseRef) -> Boolean): SessionMix = mixOf(doneExercises.map { isCardio(it.exercise) })

/** Zbroj odrađenih serija kardio vježbi, kao `SessionCardio.part`; null kad ih nema. */
fun SessionSnapshot.cardioPart(isCardio: (ExerciseRef) -> Boolean): CardioPart? {
    val cardio = doneExercises.filter { isCardio(it.exercise) }
    if (cardio.isEmpty()) return null
    val sets = cardio.flatMap { it.sets }.filter { it.isCompleted }
    val seconds = sets.sumOf { maxOf(0, it.durationSeconds ?: 0) }
    val distances = sets.mapNotNull { it.distanceMeters }.filter { it > 0 }
    return CardioPart(seconds, if (distances.isEmpty()) null else distances.sum())
}

/** Završene serije bez kardio vježbi (kardio se ne broji u serije, kao na mobitelu). */
fun SessionSnapshot.strengthSetCount(isCardio: (ExerciseRef) -> Boolean): Int =
    visibleExercises.filter { !isCardio(it.exercise) }.sumOf { it.completedSetCount }

/** Odrađene vježbe: nisu izbačene i imaju barem jednu seriju s kvačicom. */
private val SessionSnapshot.doneExercises: List<ExerciseSnapshot>
    get() = visibleExercises.filter { exercise -> exercise.sets.any { it.isCompleted } }
