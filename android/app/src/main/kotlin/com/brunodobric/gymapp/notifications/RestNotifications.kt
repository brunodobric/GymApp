package com.brunodobric.gymapp.notifications

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.R
import java.time.Instant

/**
 * Lokalna obavijest o kraju odmora (`RestNotifications` na iOS-u). Kada se zakazuje, odlučuje
 * `RestNotificationPolicy` (core/training). Alarm budi [RestAlarmReceiver], koji obavijest prikazuje samo
 * kad ekran treninga nije pred korisnikom, jer ekran treninga sam javlja kraj odmora zvukom i vibracijom.
 */
object RestNotifications {
    private const val CHANNEL_SOUND = "rest_end"
    private const val CHANNEL_SILENT = "rest_end_silent"
    private const val NOTIFICATION_ID = 1001
    private const val REQUEST_CODE = 1001
    internal const val EXTRA_BODY = "body"
    internal const val EXTRA_SOUND = "sound"

    /** Dva kanala jer se zvuk kanala ne može mijenjati nakon što je stvoren. */
    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_SOUND, context.getString(R.string.rest_end), NotificationManager.IMPORTANCE_HIGH),
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_SILENT, context.getString(R.string.rest_channel_silent), NotificationManager.IMPORTANCE_HIGH)
                .apply { setSound(null, null) },
        )
    }

    /**
     * Zakazuje obavijest za [fireAt], a bez termina uklanja zakazanu. Svaki poziv zamjenjuje prethodni
     * alarm, pa +10 / −10 premješta obavijest na novi trenutak.
     */
    fun schedule(context: Context, fireAt: Instant?, body: String, soundEnabled: Boolean) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, RestAlarmReceiver::class.java)
            .putExtra(EXTRA_BODY, body)
            .putExtra(EXTRA_SOUND, soundEnabled)
        val pending = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarms.cancel(pending)
        if (fireAt == null || !fireAt.isAfter(Instant.now())) return
        val millis = fireAt.toEpochMilli()
        // Točan alarm kad ga sustav dopušta; inače prozor od nekoliko sekundi, za koji dopuštenje ne treba.
        if (alarms.canScheduleExactAlarms()) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pending)
        } else {
            alarms.setWindow(AlarmManager.RTC_WAKEUP, millis, WINDOW_MILLIS, pending)
        }
    }

    /** Uklanja i prikazanu obavijest, npr. kad korisnik otvori ekran treninga. */
    fun dismiss(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    /** Treba li tražiti dopuštenje za obavijesti (Android 13 i noviji). */
    fun needsPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    internal fun show(context: Context, body: String, soundEnabled: Boolean) {
        if (needsPermission(context)) return
        val open = WorkoutNotification.openWorkoutIntent(context, REQUEST_CODE)
        val notification = NotificationCompat.Builder(context, if (soundEnabled) CHANNEL_SOUND else CHANNEL_SILENT)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.rest_over))
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Dopuštenje je povučeno između provjere i prikaza.
        }
    }

    private const val WINDOW_MILLIS = 5_000L
}

/** Budi se kad odmor istekne i prikazuje obavijest, osim kad je ekran treninga otvoren. */
class RestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Odbrojavanje u obavijesti treninga se vraća na trajanje treninga.
        (context.applicationContext as? ApolonApplication)?.workoutNotifications?.refresh(force = true)
        if (WorkoutScreenPresence.isVisible) return
        val body = intent.getStringExtra(RestNotifications.EXTRA_BODY) ?: context.getString(R.string.rest_next_generic)
        RestNotifications.show(context, body, intent.getBooleanExtra(RestNotifications.EXTRA_SOUND, true))
    }
}

/**
 * Je li ekran aktivnog treninga pred korisnikom (otvoren i aplikacija u prvom planu). Dok jest, on sam javlja
 * kraj odmora, pa se obavijest ne prikazuje. Brojač, kao na iOS-u.
 */
object WorkoutScreenPresence {
    @Volatile private var count = 0

    val isVisible: Boolean get() = count > 0

    @Synchronized fun appeared() { count += 1 }

    @Synchronized fun disappeared() { count = maxOf(0, count - 1) }
}
