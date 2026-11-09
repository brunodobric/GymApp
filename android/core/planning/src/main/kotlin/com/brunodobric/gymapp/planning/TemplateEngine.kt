package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.TemplateExercise
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.model.moveElements
import java.util.UUID

sealed class PlanningError(message: String) : Exception(message) {
    data object NeedsTwoExercises : PlanningError("Superset traži dvije vježbe")
}

/** Vježba odabrana za dodavanje u predložak: referenca i način unosa. */
data class ExerciseChoice(val ref: ExerciseRef, val inputType: ExerciseInputType)

/** Uređivanje predložaka treninga: vježbe, ciljane serije, supersetovi, pauze i redoslijed. Svaka promjena odmah se sprema. */
class TemplateEngine(private val store: GymStore) {

    // MARK: Predlošci

    fun createTemplate(name: String, kind: WorkoutKind = WorkoutKind.STRENGTH): WorkoutTemplate {
        val template = store.insert(WorkoutTemplate(name, kind))
        store.save()
        return template
    }

    /** Brisanje predloška ne dira odrađene treninge (oni su neovisna kopija) ni stavke rasporeda. */
    fun delete(template: WorkoutTemplate) {
        store.delete(template)
        store.save()
    }

    // MARK: Vježbe

    fun addExercise(
        ref: ExerciseRef,
        inputType: ExerciseInputType,
        template: WorkoutTemplate,
        setCount: Int = DEFAULT_SET_COUNT,
    ): TemplateExercise {
        val order = (template.exercises.maxOfOrNull { it.orderIndex } ?: -1) + 1
        val exercise = template.add(TemplateExercise(order, ref, inputType))
        repeat(maxOf(setCount, 0)) { exercise.add(TemplateSet(it)) }
        store.save()
        return exercise
    }

    /**
     * Dodaje više vježbi odjednom, redom kojim su zadane. S [index] se umeću na to mjesto u predlošku,
     * a bez njega idu na kraj. Svaka dobiva zadane serije.
     */
    fun addExercises(
        choices: List<ExerciseChoice>,
        template: WorkoutTemplate,
        index: Int? = null,
        setCount: Int = DEFAULT_SET_COUNT,
    ): List<TemplateExercise> {
        val ordered = template.orderedExercises.toMutableList()
        val position = (index ?: ordered.size).coerceIn(0, ordered.size)
        val added = choices.map { choice ->
            template.add(TemplateExercise(0, choice.ref, choice.inputType)).also { exercise ->
                repeat(maxOf(setCount, 0)) { exercise.add(TemplateSet(it)) }
            }
        }
        ordered.addAll(position, added)
        ordered.forEachIndexed { order, exercise -> exercise.orderIndex = order }
        store.save()
        return added
    }

    fun removeExercise(exercise: TemplateExercise) {
        val template = exercise.template
        val group = exercise.supersetGroupId
        store.delete(exercise)
        if (template != null) {
            val rest = template.orderedExercises
            rest.forEachIndexed { index, item -> item.orderIndex = index }
            // Superset s jednom vježbom nema smisla.
            val members = rest.filter { group != null && it.supersetGroupId == group }
            if (members.size == 1) members[0].supersetGroupId = null
        }
        store.save()
    }

    /** Premješta vježbe kao `onMove` u SwiftUI-ju. */
    fun moveExercises(template: WorkoutTemplate, from: Collection<Int>, to: Int) {
        val ordered = template.orderedExercises.toMutableList()
        ordered.moveElements(from, to)
        ordered.forEachIndexed { index, exercise -> exercise.orderIndex = index }
        store.save()
    }

    fun setRest(seconds: Int?, exercise: TemplateExercise) {
        exercise.restSeconds = seconds
        store.save()
    }

    // MARK: Supersetovi

    /** Spaja vježbe u superset i postavlja ih jednu do druge, na mjesto prve među njima. */
    fun makeSuperset(exercises: List<TemplateExercise>, template: WorkoutTemplate) {
        if (exercises.size < 2) throw PlanningError.NeedsTwoExercises
        val group = UUID.randomUUID()
        val selected = exercises.map { it.id }.toSet()
        val ordered = template.orderedExercises
        val anchor = ordered.indexOfFirst { it.id in selected }.takeIf { it >= 0 } ?: return
        val members = ordered.filter { it.id in selected }
        val others = ordered.filter { it.id !in selected }
        val insertAt = minOf(anchor, others.size)
        val result = others.subList(0, insertAt) + members + others.subList(insertAt, others.size)
        members.forEach { it.supersetGroupId = group }
        result.forEachIndexed { index, exercise -> exercise.orderIndex = index }
        store.save()
    }

    fun removeFromSuperset(exercise: TemplateExercise) {
        val group = exercise.supersetGroupId
        exercise.supersetGroupId = null
        val template = exercise.template
        if (template != null && group != null) {
            val rest = template.orderedExercises.filter { it.supersetGroupId == group }
            if (rest.size == 1) rest[0].supersetGroupId = null
        }
        store.save()
    }

    // MARK: Serije

    /** Nova serija preuzima ciljeve zadnje serije iste vrste. */
    fun addSet(exercise: TemplateExercise, kind: SetKind = SetKind.WORKING): TemplateSet {
        val existing = exercise.orderedSets
        val set = TemplateSet(existing.size, kind)
        existing.lastOrNull { it.kind == kind }?.let { last ->
            set.targetWeightKg = last.targetWeightKg
            set.targetReps = last.targetReps
            set.targetRepsMax = last.targetRepsMax
        }
        exercise.add(set)
        store.save()
        return set
    }

    fun removeSet(set: TemplateSet) {
        val exercise = set.exercise
        store.delete(set)
        exercise?.orderedSets?.forEachIndexed { index, remaining -> remaining.orderIndex = index }
        store.save()
    }

    fun setTargets(set: TemplateSet, weightKg: Double?, reps: Int?) {
        set.targetWeightKg = weightKg
        set.targetReps = reps
        // Raspon ostaje samo dok mu je gornja granica iznad novog cilja.
        val max = set.targetRepsMax
        if (max != null && max <= (reps ?: Int.MAX_VALUE)) set.targetRepsMax = null
        store.save()
    }

    // MARK: Predložak iz odrađenog treninga

    /**
     * Novi trening (predložak) iz odrađenog treninga: isti naziv, iste vježbe redom, pauze i supersetovi,
     * a ciljevi serija su vrijednosti završenih serija. Odrađeni trening ostaje netaknut.
     */
    fun createTemplate(session: Session): WorkoutTemplate {
        val template = store.insert(WorkoutTemplate(session.name, WorkoutKind.STRENGTH))
        val groups = mutableMapOf<UUID, UUID>()
        session.orderedExercises.filter { !it.isRemoved }.forEachIndexed { order, exercise ->
            val copy = template.add(TemplateExercise(order, exercise.exercise, exercise.inputType))
            copy.restSeconds = exercise.restSeconds
            exercise.supersetGroupId?.let { copy.supersetGroupId = groups.getOrPut(it) { UUID.randomUUID() } }
            val completed = exercise.orderedSets.filter { it.isCompleted }
            val sets = completed.ifEmpty { exercise.orderedSets }
            sets.forEachIndexed { index, set ->
                copy.add(TemplateSet(index, set.kind, targetWeight(set, exercise.inputType), targetReps(set, exercise.inputType)))
            }
            if (sets.isEmpty()) repeat(DEFAULT_SET_COUNT) { copy.add(TemplateSet(it)) }
        }
        // Superset s jednom vježbom (druga je bila izbačena) nema smisla.
        template.orderedExercises.filter { it.supersetGroupId != null }.groupBy { it.supersetGroupId }
            .values.filter { it.size == 1 }.forEach { it[0].supersetGroupId = null }
        store.save()
        return template
    }

    companion object {
        /** Broj radnih serija nove vježbe u predlošku. */
        const val DEFAULT_SET_COUNT = 3

        /** Ciljana težina predloška: težina, a kod vlastite težine dodatna težina ili pomoć. */
        internal fun targetWeight(set: SetLog, inputType: ExerciseInputType): Double? = when (inputType) {
            ExerciseInputType.WEIGHT_REPS -> set.weightKg
            ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> set.extraWeightKg
            ExerciseInputType.BODYWEIGHT, ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> null
        }

        internal fun targetReps(set: SetLog, inputType: ExerciseInputType): Int? = when (inputType) {
            ExerciseInputType.WEIGHT_REPS, ExerciseInputType.BODYWEIGHT,
            ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> set.reps
            ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> null
        }
    }
}
