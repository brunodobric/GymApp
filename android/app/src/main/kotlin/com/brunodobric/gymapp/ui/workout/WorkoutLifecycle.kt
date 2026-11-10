package com.brunodobric.gymapp.ui.workout

import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.training.WorkoutEngine

/**
 * Jedan put za završetak i odbacivanje treninga (`WorkoutLifecycle` na iOS-u). Svaki ulaz (ekran treninga,
 * kasnije obavijest i prečac) ide kroz njega, da raspored napreduje jednako.
 */
object WorkoutLifecycle {
    /** Završava trening i pomiče raspored ako je to bio njegov trening. Baca `WorkoutError.NothingCompleted`. */
    fun finish(session: Session, store: GymStore) {
        WorkoutEngine(store).finishSession(session)
        ScheduleEngine(store).sessionFinished(session)
    }

    fun discard(session: Session, store: GymStore) {
        WorkoutEngine(store).discardSession(session)
    }
}
