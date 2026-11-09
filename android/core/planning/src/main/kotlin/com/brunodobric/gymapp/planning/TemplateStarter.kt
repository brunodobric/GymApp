package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.NaturalOrder
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.training.WorkoutEngine
import java.time.Instant
import java.util.Locale
import java.util.UUID

/** Pokretanje treninga iz predloška: podaci se kopiraju u [Session], koji nakon toga ne ovisi o predlošku. */
class TemplateStarter(private val store: GymStore) {

    /** Pokreće sljedeći trening rasporeda, s izmjenama tekućeg ciklusa. */
    fun start(planned: PlannedWorkout, now: Instant = Instant.now()): Session =
        begin(planned.template, planned.exercises, planned.schedule.id, now)

    /** Pokreće predložak izvan rasporeda. */
    fun start(template: WorkoutTemplate, now: Instant = Instant.now()): Session {
        val exercises = template.orderedExercises.map { PlannedExercise(it.id, it.exercise, it.inputType, isReplacement = false) }
        return begin(template, exercises, null, now)
    }

    private fun begin(template: WorkoutTemplate, exercises: List<PlannedExercise>, scheduleId: UUID?, now: Instant): Session {
        val engine = WorkoutEngine(store)
        val session = engine.startSession(template.name, template.kind, templateId = template.id, scheduleId = scheduleId, now = now)
        val sources = template.orderedExercises.associateBy { it.id }
        val groups = linkedMapOf<UUID, MutableList<SessionExercise>>()

        for (planned in exercises) {
            val source = sources[planned.source]
            val created = engine.addExercise(planned.ref, planned.inputType, session, source?.restSeconds, now)
            // Ciljevi pripadaju originalnoj vježbi: zamijenjena vježba zadržava serije iz svoje povijesti.
            if (source != null && !planned.isReplacement && source.sets.isNotEmpty()) {
                applyTargets(source.orderedSets, created, engine, now)
            }
            source?.supersetGroupId?.let { groups.getOrPut(it) { mutableListOf() } += created }
        }
        groups.values.filter { it.size >= 2 }.forEach { engine.makeSuperset(it, session, now) }
        store.save()
        return session
    }

    /** Serije vježbe postaju točno one iz predloška; prazni ciljevi ostaju kakve ih daju smart defaulti. */
    private fun applyTargets(targets: List<TemplateSet>, exercise: SessionExercise, engine: WorkoutEngine, now: Instant) {
        exercise.orderedSets.forEach { engine.removeSet(it, now) }
        for (target in targets) {
            val set = engine.addSet(exercise, target.kind, now)
            target.targetWeightKg?.let { weight ->
                when (exercise.inputType) {
                    ExerciseInputType.WEIGHT_REPS -> set.weightKg = weight
                    ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> set.extraWeightKg = weight
                    ExerciseInputType.BODYWEIGHT, ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> Unit
                }
            }
            target.targetReps?.let { reps ->
                when (exercise.inputType) {
                    ExerciseInputType.WEIGHT_REPS, ExerciseInputType.BODYWEIGHT,
                    ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> set.reps = reps
                    ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> Unit
                }
            }
        }
    }

    companion object {
        /** Treninzi koji se mogu pokrenuti izvan rasporeda, po nazivu: samo treninzi snage s barem jednom vježbom. */
        fun startable(templates: List<WorkoutTemplate>, locale: Locale = Locale.getDefault()): List<WorkoutTemplate> {
            val names = NaturalOrder(locale)
            return templates.filter { it.kind == WorkoutKind.STRENGTH && it.exercises.isNotEmpty() }
                .sortedWith { a, b -> names.compare(a.name, b.name) }
        }
    }
}
