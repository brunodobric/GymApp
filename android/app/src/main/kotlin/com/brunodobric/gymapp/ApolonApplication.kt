package com.brunodobric.gymapp

import android.app.Application
import com.brunodobric.gymapp.notifications.RestNotificationScheduler
import com.brunodobric.gymapp.notifications.RestNotifications

class ApolonApplication : Application() {
    /** Zajedničke usluge aplikacije (katalog, kasnije baza), kao `AppServices` na iOS-u. */
    lateinit var services: AppServices
        private set

    override fun onCreate() {
        super.onCreate()
        services = AppServices(this)
        RestNotifications.createChannels(this)
        RestNotificationScheduler(this, services.store).start()
    }
}
