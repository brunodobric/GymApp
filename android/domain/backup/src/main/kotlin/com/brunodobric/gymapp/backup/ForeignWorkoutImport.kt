package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.CustomExercise
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.WorkoutKind
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * Uvoz treninga iz CSV izvoza druge aplikacije ([ForeignWorkoutsCsv]): prvo pregled, pa uvoz.
 *
 * * Svaki trening dobiva stabilan UUID iz zaglavlja i datuma, pa se već uvezeni trening preskače
 *   (i kod ponovnog uvoza iste ili novije datoteke, i kad je ista datoteka uvezena na iPhoneu).
 * * Vježbe se povezuju s katalogom ([ForeignExerciseMatcher]). Ostale postaju vlastite vježbe;
 *   ako vlastita vježba istog naziva već postoji, koristi se ona.
 * * Serije bez ponavljanja i trajanja ("-") se ne uvoze, a ni vježba kojoj ne ostane nijedna serija.
 */
object ForeignWorkoutImport {

    /** Kamo ide vježba iz datoteke. */
    sealed interface Target {
        val name: String

        data class Catalog(val id: String, override val name: String) : Target
        data class ExistingCustom(val id: UUID, override val name: String) : Target
        data class NewCustom(override val name: String) : Target

        val isNewCustom: Boolean get() = this is NewCustom
    }

    /** Jedna vježba iz datoteke i kamo će se uvesti. */
    data class ExerciseMapping(
        /** Naziv i oprema iz datoteke ("incline bench press|dumbbells"). */
        val id: String,
        val sourceName: String,
        val sourceEquipment: String,
        val target: Target,
        val inputType: ExerciseInputType,
        /** U koliko novih treninga se pojavljuje. */
        var workoutCount: Int,
    )

    /** Što će uvoz napraviti. Ne mijenja bazu. */
    data class Preview(
        /** Treninzi koji još ne postoje, od najstarijeg. */
        val newWorkouts: List<ForeignWorkoutsCsv.Workout>,
        /** Treninzi koji su već uvezeni (ili se u datoteci ponavljaju). */
        val alreadyImported: Int,
        /** Vježbe iz novih treninga, abecedno po nazivu iz datoteke. */
        val exercises: List<ExerciseMapping>,
        /** Broj odrađenih serija u novim treninzima. */
        val setCount: Int,
    ) {
        val firstDate: Instant? get() = newWorkouts.firstOrNull()?.startedAt
        val lastDate: Instant? get() = newWorkouts.lastOrNull()?.startedAt
        val newCustomCount: Int get() = exercises.count { it.target.isNewCustom }
    }

    /** Čita datoteku i priprema pregled. Baca [BackupException.InvalidCsv] za neispravnu datoteku. */
    fun preview(
        text: String,
        catalog: ExerciseCatalog,
        language: String,
        store: GymStore,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Preview {
        val workouts = ForeignWorkoutsCsv.parse(text, zone)
        val known = store.sessions.map { it.id }.toSet()

        val seen = mutableSetOf<UUID>()
        val fresh = mutableListOf<ForeignWorkoutsCsv.Workout>()
        var skipped = 0
        for (workout in workouts) {
            val id = workout.stableId
            if (id in known || !seen.add(id)) {
                skipped += 1
                continue
            }
            fresh += workout
        }
        fresh.sortWith(compareBy({ it.startedAt }, { it.line }))

        val mappings = LinkedHashMap<String, ExerciseMapping>()
        var setCount = 0
        for (workout in fresh) {
            val inWorkout = mutableSetOf<String>()
            for (exercise in workout.exercises) {
                val done = exercise.sets.filter { it.isDone }
                if (done.isEmpty()) continue
                setCount += done.size
                val key = mappingKey(exercise)
                val mapping = mappings.getOrPut(key) {
                    ExerciseMapping(
                        id = key,
                        sourceName = exercise.name,
                        sourceEquipment = exercise.equipment,
                        target = target(exercise, catalog, language, store.customExercises),
                        inputType = inputType(exercise),
                        workoutCount = 0,
                    )
                }
                if (inWorkout.add(key)) mapping.workoutCount += 1
            }
        }
        val sorted = mappings.values.sortedWith(compareBy({ it.sourceName.lowercase() }, { it.sourceEquipment }))
        return Preview(fresh, skipped, sorted, setCount)
    }

    /** Uvozi treninge iz pregleda. Sve ili ništa: kod greške se baza vraća na stanje prije uvoza. */
    fun apply(preview: Preview, store: GymStore): BackupImportResult {
        // Pregled je mogao zastarjeti (npr. drugi uvoz je u međuvremenu donio iste treninge).
        val known = store.sessions.map { it.id }.toSet()
        val mappings = preview.exercises.associateBy { it.id }
        val created = mutableMapOf<String, ExerciseRef>()
        val result = BackupImportResult(skipped = preview.alreadyImported)
        try {
            for (workout in preview.newWorkouts) {
                if (workout.stableId in known) {
                    result.skipped += 1
                    continue
                }
                insert(workout, mappings, created, store)
                result.added += 1
            }
            store.save()
        } catch (error: Exception) {
            store.rollback()
            throw error
        }
        return result
    }

    // MARK: Pomoćno

    private fun insert(
        workout: ForeignWorkoutsCsv.Workout,
        mappings: Map<String, ExerciseMapping>,
        created: MutableMap<String, ExerciseRef>,
        store: GymStore,
    ) {
        val session = Session(workout.stableId)
        session.name = workout.name
        session.kind = WorkoutKind.STRENGTH
        session.startedAt = workout.startedAt
        session.notes = workout.details
        session.state = SessionState.FINISHED
        val doneSets = workout.exercises.sumOf { exercise -> exercise.sets.count { it.isDone } }
        // Bez trajanja u datoteci: oko tri minute po seriji, da trening ima smislen kraj.
        val duration = (workout.durationSeconds ?: (maxOf(doneSets, 1) * 180)).toDouble()
        val endedAt = workout.startedAt.plusMillis(Math.round(duration * 1000))
        session.endedAt = endedAt
        session.lastActivityAt = endedAt
        store.insert(session)

        var order = 0
        var setNumber = 0
        for (exercise in workout.exercises) {
            val done = exercise.sets.filter { it.isDone }
            val mapping = mappings[mappingKey(exercise)]
            if (done.isEmpty() || mapping == null) continue
            val ref = reference(mapping, created, store)

            // Vrsta unosa prema podacima ovog treninga (ista vježba je mogla biti i s teretom i bez njega).
            val sessionExercise = session.add(SessionExercise(order, ref, inputType(exercise)))
            order += 1

            done.forEachIndexed { index, row ->
                val set = sessionExercise.add(SetLog(index, SetKind.WORKING))
                set.weightKg = row.weightKg
                set.extraWeightKg = row.extraWeightKg
                set.reps = row.reps
                set.durationSeconds = row.durationSeconds
                set.distanceMeters = row.distanceMeters
                // Datoteka nema vrijeme serija: raspoređuju se ravnomjerno kroz trening, redom.
                setNumber += 1
                val offset = duration * setNumber / maxOf(doneSets, 1)
                set.completedAt = workout.startedAt.plusMillis(Math.round(offset * 1000))
            }
        }
    }

    private fun reference(mapping: ExerciseMapping, created: MutableMap<String, ExerciseRef>, store: GymStore): ExerciseRef =
        when (val target = mapping.target) {
            is Target.Catalog -> ExerciseRef.catalog(target.id, target.name)
            is Target.ExistingCustom -> ExerciseRef.custom(target.id, target.name)
            is Target.NewCustom -> created.getOrPut(mapping.id) {
                val custom = store.insert(CustomExercise(target.name, mapping.inputType))
                custom.equipment = ForeignExerciseMatcher.equipment(mapping.sourceEquipment)
                custom.ref
            }
        }

    private fun target(
        exercise: ForeignWorkoutsCsv.Exercise,
        catalog: ExerciseCatalog,
        language: String,
        customs: List<CustomExercise>,
    ): Target {
        val id = ForeignExerciseMatcher.catalogId(exercise.name, exercise.equipment, catalog)
        val item = id?.let(catalog::exercise)
        if (id != null && item != null) return Target.Catalog(id, item.displayName(language))
        val name = ForeignExerciseMatcher.normalized(exercise.name)
        val custom = customs.firstOrNull { ForeignExerciseMatcher.normalized(it.name) == name && !it.isArchived }
            ?: customs.firstOrNull { ForeignExerciseMatcher.normalized(it.name) == name }
        if (custom != null) return Target.ExistingCustom(custom.id, custom.name)
        return Target.NewCustom(exercise.name)
    }

    private fun inputType(exercise: ForeignWorkoutsCsv.Exercise): ExerciseInputType = when (exercise.kind) {
        ForeignWorkoutsCsv.Kind.WEIGHT_REPS -> ExerciseInputType.WEIGHT_REPS
        ForeignWorkoutsCsv.Kind.WEIGHTED_BODYWEIGHT -> ExerciseInputType.WEIGHTED_BODYWEIGHT
        ForeignWorkoutsCsv.Kind.REPS -> ExerciseInputType.BODYWEIGHT
        ForeignWorkoutsCsv.Kind.DURATION -> ExerciseInputType.DURATION
        ForeignWorkoutsCsv.Kind.DURATION_DISTANCE -> ExerciseInputType.DURATION_DISTANCE
    }

    private fun mappingKey(exercise: ForeignWorkoutsCsv.Exercise): String =
        ForeignExerciseMatcher.normalized(exercise.name) + "|" + ForeignExerciseMatcher.normalized(exercise.equipment)
}
