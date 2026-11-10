package com.brunodobric.gymapp.appwidgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.PersonalRecord
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.widgets.WidgetDates
import com.brunodobric.gymapp.widgets.WidgetSnapshotBuilder
import com.brunodobric.gymapp.widgets.WidgetSnapshotStore
import java.io.File
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Datoteka snimke za widgete u mapi aplikacije. */
internal fun widgetSnapshots(context: Context) = WidgetSnapshotStore(File(context.applicationContext.filesDir, "widgets"))

/**
 * Nakon svakog spremanja baze (s odgodom od sekunde) slaže novu snimku za widgete (`WidgetRefresher` na iOS-u).
 * Widgeti se osvježavaju samo kad se snimka promijeni, i u ponoć, kad se mijenjaju tjedan, "danas" i "prije N dana".
 */
class WidgetRefresher(context: Context, private val services: AppServices) {
    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val pending = Runnable { refresh() }

    fun start() {
        services.store.addListener { schedule() }
        schedule()
    }

    private fun schedule() {
        handler.removeCallbacks(pending)
        handler.postDelayed(pending, DELAY_MILLIS)
    }

    /** [force] u ponoć ili nakon promjene vremena: widgeti se crtaju iznova i kad je snimka ista. */
    fun refresh(force: Boolean = false) {
        val store = services.store
        val settings = store.settings()
        val weight = WeightFormatter(settings.weightUnit)
        val info = ExerciseInfoBuilder.provider(services.catalog, store.customExercises)
        val snapshot = runCatching {
            WidgetSnapshotBuilder(
                store,
                isCardio = ExerciseInfoBuilder.isCardio(info),
                isCompound = { key ->
                    if (key.startsWith("c:")) services.catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND } else null
                },
                recordText = { recordText(appContext, it, weight) },
            ).make()
        }.getOrNull() ?: return
        val changed = runCatching { widgetSnapshots(appContext).save(snapshot) }.getOrDefault(false)
        if (changed || force) scope.launch { ApolonWidgets.updateAll(appContext) }
        scheduleMidnight()
    }

    private fun scheduleMidnight() {
        val alarms = appContext.getSystemService(AlarmManager::class.java) ?: return
        val pending = PendingIntent.getBroadcast(
            appContext, MIDNIGHT_REQUEST_CODE, Intent(appContext, WidgetMidnightReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Nepreciznim alarmom: widget koji se osvježi par minuta nakon ponoći je dovoljno dobar.
        alarms.set(AlarmManager.RTC, WidgetDates.nextMidnight(Instant.now()).toEpochMilli() + 60_000, pending)
    }

    private companion object {
        const val DELAY_MILLIS = 1_000L
        const val MIDNIGHT_REQUEST_CODE = 3000
    }
}

/** Vrijednost rekorda za widget, kao na popisu rekorda: "80 kg × 5", ponavljanja, trajanje ili udaljenost. */
internal fun recordText(context: Context, record: PersonalRecord, weight: WeightFormatter): String = when (record.kind) {
    PRKind.ESTIMATED_ONE_REP_MAX, PRKind.MAX_WEIGHT, PRKind.EXERCISE_VOLUME, PRKind.LOWEST_ASSISTANCE -> weight.string(record.value)
    PRKind.REP_MAX -> "${weight.string(record.value)} × ${record.reps ?: 1}"
    PRKind.MAX_REPS -> context.getString(R.string.reps_short, record.value.toInt())
    PRKind.LONGEST_DURATION -> DurationInput.format(record.value.toInt())
    PRKind.LONGEST_DISTANCE -> if (record.value >= 1000) "${NumberInput.format(record.value / 1000)} km" else "${record.value.toInt()} m"
}

/** U ponoć (i nakon promjene vremena) crta widgete iznova. */
class WidgetMidnightReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        (context.applicationContext as? ApolonApplication)?.widgets?.refresh(force = true)
    }
}
