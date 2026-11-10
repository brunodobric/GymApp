package com.brunodobric.gymapp

import android.app.Application
import com.brunodobric.gymapp.appwidgets.WidgetRefresher
import com.brunodobric.gymapp.health.HealthConnectSync
import com.brunodobric.gymapp.notifications.ReminderNotifications
import com.brunodobric.gymapp.notifications.ReminderScheduler
import com.brunodobric.gymapp.notifications.RestNotificationScheduler
import com.brunodobric.gymapp.notifications.RestNotifications
import com.brunodobric.gymapp.notifications.WorkoutNotification
import com.brunodobric.gymapp.notifications.WorkoutNotificationUpdater

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

    override fun onCreate() {
        super.onCreate()
        services = AppServices(this)
        RestNotifications.createChannels(this)
        RestNotificationScheduler(this, services.store).start()
        WorkoutNotification.createChannel(this)
        workoutNotifications = WorkoutNotificationUpdater(this, services.store).also { it.start() }
        ReminderNotifications.createChannel(this)
        reminders = ReminderScheduler(this, services.store).also { it.start() }
        widgets = WidgetRefresher(this, services).also { it.start() }
        health = HealthConnectSync(this, services).also { it.start() }
    }
}
