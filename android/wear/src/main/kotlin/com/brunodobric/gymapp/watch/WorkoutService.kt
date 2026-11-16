package com.brunodobric.gymapp.watch

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Usluga u prvom planu dok sat mjeri trening: aplikacija radi i sa spuštenim zapešćem, pa puls stiže, a odmor
 * vibrira na kraju. Obavijest vraća u aplikaciju.
 */
class WorkoutService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel(this)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.workout_in_progress))
            .setContentIntent(openAppIntent(this))
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
        val started = runCatching {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        }
        if (started.isFailure) stopSelf()
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL_ID = "workout"
        private const val NOTIFICATION_ID = 1

        /** Vraća false kad sustav ne dopušta pokretanje (aplikacija nije na zaslonu). */
        fun start(context: Context): Boolean = runCatching {
            ContextCompat.startForegroundService(context, Intent(context, WorkoutService::class.java))
        }.isSuccess

        fun stop(context: Context) {
            context.stopService(Intent(context, WorkoutService::class.java))
        }

        fun createChannel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(CHANNEL_ID, context.getString(R.string.workout_channel), NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(channel)
        }

        fun openAppIntent(context: Context, measure: Boolean = false): PendingIntent = PendingIntent.getActivity(
            context, if (measure) 1 else 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(MainActivity.EXTRA_MEASURE, measure),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
