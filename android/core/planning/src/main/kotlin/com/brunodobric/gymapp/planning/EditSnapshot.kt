package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.model.CycleOverride
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.ScheduleItem
import com.brunodobric.gymapp.model.TemplateExercise
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.WorkoutTemplate
import java.util.UUID

/**
 * Stanje rasporeda prije uređivanja, za "Izađi bez spremanja".
 *
 * Uređivač sprema svaku promjenu odmah (premještanje, dodavanje, prekidači), pa se odustajanje ne može
 * riješiti s `rollback`. Snimka pamti polja rasporeda, njegov niz i izmjene ciklusa, a [restore] ih vraća.
 */
class ScheduleSnapshot(schedule: Schedule, store: GymStore) {
    private data class Item(val id: UUID, val orderIndex: Int, val kindRaw: String, val workoutTemplateId: UUID?)

    private data class Change(
        val id: UUID,
        val cycleNumber: Int,
        val scheduleItemId: UUID?,
        val kindRaw: String,
        val targetExerciseKey: String?,
        val replacementCatalogId: String?,
        val replacementCustomId: UUID?,
        val replacementName: String?,
        val replacementInputTypeRaw: String?,
    )

    private val name = schedule.name
    private val details = schedule.details
    private val cycleCount = schedule.cycleCount
    private val reminderModeRaw = schedule.reminderModeRaw
    private val weekdaysRaw = schedule.weekdaysRaw
    private val reminderMinutes = schedule.reminderMinutes
    private val reminderGapDays = schedule.reminderGapDays
    private val isActive = schedule.isActive
    private val currentCycle = schedule.currentCycle
    private val currentPosition = schedule.currentPosition
    private val items = schedule.orderedItems.map { Item(it.id, it.orderIndex, it.kindRaw, it.workoutTemplateId) }
    private val changes = overrides(schedule, store).map {
        Change(
            it.id, it.cycleNumber, it.scheduleItemId, it.kindRaw, it.targetExerciseKey, it.replacementCatalogId,
            it.replacementCustomId, it.replacementName, it.replacementInputTypeRaw,
        )
    }

    /** Vraća raspored na stanje iz snimke i sprema. */
    fun restore(schedule: Schedule, store: GymStore) {
        schedule.name = name
        schedule.details = details
        schedule.cycleCount = cycleCount
        schedule.reminderModeRaw = reminderModeRaw
        schedule.weekdaysRaw = weekdaysRaw
        schedule.reminderMinutes = reminderMinutes
        schedule.reminderGapDays = reminderGapDays
        schedule.isActive = isActive
        schedule.currentCycle = currentCycle
        schedule.currentPosition = currentPosition

        // Postojeće stavke se ažuriraju (zadržavaju identitet), dodane se brišu, obrisane stvaraju iznova.
        val existing = schedule.items.associateByTo(LinkedHashMap()) { it.id }
        for (item in items) {
            val model = existing.remove(item.id) ?: schedule.add(ScheduleItem(item.id))
            model.orderIndex = item.orderIndex
            model.kindRaw = item.kindRaw
            model.workoutTemplateId = item.workoutTemplateId
        }
        existing.values.forEach(store::delete)

        overrides(schedule, store).forEach(store::delete)
        for (change in changes) {
            val model = CycleOverride(change.id)
            model.scheduleId = schedule.id
            model.cycleNumber = change.cycleNumber
            model.scheduleItemId = change.scheduleItemId
            model.kindRaw = change.kindRaw
            model.targetExerciseKey = change.targetExerciseKey
            model.replacementCatalogId = change.replacementCatalogId
            model.replacementCustomId = change.replacementCustomId
            model.replacementName = change.replacementName
            model.replacementInputTypeRaw = change.replacementInputTypeRaw
            store.insert(model)
        }
        store.save()
    }

    private companion object {
        fun overrides(schedule: Schedule, store: GymStore): List<CycleOverride> =
            store.cycleOverrides.filter { it.scheduleId == schedule.id }
    }
}

/** Stanje treninga (predloška) prije uređivanja, za "Izađi bez spremanja": naziv, plan i vježbe sa serijama. */
class TemplateSnapshot(template: WorkoutTemplate) {
    private data class SetValue(
        val id: UUID,
        val orderIndex: Int,
        val kindRaw: String,
        val targetWeightKg: Double?,
        val targetReps: Int?,
        val targetRepsMax: Int?,
    )

    private data class ExerciseValue(
        val id: UUID,
        val orderIndex: Int,
        val catalogId: String?,
        val customId: UUID?,
        val name: String,
        val inputTypeRaw: String,
        val supersetGroupId: UUID?,
        val restSeconds: Int?,
        val notes: String,
        val sets: List<SetValue>,
    )

    private val name = template.name
    private val details = template.details
    private val kindRaw = template.kindRaw
    private val exercises = template.orderedExercises.map { exercise ->
        ExerciseValue(
            exercise.id, exercise.orderIndex, exercise.exerciseCatalogId, exercise.exerciseCustomId,
            exercise.exerciseName, exercise.inputTypeRaw, exercise.supersetGroupId, exercise.restSeconds, exercise.notes,
            exercise.orderedSets.map {
                SetValue(it.id, it.orderIndex, it.kindRaw, it.targetWeightKg, it.targetReps, it.targetRepsMax)
            },
        )
    }

    /** Vraća trening na stanje iz snimke i sprema. */
    fun restore(template: WorkoutTemplate, store: GymStore) {
        template.name = name
        template.details = details
        template.kindRaw = kindRaw

        val existing = template.exercises.associateByTo(LinkedHashMap()) { it.id }
        for (value in exercises) {
            val exercise = existing.remove(value.id) ?: template.add(TemplateExercise(value.id))
            exercise.orderIndex = value.orderIndex
            exercise.exerciseCatalogId = value.catalogId
            exercise.exerciseCustomId = value.customId
            exercise.exerciseName = value.name
            exercise.inputTypeRaw = value.inputTypeRaw
            exercise.supersetGroupId = value.supersetGroupId
            exercise.restSeconds = value.restSeconds
            exercise.notes = value.notes
            restoreSets(value.sets, exercise, store)
        }
        existing.values.forEach(store::delete)
        store.save()
    }

    private fun restoreSets(sets: List<SetValue>, exercise: TemplateExercise, store: GymStore) {
        val existing = exercise.sets.associateByTo(LinkedHashMap()) { it.id }
        for (value in sets) {
            val model = existing.remove(value.id) ?: exercise.add(TemplateSet(value.id))
            model.orderIndex = value.orderIndex
            model.kindRaw = value.kindRaw
            model.targetWeightKg = value.targetWeightKg
            model.targetReps = value.targetReps
            model.targetRepsMax = value.targetRepsMax
        }
        existing.values.forEach(store::delete)
    }
}
