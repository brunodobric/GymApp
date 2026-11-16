package com.brunodobric.gymapp.watch

import android.app.Application
import android.app.NotificationManager
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.wear.WatchWorkoutStore
import com.brunodobric.gymapp.wear.WearCoding
import com.brunodobric.gymapp.wear.WearPaths
import com.brunodobric.gymapp.wear.WorkoutEvent
import com.brunodobric.gymapp.wear.WorkoutEventDeduplicator
import java.io.File
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/** Aplikacija na satu: stanje treninga, veza s mobitelom i mjerenje, za sve ekrane i usluge. */
class WatchApplication : Application() {
    private val scope = MainScope()
    lateinit var link: DataLayerLink
        private set
    lateinit var health: HealthTracker
        private set
    lateinit var store: WatchWorkoutStore
        private set
    private val deduplicator = WorkoutEventDeduplicator()

    override fun onCreate() {
        super.onCreate()
        link = DataLayerLink(this, scope)
        health = HealthTracker(this, scope).also { it.onBackgroundStartBlocked = ::notifyMeasureRequest }
        val haptics = Haptics(this)
        store = WatchWorkoutStore(link, health, FileStateStorage(File(filesDir, "watch")), scope, haptics::play)
        store.start()
        refreshFromPhone()
    }

    /** Čita zadnji kontekst i snimku s mobitela (Data Layer ih drži i dok mobitel nije u dosegu). */
    fun refreshFromPhone() {
        scope.launch {
            val items = link.currentItems()
            items[WearPaths.CONTEXT]?.let { (_, bytes) -> WearCoding.decodeContext(bytes)?.let(store::handleContext) }
            val phoneSession = items[WearPaths.PHONE_SESSION]?.second?.let(WearCoding::decodeSnapshot)
            store.handlePhoneSession(phoneSession)
            // Zajamčeni događaji s mobitela koji su stigli dok aplikacija nije radila.
            items.filterKeys { it.startsWith(WearPaths.EVENT + "/") }.values.forEach { (uri, bytes) -> receiveEventItem(uri, bytes) }
            if (link.isPhoneReachable()) store.connectionChanged()
        }
    }

    // MARK: Primanje (s glavne niti)

    fun receiveData(path: String, uri: Uri, bytes: ByteArray?) {
        when {
            path == WearPaths.CONTEXT -> bytes?.let(WearCoding::decodeContext)?.let(store::handleContext)
            path == WearPaths.PHONE_SESSION -> store.handlePhoneSession(bytes?.let(WearCoding::decodeSnapshot))
            path.startsWith(WearPaths.EVENT + "/") && bytes != null -> receiveEventItem(uri, bytes)
        }
    }

    fun receiveMessage(path: String, bytes: ByteArray) {
        when (path) {
            WearPaths.EVENT -> WorkoutEvent.decode(bytes)?.let(::receiveEvent)
            WearPaths.HEALTH_REQUEST -> store.phoneRequestedHealthSession()
        }
    }

    fun phoneConnectionChanged() {
        store.connectionChanged()
    }

    private fun receiveEventItem(uri: Uri, bytes: ByteArray) {
        val event = WorkoutEvent.decode(bytes) ?: return
        // Vlastiti događaji ostaju dok ih mobitel ne obriše.
        if (event.origin == DeviceRole.WATCH) return
        receiveEvent(event)
        link.consume(uri)
    }

    private fun receiveEvent(event: WorkoutEvent) {
        if (event.origin != DeviceRole.PHONE || !deduplicator.accept(event)) return
        store.handle(event)
    }

    /** Mobitel je zatražio mjerenje dok aplikacija nije na zaslonu: obavijest je otvara i mjerenje počinje. */
    private fun notifyMeasureRequest() {
        WorkoutService.createChannel(this)
        val notification = NotificationCompat.Builder(this, "workout")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.measure_request_title))
            .setContentText(getString(R.string.measure_request_text))
            .setContentIntent(WorkoutService.openAppIntent(this, measure = true))
            .setAutoCancel(true)
            .build()
        runCatching { getSystemService(NotificationManager::class.java)?.notify(MEASURE_NOTIFICATION_ID, notification) }
    }

    private companion object {
        const val MEASURE_NOTIFICATION_ID = 2
    }
}
