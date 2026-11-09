package com.brunodobric.gymapp.model

/** Brisanje vlastitih vježbi. */
object CustomExerciseStore {

    enum class RemovalResult {
        DELETED,

        /** Vježba ima povijest ili je u predlošku, pa je samo skrivena. */
        ARCHIVED,
    }

    /** Je li vježba korištena u nekom treningu ili predlošku. */
    fun isReferenced(exercise: CustomExercise, store: GymStore): Boolean =
        store.sessionExercises.any { it.exerciseCustomId == exercise.id } ||
            store.templateExercises.any { it.exerciseCustomId == exercise.id }

    /** Briše vlastitu vježbu, a ako ima povijest samo je arhivira kako statistika ne bi izgubila podatke. */
    fun remove(exercise: CustomExercise, store: GymStore): RemovalResult {
        val result = if (isReferenced(exercise, store)) {
            exercise.isArchived = true
            RemovalResult.ARCHIVED
        } else {
            store.delete(exercise)
            RemovalResult.DELETED
        }
        store.save()
        return result
    }
}
