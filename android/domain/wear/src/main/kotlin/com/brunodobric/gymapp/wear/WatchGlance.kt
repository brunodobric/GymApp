package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.widgets.WidgetSnapshot
import java.time.Instant

/**
 * Sadržaj pločice, komplikacija i trajne aktivnosti na satu (`ComplicationState` na iOS-u): odmor u tijeku,
 * trening u tijeku ili sljedeći trening rasporeda, te tjedan. Mijenja se samo kad se promijeni nešto što
 * se vidi, pa usporedba dvije vrijednosti kaže treba li osvježiti prikaze.
 */
data class WatchGlance(
    val activeName: String? = null,
    val activeStartedAt: Instant? = null,
    val restStartedAt: Instant? = null,
    val restEndsAt: Instant? = null,
    val next: Next? = null,
    val week: WidgetSnapshot.Week? = null,
    val accent: String = "blue",
) {
    /** Sljedeći trening: [planId] je `PlannedWorkoutPayload.id`, za pokretanje s pločice. */
    data class Next(val planId: String, val name: String, val scheduleName: String?, val exerciseCount: Int)

    enum class Kind { RESTING, ACTIVE, NEXT, EMPTY }

    /** Odmor traje u trenutku [now]. */
    fun isResting(now: Instant): Boolean = activeName != null && restEndsAt?.let { it > now } == true

    fun kind(now: Instant): Kind = when {
        isResting(now) -> Kind.RESTING
        activeName != null -> Kind.ACTIVE
        next != null -> Kind.NEXT
        else -> Kind.EMPTY
    }

    /** Tjedan kakav je u trenutku [now] (snimka s mobitela može biti iz prošlog tjedna). */
    fun week(now: Instant): WidgetSnapshot.Week? = week?.current(now)

    companion object {
        fun from(state: WatchUiState): WatchGlance {
            val active = state.active?.takeIf { it.state == SessionState.ACTIVE }
            val rest = if (active != null && state.isResting) state.restTimer else null
            val plan = state.context.upcoming.firstOrNull()
            return WatchGlance(
                activeName = active?.name,
                activeStartedAt = active?.startedAt,
                restStartedAt = rest?.startedAt,
                restEndsAt = rest?.endsAt,
                next = plan?.let { Next(it.id, it.name, it.scheduleName, it.exercises.size) },
                week = state.context.week,
                accent = state.context.accent,
            )
        }
    }
}

/** Plan po `PlannedWorkoutPayload.id` (sljedeći treninzi rasporeda pa predlošci). */
fun WatchContextPayload.plan(id: String): PlannedWorkoutPayload? = (upcoming + templates).firstOrNull { it.id == id }
