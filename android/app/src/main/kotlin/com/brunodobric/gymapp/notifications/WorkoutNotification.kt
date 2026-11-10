package com.brunodobric.gymapp.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.MainActivity
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.WeightStepSettings
import com.brunodobric.gymapp.training.LiveSetEditor
import com.brunodobric.gymapp.training.LiveSetValue
import com.brunodobric.gymapp.training.LiveWorkoutStatus
import com.brunodobric.gymapp.training.SetField
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.liveStatus
import com.brunodobric.gymapp.training.restDefaults
import java.time.Instant
import java.util.UUID
import kotlin.math.sign

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
    private const val OPEN_APP_REQUEST_CODE = 1005
    internal const val ACTION_CONFIRM = "com.brunodobric.gymapp.CONFIRM_SET"
    internal const val ACTION_ADJUST = "com.brunodobric.gymapp.ADJUST_SET"
    internal const val EXTRA_SET_ID = "setId"
    internal const val EXTRA_FIELD = "field"
    internal const val EXTRA_STEPS = "steps"

    /** Četiri gumba (dva polja, − i +) od ovog broja nadalje. */
    private const val ADJUST_REQUEST_CODE = 1010

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

    /** Intent koji samo otvara aplikaciju (podsjetnici rasporeda: Početna prikazuje sljedeći trening). */
    fun openAppIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            OPEN_APP_REQUEST_CODE,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    internal fun show(
        context: Context,
        name: String,
        startedAt: Instant,
        status: LiveWorkoutStatus,
        values: List<LiveSetValue>,
        now: Instant,
    ) {
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
        val setId = status.nextSetId
        val body = if (next != null) "$text\n$next" else text
        if (setId != null && values.isNotEmpty()) {
            // Proširena obavijest s gumbima − i + uz vrijednosti sljedeće serije, kao Live Activity.
            val expanded = setValuesView(context, body, setId, values)
            builder.setStyle(NotificationCompat.DecoratedCustomViewStyle()).setCustomBigContentView(expanded)
        } else if (next != null) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
        }
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

    private fun setValuesView(context: Context, text: String, setId: UUID, values: List<LiveSetValue>): RemoteViews {
        val view = RemoteViews(context.packageName, R.layout.notification_set_values)
        view.setTextViewText(R.id.set_text, text)
        val rows = listOf(
            SetRow(R.id.row_first, R.id.first_minus, R.id.first_value, R.id.first_plus),
            SetRow(R.id.row_second, R.id.second_minus, R.id.second_value, R.id.second_plus),
        )
        rows.forEachIndexed { index, row ->
            val value = values.getOrNull(index)
            if (value == null) {
                view.setViewVisibility(row.container, View.GONE)
                return@forEachIndexed
            }
            view.setViewVisibility(row.container, View.VISIBLE)
            val label = if (value.unitSymbol.isEmpty()) {
                if (value.field == SetField.REPS) "${value.text} ×" else value.text
            } else {
                "${value.text} ${value.unitSymbol}"
            }
            view.setTextViewText(row.value, label)
            view.setContentDescription(row.minus, context.getString(decreaseLabel(value.field)))
            view.setContentDescription(row.plus, context.getString(increaseLabel(value.field)))
            view.setBoolean(row.minus, "setEnabled", value.canDecrease)
            view.setBoolean(row.plus, "setEnabled", value.canIncrease)
            view.setOnClickPendingIntent(row.minus, adjustIntent(context, setId, value.field, -1, ADJUST_REQUEST_CODE + index * 2))
            view.setOnClickPendingIntent(row.plus, adjustIntent(context, setId, value.field, 1, ADJUST_REQUEST_CODE + index * 2 + 1))
        }
        return view
    }

    private class SetRow(val container: Int, val minus: Int, val value: Int, val plus: Int)

    /** Opisi gumba za TalkBack, isti kao u Live Activityju (`SetValueLabels` na iOS-u). */
    private fun decreaseLabel(field: SetField): Int = when (field) {
        SetField.REPS -> R.string.decrease_reps
        SetField.DURATION -> R.string.decrease_duration
        SetField.DISTANCE -> R.string.decrease_distance
        SetField.WEIGHT, SetField.EXTRA_WEIGHT -> R.string.decrease_weight
    }

    private fun increaseLabel(field: SetField): Int = when (field) {
        SetField.REPS -> R.string.increase_reps
        SetField.DURATION -> R.string.increase_duration
        SetField.DISTANCE -> R.string.increase_distance
        SetField.WEIGHT, SetField.EXTRA_WEIGHT -> R.string.increase_weight
    }

    private fun adjustIntent(context: Context, setId: UUID, field: SetField, steps: Int, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, WorkoutActionReceiver::class.java)
                .setAction(ACTION_ADJUST)
                .putExtra(EXTRA_SET_ID, setId.toString())
                .putExtra(EXTRA_FIELD, field.raw)
                .putExtra(EXTRA_STEPS, steps),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

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
        val nextSet = status.nextSetId?.let { id -> session.exercises.flatMap { it.sets }.firstOrNull { it.id == id } }
        val unit = store.settings().weightUnit
        val values = nextSet?.exercise?.let { LiveSetEditor.values(nextSet, it.inputType, unit) } ?: emptyList()
        // RestTimer nema equals, pa se uspoređuje kraj odmora i je li još u tijeku.
        val rest = status.rest?.endsAt
        val key = listOf(session.id, session.name, session.startedAt, status.copy(rest = null), rest, rest?.isAfter(now), values)
        if (!force && key == shown) return
        shown = key
        WorkoutNotification.show(appContext, session.name, session.startedAt, status, values, now)
    }
}

/** Gumb "Potvrdi seriju": označava seriju završenom kao kvačica na ekranu treninga i pokreće odmor. */
class WorkoutActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as ApolonApplication
        val services = app.services
        val store = services.store
        val id = intent.getStringExtra(WorkoutNotification.EXTRA_SET_ID)?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        val session = store.activeSession()?.takeIf { it.state == SessionState.ACTIVE }
        val set = session?.exercises?.flatMap { it.sets }?.firstOrNull { it.id == id }
        // Serija je u međuvremenu promijenjena na ekranu: obavijest samo dobiva novo stanje.
        if (set == null || set.isCompleted) {
            app.workoutNotifications.refresh(force = true)
            return
        }
        when (intent.action) {
            WorkoutNotification.ACTION_CONFIRM -> {
                val catalog = services.catalog
                val isCompound: (String) -> Boolean? = { key ->
                    if (key.startsWith("c:")) catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND } else null
                }
                runCatching { WorkoutEngine(store).completeSet(set, store.settings().restDefaults, isCompound) }
            }
            WorkoutNotification.ACTION_ADJUST -> {
                // Kao gumbi − i + u Live Activityju: korak težine vježbe, odmor se ne dira.
                val field = SetField.fromRaw(intent.getStringExtra(WorkoutNotification.EXTRA_FIELD)) ?: return
                val steps = intent.getIntExtra(WorkoutNotification.EXTRA_STEPS, 0).sign
                val settings = store.settings()
                val exercise = set.exercise ?: return
                val weightStep = WeightStepSettings.resolver(settings, services.catalog, store.customExercises)(exercise.exercise)
                if (LiveSetEditor.adjust(set, field, steps, settings.weightUnit, weightStep)) {
                    exercise.session?.let { WorkoutEngine(store).touch(it) }
                }
            }
        }
    }
}
