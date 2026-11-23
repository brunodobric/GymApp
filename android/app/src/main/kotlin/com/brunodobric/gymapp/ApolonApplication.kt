package com.brunodobric.gymapp

import android.app.Application
import android.util.Log
import com.brunodobric.gymapp.appwidgets.WidgetRefresher
import com.brunodobric.gymapp.health.HealthConnectSync
import com.brunodobric.gymapp.notifications.ReminderNotifications
import com.brunodobric.gymapp.notifications.ReminderScheduler
import com.brunodobric.gymapp.notifications.RestNotificationScheduler
import com.brunodobric.gymapp.notifications.RestNotifications
import com.brunodobric.gymapp.notifications.WorkoutNotification
import com.brunodobric.gymapp.notifications.WorkoutNotificationUpdater
import com.brunodobric.gymapp.sync.FileSync
import com.brunodobric.gymapp.wear.PhoneWatchSync

class ApolonApplication : Application() {
    /** Zajedničke usluge aplikacije (katalog, kasnije baza), kao `AppServices` na iOS-u. */
    lateinit var services: AppServices
        private set

    /** Obavijest treninga u tijeku; alarm kraja odmora je osvježava. */
    lateinit var workoutNotifications: WorkoutNotificationUpdater
        private set

    /** Podsjetnici rasporeda; ponovno se zakazuju nakon pokretanja telefona i promjene vremena. */
    lateinit var reminders: ReminderScheduler
        private set

    /** Snimka za widgete na početnom zaslonu; osvježava se nakon spremanja i u ponoć. */
    lateinit var widgets: WidgetRefresher
        private set

    /** Upis u Health Connect i čitanje iz njega, kad ga korisnik uključi. */
    lateinit var health: HealthConnectSync
        private set

    /** Sinkronizacija s drugim Android uređajima preko datoteke u pohrani (npr. Google Drive), kad je uključena. */
    lateinit var sync: FileSync
        private set

    /** Veza sa satom (Wear OS) preko Data Layera, kad je sat s aplikacijom uparen. */
    lateinit var watchSync: PhoneWatchSync
        private set

    /**
     * Greška pri otvaranju baze na uređaju; tada se umjesto aplikacije prikazuje `StoreFailureScreen`, a usluge
     * koje čitaju bazu (obavijesti, podsjetnici, widgeti, Health Connect, sinkronizacija, sat) se ne pokreću.
     */
    var storeFailure: Throwable? = null
        private set

    override fun onCreate() {
        super.onCreate()
        services = AppServices(this)
        // Aplikacija se ne ruši pri svakom pokretanju kad se baza ne može otvoriti (kao na iOS-u).
        storeFailure = runCatching { services.store }.exceptionOrNull()
        storeFailure?.let {
            Log.e("Store", "Baza se nije otvorila", it)
            return
        }
        RestNotifications.createChannels(this)
        RestNotificationScheduler(this, services.store).start()
        WorkoutNotification.createChannel(this)
        workoutNotifications = WorkoutNotificationUpdater(this, services.store).also { it.start() }
        ReminderNotifications.createChannel(this)
        reminders = ReminderScheduler(this, services.store).also { it.start() }
        widgets = WidgetRefresher(this, services).also { it.start() }
        health = HealthConnectSync(this, services).also { it.start() }
        sync = FileSync(this, services).also { it.start() }
        watchSync = PhoneWatchSync(this, services).also { it.start() }
    }
}
