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
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import com.brunodobric.gymapp.wear.WatchGlance
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Usluga u prvom planu dok sat mjeri trening: aplikacija radi i sa spuštenim zapešćem, pa puls stiže, a odmor
 * vibrira na kraju. Trajna aktivnost (Ongoing Activity) drži trening na brojčaniku i u popisu nedavnih, a
 * dodir vraća u aplikaciju.
 */
class WorkoutService : Service() {
    private val scope = MainScope()
    private var observing: Job? = null
    private var isForeground = false
    private var restWakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel(this)
        val app = application as WatchApplication
        val glance = WatchGlance.from(app.store.state.value)
        val started = runCatching {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(glance), ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        }
        if (started.isFailure) {
            stopSelf()
            return START_NOT_STICKY
        }
        isForeground = true
        if (observing == null) {
            observing = scope.launch {
                app.store.state.map(WatchGlance::from).distinctUntilChanged().collect(::show)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        releaseRestWakeLock()
        super.onDestroy()
    }

    private fun show(glance: WatchGlance) {
        if (!isForeground) return
        holdAwakeDuringRest(glance)
        runCatching { getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, notification(glance)) }
    }

    /** Obavijest usluge s trajnom aktivnosti: odbrojavanje odmora ili naziv i trajanje treninga. */
    private fun notification(glance: WatchGlance): Notification {
        val touch = openAppIntent(this)
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(glance.activeName ?: getString(R.string.workout_in_progress))
            .setContentText(getString(R.string.workout_in_progress))
            .setContentIntent(touch)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        OngoingActivity.Builder(this, NOTIFICATION_ID, builder)
            .setStaticIcon(R.drawable.ic_notification)
            .setTouchIntent(touch)
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setStatus(status(glance))
            .build()
            .apply(this)
        return builder.build()
    }

    private fun status(glance: WatchGlance): Status {
        val now = Instant.now()
        val restEnd = glance.restEndsAt
        if (glance.isResting(now) && restEnd != null) {
            return Status.Builder()
                .addTemplate(getString(R.string.ongoing_rest))
                .addPart("rest", Status.TimerPart(elapsedRealtime(restEnd)))
                .build()
        }
        val name = glance.activeName ?: getString(R.string.workout_in_progress)
        val started = glance.activeStartedAt ?: return Status.forPart(Status.TextPart(name))
        return Status.Builder()
            .addTemplate(getString(R.string.ongoing_workout))
            .addPart("name", Status.TextPart(name))
            .addPart("time", Status.StopwatchPart(elapsedRealtime(started)))
            .build()
    }

    /**
     * Dok odmor traje, procesor ostaje budan do kraja odmora (i malo poslije), da vibracija za kraj stigne i sa
     * zatamnjenim zaslonom. Izvan odmora ništa se ne drži, zbog baterije.
     */
    private fun holdAwakeDuringRest(glance: WatchGlance) {
        releaseRestWakeLock()
        val end = glance.restEndsAt ?: return
        val now = Instant.now()
        if (!glance.isResting(now)) return
        val millis = Duration.between(now, end).toMillis() + REST_WAKE_GRACE_MILLIS
        val lock = getSystemService(PowerManager::class.java)?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Apolon:rest") ?: return
        lock.setReferenceCounted(false)
        lock.acquire(millis.coerceAtMost(MAX_REST_WAKE_MILLIS))
        restWakeLock = lock
    }

    private fun releaseRestWakeLock() {
        restWakeLock?.takeIf { it.isHeld }?.release()
        restWakeLock = null
    }

    /** Trenutak u vremenskoj bazi `SystemClock.elapsedRealtime()`, koju koristi trajna aktivnost. */
    private fun elapsedRealtime(instant: Instant): Long =
        SystemClock.elapsedRealtime() - (System.currentTimeMillis() - instant.toEpochMilli())

    companion object {
        private const val CHANNEL_ID = "workout"
        private const val NOTIFICATION_ID = 1
        private const val REST_WAKE_GRACE_MILLIS = 15_000L
        private const val MAX_REST_WAKE_MILLIS = 15 * 60_000L

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
