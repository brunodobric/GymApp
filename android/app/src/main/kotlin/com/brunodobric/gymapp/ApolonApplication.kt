package com.brunodobric.gymapp

import android.app.Application
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

    override fun onCreate() {
        super.onCreate()
        services = AppServices(this)
        RestNotifications.createChannels(this)
        RestNotificationScheduler(this, services.store).start()
        WorkoutNotification.createChannel(this)
        workoutNotifications = WorkoutNotificationUpdater(this, services.store).also { it.start() }
    }
}
