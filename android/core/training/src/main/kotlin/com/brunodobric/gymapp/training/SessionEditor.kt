package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.WorkoutKind
import java.time.Instant

/**
 * Naknadno uređivanje odrađenog treninga: naziv, vrijeme, bilješke, vježbe i serije.
 *
 * Za razliku od [WorkoutEngine] ništa se ne sprema usput: promjene se spremaju tek u [save], a [cancel]
 * vraća bazu na zadnje spremljeno stanje (na iOS-u to radi zaseban kontekst).
 */
class SessionEditor(private val store: GymStore) {

    // MARK: Vježbe

    /** Dodaje vježbu na kraj treninga s praznim radnim serijama. */
    fun addExercise(ref: ExerciseRef, inputType: ExerciseInputType, session: Session): SessionExercise {
        val order = (session.exercises.maxOfOrNull { it.orderIndex } ?: -1) + 1
        val exercise = session.add(SessionExercise(order, ref, inputType))
        repeat(WorkoutEngine.DEFAULT_WORKING_SETS) { exercise.add(SetLog(it)) }
        return exercise
    }

    /** Briše vježbu sa svim serijama. Superset s jednom preostalom vježbom se raspušta. */
    fun removeExercise(exercise: SessionExercise) {
        val session = exercise.session
        val group = exercise.supersetGroupId
        store.delete(exercise)
        if (session == null) return
        val rest = session.orderedExercises
        rest.forEachIndexed { index, item -> item.orderIndex = index }
        val members = rest.filter { group != null && it.supersetGroupId == group }
        if (members.size == 1) members[0].supersetGroupId = null
    }

    // MARK: Serije

    /**
     * Nova serija preuzima vrijednosti zadnje serije iste vrste. Ako su vrijednosti potpune, serija je odmah
     * završena (dodaje se serija koja je odrađena, a nije upisana); prazna čeka unos i kvačicu.
     */
    fun addSet(exercise: SessionExercise, kind: SetKind = SetKind.WORKING, now: Instant = Instant.now()): SetLog {
        val existing = exercise.orderedSets
        val set = SetLog(existing.size, kind)
        existing.lastOrNull { it.kind == kind }?.let { last ->
            set.weightKg = last.weightKg
            set.reps = last.reps
            set.extraWeightKg = last.extraWeightKg
            set.durationSeconds = last.durationSeconds
            set.distanceMeters = last.distanceMeters
        }
        exercise.add(set)
        if (SetMetrics.isComplete(set.values, exercise.inputType)) set.completedAt = completionDate(exercise, now)
        return set
    }

    fun removeSet(set: SetLog) {
        val exercise = set.exercise
        store.delete(set)
        exercise?.orderedSets?.forEachIndexed { index, remaining -> remaining.orderIndex = index }
    }

    /** Kvačica u uređivaču: završena serija mora imati sve vrijednosti, ali ne pokreće odmor. */
    fun toggleCompleted(set: SetLog, now: Instant = Instant.now()) {
        if (set.isCompleted) {
            set.completedAt = null
            return
        }
        val exercise = set.exercise ?: return
        if (!SetMetrics.isComplete(set.values, exercise.inputType)) throw WorkoutError.SetIncomplete
        set.completedAt = completionDate(exercise, now)
    }

    // MARK: Spremanje

    /**
     * Sprema izmjene kao kod završetka treninga: nezavršene serije i vježbe bez završene serije se brišu,
     * a trening bez ijedne završene serije se ne sprema. Kraj nije prije početka.
     */
    fun save(session: Session) {
        val exercises = session.orderedExercises
        fun completedSets(exercise: SessionExercise) = exercise.orderedSets.filter { it.isCompleted }
        val remaining = exercises.filter { !it.isRemoved && completedSets(it).isNotEmpty() }
        if (remaining.isEmpty()) throw WorkoutError.NothingCompleted

        exercises.filter { exercise -> remaining.none { it === exercise } }.forEach(store::delete)
        // Superset kojem je ostala jedna vježba se raspušta.
        for (exercise in remaining) {
            val group = exercise.supersetGroupId ?: continue
            if (remaining.count { it.supersetGroupId == group } == 1) exercise.supersetGroupId = null
        }
        remaining.forEachIndexed { order, exercise ->
            exercise.orderIndex = order
            exercise.orderedSets.filter { !it.isCompleted }.forEach(store::delete)
            completedSets(exercise).forEachIndexed { index, set -> set.orderIndex = index }
        }

        // Udaljenost treninga snage je zbroj udaljenosti serija; kardio trening ostaje sa svojom udaljenošću.
        val distance = remaining.flatMap(::completedSets).mapNotNull { it.distanceMeters }.sum()
        if (distance > 0) {
            session.distanceMeters = distance
        } else if (session.kind == WorkoutKind.STRENGTH) {
            session.distanceMeters = null
        }
        session.endedAt?.let { if (it < session.startedAt) session.endedAt = session.startedAt }
        session.name = session.name.trim()
        session.lastActivityAt = session.endedAt ?: session.lastActivityAt
        store.save()
    }

    /** Odustajanje: sve izmjene od zadnjeg spremanja se odbacuju. */
    fun cancel() {
        store.rollback()
    }

    /** Serija dodana naknadno dobiva trenutak kraja treninga (kao da je odrađena prije njega). */
    private fun completionDate(exercise: SessionExercise, now: Instant): Instant = exercise.session?.endedAt ?: now
}
