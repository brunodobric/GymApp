package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.TemplateExercise
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.WorkoutTemplate

/**
 * Razlika u strukturi između odrađenog treninga i predloška iz kojeg je pokrenut: koje su vježbe dodane,
 * koje nisu rađene i kojima se promijenio broj serija. Težine i ponavljanja se ne gledaju: o njima odlučuje
 * prijedlog veće težine (`SetPlanner`). Isto kao `TemplateChanges` na iOS-u.
 */
data class TemplateChanges(
    /** Vježbe odrađene u treningu kojih nema u predlošku. */
    val added: List<String> = emptyList(),
    /** Vježbe iz predloška koje u treningu nisu rađene. */
    val removed: List<String> = emptyList(),
    /** Vježbe s drugim brojem serija. */
    val setCounts: List<SetCount> = emptyList(),
    /** Isti skup vježbi, ali drugim redoslijedom. */
    val reordered: Boolean = false,
) {
    data class SetCount(val name: String, val from: Int, val to: Int)

    val isEmpty: Boolean get() = added.isEmpty() && removed.isEmpty() && setCounts.isEmpty() && !reordered
}

/** Promjene i ažuriranje predloška iz odrađenog treninga ("Ažuriraj trening" na kraju treninga). */
class TemplateUpdater(private val store: GymStore) {

    /** Promjene koje bi [updateTemplate] napravio. Rađena vježba je ona s barem jednom završenom serijom. */
    fun changes(session: Session, template: WorkoutTemplate): TemplateChanges {
        val done = performed(session)
        val planned = template.orderedExercises
        val plannedKeys = planned.map { it.exercise.key }
        val doneKeys = done.map { it.exerciseKey }
        val setCounts = planned.mapNotNull { item ->
            val match = done.firstOrNull { it.exerciseKey == item.exercise.key } ?: return@mapNotNull null
            val count = match.orderedSets.count { it.isCompleted }
            if (count == item.orderedSets.size) null else TemplateChanges.SetCount(item.exerciseName, item.orderedSets.size, count)
        }
        return TemplateChanges(
            added = done.filter { it.exerciseKey !in plannedKeys }.map { it.exerciseName },
            removed = planned.filter { it.exercise.key !in doneKeys }.map { it.exerciseName },
            setCounts = setCounts,
            reordered = doneKeys.filter { it in plannedKeys } != plannedKeys.filter { it in doneKeys },
        )
    }

    /**
     * Mijenja strukturu predloška prema odrađenom treningu: redoslijed i skup vježbi kao u treningu, a broj
     * i vrsta serija kao završene serije. Postojeće vježbe zadržavaju ciljeve, bilješke i pauze; nova serija
     * preuzima cilj zadnje serije iste vrste. Nove vježbe dobivaju ciljeve ponavljanja iz treninga, bez težine.
     */
    fun updateTemplate(template: WorkoutTemplate, session: Session) {
        val done = performed(session)
        if (done.isEmpty()) return
        val remaining = template.orderedExercises.toMutableList()
        val ordered = mutableListOf<TemplateExercise>()
        for (exercise in done) {
            val completed = exercise.orderedSets.filter { it.isCompleted }
            val index = remaining.indexOfFirst { it.exercise.key == exercise.exerciseKey }
            if (index >= 0) {
                val item = remaining.removeAt(index)
                resize(item, completed.map { it.kind })
                ordered += item
            } else {
                val item = template.add(TemplateExercise(0, exercise.exercise, exercise.inputType))
                item.restSeconds = exercise.restSeconds
                completed.forEachIndexed { setIndex, set -> item.add(TemplateSet(setIndex, set.kind, targetReps = set.reps)) }
                ordered += item
            }
        }
        remaining.forEach(store::delete)
        ordered.forEachIndexed { index, item -> item.orderIndex = index }
        // Superset s jednom vježbom (druga nije rađena) nema smisla.
        ordered.filter { it.supersetGroupId != null }.groupBy { it.supersetGroupId }.values
            .filter { it.size == 1 }
            .forEach { it[0].supersetGroupId = null }
        store.save()
    }

    /** Serije predloška po vrstama iz treninga: postojeće se zadržavaju po redu, višak se briše. */
    private fun resize(exercise: TemplateExercise, kinds: List<SetKind>) {
        val original = exercise.orderedSets
        val pool = original.toMutableList()
        val result = mutableListOf<TemplateSet>()
        for (kind in kinds) {
            val index = pool.indexOfFirst { it.kind == kind }
            if (index >= 0) {
                result += pool.removeAt(index)
            } else {
                val last = result.lastOrNull { it.kind == kind } ?: original.lastOrNull { it.kind == kind }
                val set = TemplateSet(0, kind, last?.targetWeightKg, last?.targetReps)
                set.targetRepsMax = last?.targetRepsMax
                result += exercise.add(set)
            }
        }
        pool.forEach(store::delete)
        result.forEachIndexed { index, set -> set.orderIndex = index }
    }

    private fun performed(session: Session): List<SessionExercise> =
        session.orderedExercises.filter { exercise -> !exercise.isRemoved && exercise.orderedSets.any { it.isCompleted } }
}
