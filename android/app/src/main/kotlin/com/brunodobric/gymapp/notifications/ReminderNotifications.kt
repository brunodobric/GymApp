package com.brunodobric.gymapp.notifications

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.planning.PlannedReminder
import com.brunodobric.gymapp.planning.ReminderBuilder
import java.time.Instant

/**
 * Lokalni podsjetnici rasporeda (`ReminderScheduler` na iOS-u). Termine računa `ReminderBuilder`
 * (core/planning): bez podsjetnika tijekom aktivnog treninga i na dan kad je trening iz rasporeda već odrađen.
 * Svaki podsjetnik je jedan alarm; [ReminderAlarmReceiver] prikazuje obavijest.
 */
object ReminderNotifications {
    private const val CHANNEL = "reminders"
    private const val FIRST_REQUEST_CODE = 2000

    /** Najviše toliko alarma odjednom; dovoljno za dva tjedna fiksnih dana u nekoliko rasporeda. */
    internal const val MAX_ALARMS = 50
    internal const val EXTRA_TITLE = "title"
    internal const val EXTRA_BODY = "body"
    internal const val EXTRA_ID = "id"

    fun createChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, context.getString(R.string.schedule_reminders), NotificationManager.IMPORTANCE_DEFAULT),
        )
    }

    /** Briše sve zakazane podsjetnike i zakazuje [reminders] (najviše [MAX_ALARMS]). */
    fun schedule(context: Context, reminders: List<PlannedReminder>) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val now = Instant.now()
        val upcoming = reminders.filter { it.fireDate.isAfter(now) }.sortedBy { it.fireDate }.take(MAX_ALARMS)
        for (index in 0 until MAX_ALARMS) {
            val reminder = upcoming.getOrNull(index)
            val intent = Intent(context, ReminderAlarmReceiver::class.java)
            if (reminder != null) {
                intent.putExtra(EXTRA_TITLE, reminder.scheduleName)
                    .putExtra(EXTRA_BODY, body(context, reminder))
                    .putExtra(EXTRA_ID, reminder.identifier)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                FIRST_REQUEST_CODE + index,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarms.cancel(pending)
            if (reminder == null) continue
            // Podsjetnik ne mora stići u sekundu: prozor od 10 minuta ne traži dopuštenje za točne alarme.
            alarms.setWindow(AlarmManager.RTC_WAKEUP, reminder.fireDate.toEpochMilli(), WINDOW_MILLIS, pending)
        }
    }

    private fun body(context: Context, reminder: PlannedReminder): String =
        reminder.workoutName?.let { context.getString(R.string.reminder_body_workout, it) }
            ?: context.getString(R.string.reminder_body)

    internal fun show(context: Context, id: String, title: String, body: String) {
        if (RestNotifications.needsPermission(context)) return
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(WorkoutNotification.openAppIntent(context))
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(id, 0, notification)
        } catch (_: SecurityException) {
            // Dopuštenje je povučeno između provjere i prikaza.
        }
    }

    private const val WINDOW_MILLIS = 10 * 60_000L
}

/**
 * Nakon svakog spremanja ponovno računa podsjetnike, kao `ReminderScheduler.refresh` na iOS-u nakon izmjene
 * rasporeda i početka ili kraja treninga. Alarmi se mijenjaju samo kad se promijeni popis podsjetnika.
 */
class ReminderScheduler(context: Context, private val store: GymStore) {
    private val appContext = context.applicationContext
    private var scheduled: List<Pair<String, String?>>? = null

    fun start() {
        store.addListener { refresh() }
        refresh()
    }

    /** [force] nakon ponovnog pokretanja telefona ili promjene vremena, kad su alarmi izgubljeni ili pomaknuti. */
    fun refresh(force: Boolean = false) {
        val enabled = store.settings().notificationsEnabled
        val reminders = if (enabled) runCatching { ReminderBuilder(store).reminders() }.getOrDefault(emptyList()) else emptyList()
        val key = reminders.map { it.identifier to it.workoutName }
        if (!force && key == scheduled) return
        scheduled = key
        ReminderNotifications.schedule(appContext, reminders)
    }
}

/** Budi se u termin podsjetnika. Tijekom treninga ne prikazuje ništa (alarm je mogao ostati od prije). */
class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as? ApolonApplication ?: return
        val id = intent.getStringExtra(ReminderNotifications.EXTRA_ID) ?: return
        if (app.services.store.activeSession() != null) return
        val title = intent.getStringExtra(ReminderNotifications.EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(ReminderNotifications.EXTRA_BODY) ?: context.getString(R.string.reminder_body)
        ReminderNotifications.show(context, id, title, body)
    }
}

/**
 * Ponovno pokretanje telefona briše alarme, a promjena vremena ili zone ih pomiče. Pokretanje procesa već
 * zakazuje podsjetnike (`ApolonApplication`), ovdje se to radi ponovno, za svaki slučaj.
 */
class ReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> (context.applicationContext as? ApolonApplication)?.reminders?.refresh(force = true)
        }
    }
}
