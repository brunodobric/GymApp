package com.brunodobric.gymapp.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.MainActivity
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.training.LiveWorkoutStatus
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.liveStatus
import com.brunodobric.gymapp.training.restDefaults
import java.time.Instant
import java.util.UUID

/**
 * Obavijest treninga u tijeku, zamjena za Live Activity s iOS-a. Tiha je i stalna dok trening traje:
 * naziv treninga, trajanje (ili odbrojavanje odmora), trenutna vježba i serija te gumb "Potvrdi seriju".
 * Dodir otvara ekran treninga. Nije foreground service: trening se ne odvija u pozadini, pa obavijest
 * samo prikazuje stanje iz baze, a alarm kraja odmora je u [RestNotifications].
 */
object WorkoutNotification {
    private const val CHANNEL = "workout"
    private const val NOTIFICATION_ID = 1002
    private const val CONFIRM_REQUEST_CODE = 1003
    internal const val OPEN_REQUEST_CODE = 1004
    internal const val ACTION_CONFIRM = "com.brunodobric.gymapp.CONFIRM_SET"
    internal const val EXTRA_SET_ID = "setId"

    /** Extra u intentu za [MainActivity]: otvori ekran treninga. */
    const val EXTRA_OPEN_WORKOUT = "openWorkout"

    fun createChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, context.getString(R.string.workout_in_progress), NotificationManager.IMPORTANCE_LOW)
                .apply {
                    setSound(null, null)
                    setShowBadge(false)
                },
        )
    }

    /** Intent koji otvara aplikaciju na ekranu treninga (i iz obavijesti o kraju odmora). */
    fun openWorkoutIntent(context: Context, requestCode: Int = OPEN_REQUEST_CODE): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_OPEN_WORKOUT, true)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    internal fun show(context: Context, name: String, startedAt: Instant, status: LiveWorkoutStatus, now: Instant) {
        if (RestNotifications.needsPermission(context)) return
        val rest = status.rest?.takeIf { it.endsAt.isAfter(now) }
        val exercise = status.currentExerciseName
        val text = when {
            exercise != null -> context.getString(R.string.workout_notification_set, exercise, status.setNumber, status.setCount)
            status.isAllCompleted -> context.getString(R.string.all_sets_done)
            else -> context.getString(R.string.workout_in_progress)
        }
        val next = status.nextExerciseName?.let { context.getString(R.string.next_exercise_short, it) }
        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (rest != null) context.getString(R.string.workout_notification_rest, name) else name)
            .setContentText(text)
            .setSubText(context.getString(R.string.workout_notification_progress, status.completedSets, status.totalSets))
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setContentIntent(openWorkoutIntent(context))
        // Jedan sat po obavijesti: za odmora odbrojava do kraja, inače broji trajanje treninga.
        if (rest != null) {
            builder.setWhen(rest.endsAt.toEpochMilli()).setChronometerCountDown(true)
        } else {
            builder.setWhen(startedAt.toEpochMilli()).setChronometerCountDown(false)
        }
        if (next != null) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText("$text\n$next"))
        }
        val setId = status.nextSetId
        if (status.canConfirmNextSet && setId != null) {
            val confirm = PendingIntent.getBroadcast(
                context,
                CONFIRM_REQUEST_CODE,
                Intent(context, WorkoutActionReceiver::class.java)
                    .setAction(ACTION_CONFIRM)
                    .putExtra(EXTRA_SET_ID, setId.toString()),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.addAction(0, context.getString(R.string.confirm_set), confirm)
        }
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
            // Dopuštenje je povučeno između provjere i prikaza.
        }
    }

    internal fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }
}

/**
 * Nakon svakog spremanja osvježava obavijest treninga u tijeku (`WorkoutLiveUpdates` na iOS-u). Obavijest
 * se mijenja samo kad se promijeni ono što prikazuje, pa upis težine bez promjene serije ne dira sustav.
 */
class WorkoutNotificationUpdater(context: Context, private val store: GymStore) {
    private val appContext = context.applicationContext
    private var shown: Any? = null

    fun start() {
        store.addListener { refresh() }
        refresh()
    }

    /** [force] kad je odmor istekao: stanje u bazi je isto, ali obavijest se vraća na trajanje treninga. */
    fun refresh(force: Boolean = false) {
        val session = store.activeSession()?.takeIf { it.state == SessionState.ACTIVE }
        if (session == null) {
            if (shown != null) WorkoutNotification.cancel(appContext)
            shown = null
            return
        }
        val now = Instant.now()
        val status = WorkoutEngine(store).liveStatus(session)
        // RestTimer nema equals, pa se uspoređuje kraj odmora i je li još u tijeku.
        val rest = status.rest?.endsAt
        val key = listOf(session.id, session.name, session.startedAt, status.copy(rest = null), rest, rest?.isAfter(now))
        if (!force && key == shown) return
        shown = key
        WorkoutNotification.show(appContext, session.name, session.startedAt, status, now)
    }
}

/** Gumb "Potvrdi seriju": označava seriju završenom kao kvačica na ekranu treninga i pokreće odmor. */
class WorkoutActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WorkoutNotification.ACTION_CONFIRM) return
        val services = (context.applicationContext as ApolonApplication).services
        val store = services.store
        val id = intent.getStringExtra(WorkoutNotification.EXTRA_SET_ID)?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        val session = store.activeSession()?.takeIf { it.state == SessionState.ACTIVE }
        val set = session?.exercises?.flatMap { it.sets }?.firstOrNull { it.id == id }
        // Serija je u međuvremenu promijenjena na ekranu: obavijest samo dobiva novo stanje.
        if (set == null || set.isCompleted) {
            (context.applicationContext as ApolonApplication).workoutNotifications.refresh(force = true)
            return
        }
        val catalog = services.catalog
        val isCompound: (String) -> Boolean? = { key ->
            if (key.startsWith("c:")) catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND } else null
        }
        runCatching { WorkoutEngine(store).completeSet(set, store.settings().restDefaults, isCompound) }
    }
}
