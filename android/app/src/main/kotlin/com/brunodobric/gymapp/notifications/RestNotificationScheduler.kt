package com.brunodobric.gymapp.notifications

import android.content.Context
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.training.RestNotificationPolicy
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.liveStatus
import java.time.Instant

/**
 * Nakon svakog spremanja provjerava aktivni trening i zakazuje ili uklanja obavijest o kraju odmora
 * (`scheduleRestNotification` u `WorkoutLiveUpdates` na iOS-u). Alarm se mijenja samo kad se promijeni
 * termin, tekst ili zvuk, pa upis težine ne dira AlarmManager.
 */
class RestNotificationScheduler(context: Context, private val store: GymStore) {
    private val appContext = context.applicationContext
    private var scheduled: Triple<Instant?, String, Boolean>? = null

    fun start() {
        store.addListener { refresh() }
        refresh()
    }

    fun refresh() {
        val session = store.activeSession()?.takeIf { it.state == SessionState.ACTIVE }
        // Postavke se čitaju samo uz trening, kao na iOS-u.
        val settings = session?.let { store.settings() }
        val status = session?.let { WorkoutEngine(store).liveStatus(it) }
        val fireAt = RestNotificationPolicy.fireDate(
            restEndsAt = status?.rest?.endsAt,
            controllingDevice = session?.controllingDevice ?: DeviceRole.PHONE,
            notificationsEnabled = settings?.restNotificationEnabled ?: true,
            isSessionActive = session != null,
            watchAlertsRest = session?.healthRecordedByWatch ?: false,
            now = Instant.now(),
        )
        val name = status?.currentExerciseName
        val body = if (status != null && name != null) {
            appContext.getString(R.string.rest_next_body, name, status.setNumber, status.setCount)
        } else {
            appContext.getString(R.string.rest_next_generic)
        }
        val next = Triple(fireAt, body, settings?.restEndSoundEnabled ?: true)
        if (next == scheduled) return
        scheduled = next
        RestNotifications.schedule(appContext, fireAt, body, next.third)
    }
}
