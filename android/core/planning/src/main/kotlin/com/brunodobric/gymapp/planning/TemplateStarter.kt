package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.NaturalOrder
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.WeightStepSettings
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.target
import java.time.Instant
import java.util.Locale
import java.util.UUID

/** Pokretanje treninga iz predloška: podaci se kopiraju u [Session], koji nakon toga ne ovisi o predlošku. */
class TemplateStarter(
    private val store: GymStore,
    /**
     * Korak težine vježbe u jedinici korisnika, za prijedlog veće težine ([SetPlanner]). null: korak iz postavki
     * bez opreme vježbe (aplikacija predaje korak s opremom iz kataloga).
     */
    private val weightStep: ((ExerciseRef) -> Double)? = null,
) {

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
        val settings = store.settings()
        val step = weightStep ?: WeightStepSettings.resolver(settings, null, emptyList())
        val session = engine.startSession(template.name, template.kind, templateId = template.id, scheduleId = scheduleId, now = now)
        val sources = template.orderedExercises.associateBy { it.id }
        val groups = linkedMapOf<UUID, MutableList<SessionExercise>>()

        for (planned in exercises) {
            val source = sources[planned.source]
            // Ciljevi pripadaju originalnoj vježbi: zamijenjena vježba zadržava serije iz svoje povijesti.
            val targets = if (planned.isReplacement) emptyList() else source?.orderedSets.orEmpty().map { it.target }
            val created = engine.addExercise(
                planned.ref, planned.inputType, session, source?.restSeconds, now,
                targets = targets, weightStep = step(planned.ref), unit = settings.weightUnit,
            )
            if (source != null && !planned.isReplacement) created.notes = source.notes.trim()
            source?.supersetGroupId?.let { groups.getOrPut(it) { mutableListOf() } += created }
        }
        groups.values.filter { it.size >= 2 }.forEach { engine.makeSuperset(it, session, now) }
        store.save()
        return session
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
