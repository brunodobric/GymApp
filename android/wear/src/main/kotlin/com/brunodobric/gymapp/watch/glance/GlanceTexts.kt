package com.brunodobric.gymapp.watch.glance

import android.content.ComponentName
import android.content.Context
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.brunodobric.gymapp.watch.R
import com.brunodobric.gymapp.wear.WatchGlance
import com.brunodobric.gymapp.widgets.WidgetSnapshot

/** Tekst tjedna: "3 od 4 ovaj tjedan" s ciljem, inače broj treninga. */
internal fun Context.weekText(week: WidgetSnapshot.Week): String {
    val goal = week.goal
    return if (goal != null) getString(R.string.glance_week_goal, week.sessions, goal)
    else resources.getQuantityString(R.plurals.glance_week_sessions, week.sessions, week.sessions)
}

/** Naslov prikaza (odmor, trening u tijeku, sljedeći trening ili ništa zakazano). */
internal fun Context.glanceTitle(kind: WatchGlance.Kind): String = when (kind) {
    WatchGlance.Kind.RESTING -> getString(R.string.rest)
    WatchGlance.Kind.ACTIVE -> getString(R.string.workout_in_progress)
    WatchGlance.Kind.NEXT -> getString(R.string.glance_next)
    WatchGlance.Kind.EMPTY -> getString(R.string.app_name)
}

/** Traži od sustava novi sadržaj pločice i komplikacija kad se promijeni ono što prikazuju. */
internal object GlanceRefresher {
    fun refresh(context: Context) {
        runCatching { TileService.getUpdater(context).requestUpdate(NextWorkoutTileService::class.java) }
        for (service in listOf(
            WorkoutComplicationService::class.java,
            WeekComplicationService::class.java,
            QuickStartComplicationService::class.java,
            BodyWeightComplicationService::class.java,
        )) {
            runCatching {
                ComplicationDataSourceUpdateRequester.create(context, ComponentName(context, service)).requestUpdateAll()
            }
        }
    }
}
