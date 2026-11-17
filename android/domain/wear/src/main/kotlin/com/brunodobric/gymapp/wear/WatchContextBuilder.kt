package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.planning.PlannedExercise
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.TemplateStarter
import com.brunodobric.gymapp.training.SetPlanner
import com.brunodobric.gymapp.training.SmartDefaults
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.target
import com.brunodobric.gymapp.widgets.WidgetSnapshot
import java.time.Instant
import java.util.UUID

/**
 * Slaže kontekst za sat iz baze na mobitelu (`WatchContextBuilder` na iOS-u): sljedeće treninge rasporeda i
 * predloške, s istim serijama i pretpunjenim vrijednostima koje bi dobio trening pokrenut na mobitelu
 * ([TemplateStarter]).
 */
class WatchContextBuilder(
    private val store: GymStore,
    /** Je li vježba kardio, po ključu `ExerciseRef.key`. */
    private val isCardio: (String) -> Boolean = { false },
    /** Je li vježba složena, po ključu `ExerciseRef.key`. */
    private val isCompound: (String) -> Boolean? = { null },
    /** Korak težine vježbe u jedinici prikaza (`WeightStepSettings.resolver`). */
    private val weightStep: (ExerciseRef) -> Double? = { null },
) {

    /** [week] i [bodyWeightKg] dolaze iz snimke za widgete, da sat i widgeti pokazuju isto. */
    fun make(now: Instant = Instant.now(), week: WidgetSnapshot.Week? = null, bodyWeightKg: Double? = null): WatchContextPayload {
        val settings = store.settings()
        val upcoming = ScheduleEngine(store).upcomingWorkouts().map { planned ->
            payload(planned.template, planned.exercises, planned.schedule.id, planned.schedule.name, now)
        }
        val templates = TemplateStarter.startable(store.templates).take(MAX_TEMPLATES).map { template ->
            val exercises = template.orderedExercises.map { PlannedExercise(it.id, it.exercise, it.inputType, isReplacement = false) }
            payload(template, exercises, scheduleId = null, scheduleName = null, now = now)
        }
        return WatchContextPayload(
            upcoming = upcoming,
            templates = templates,
            weightUnit = settings.weightUnit.raw,
            defaultRestSeconds = settings.defaultRestSeconds,
            compoundRestSeconds = settings.compoundRestSeconds,
            savesToHealth = settings.wantsHealthKit,
            generatedAt = now.truncatedToMillis(),
            week = week,
            bodyWeightKg = bodyWeightKg,
            accent = settings.accent.raw,
        )
    }

    internal fun payload(
        template: WorkoutTemplate,
        exercises: List<PlannedExercise>,
        scheduleId: UUID?,
        scheduleName: String?,
        now: Instant = Instant.now(),
    ): PlannedWorkoutPayload {
        val sources = template.orderedExercises.associateBy { it.id }
        val settings = store.settings()
        val unit = settings.weightUnit
        val suggestsHeavier = settings.suggestsHeavierWeight
        val engine = WorkoutEngine(store)
        // Superset postoji samo ako u planu ostanu barem dvije vježbe iz iste grupe (kao u TemplateStarteru).
        val groupSizes = exercises.mapNotNull { sources[it.source]?.supersetGroupId }.groupingBy { it }.eachCount()
        val groupNumbers = mutableMapOf<UUID, Int>()
        val result = exercises.map { planned ->
            val source = sources[planned.source]
            val group = source?.supersetGroupId?.takeIf { (groupSizes[it] ?: 0) >= 2 }?.let { id ->
                groupNumbers.getOrPut(id) { groupNumbers.size }
            }
            val targets = if (planned.isReplacement) emptyList() else source?.orderedSets.orEmpty().map { it.target }
            // Ista povijest kao `WorkoutEngine.addExercise` za trening iz ovog predloška pokrenut sada.
            val performances = engine.previousPerformances(planned.ref, Session(template.name).also { it.templateId = template.id; it.startedAt = now })
            val previous = performances.firstOrNull().orEmpty()
            val plan = SetPlanner.plan(
                previous = previous,
                recentWorkingCounts = performances.take(SmartDefaults.RECENT_PERFORMANCE_COUNT).map { sets -> sets.count { it.kind == SetKind.WORKING } },
                targets = targets,
                inputType = planned.inputType,
                weightStep = if (suggestsHeavier) weightStep(planned.ref) else null,
                unit = unit,
            )
            val note = if (planned.isReplacement) "" else source?.notes.orEmpty().trim()
            PlannedExercisePayload(
                exercise = planned.ref,
                inputType = planned.inputType,
                restSeconds = source?.restSeconds,
                supersetGroup = group,
                sets = plan.sets.map(::PlannedSetPayload),
                isCardio = isCardio(planned.ref.key),
                previous = previous.map(::PlannedSetPayload),
                isCompound = isCompound(planned.ref.key),
                weightStep = weightStep(planned.ref),
                targetRepsMin = plan.repRange?.lower,
                targetRepsMax = plan.repRange?.upper,
                loadChangeKg = plan.loadChangeKg,
                notes = note.ifEmpty { null },
            )
        }
        return PlannedWorkoutPayload(
            templateId = template.id, scheduleId = scheduleId, name = template.name, scheduleName = scheduleName,
            kind = template.kind, exercises = result,
        )
    }

    companion object {
        /** Najviše predložaka u kontekstu (podatak u Data Layeru ima ograničenje veličine). */
        const val MAX_TEMPLATES = 20
    }
}
