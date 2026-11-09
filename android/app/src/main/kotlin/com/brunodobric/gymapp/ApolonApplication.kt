package com.brunodobric.gymapp

import android.app.Application

class ApolonApplication : Application() {
    /** Zajedničke usluge aplikacije (katalog, kasnije baza), kao `AppServices` na iOS-u. */
    lateinit var services: AppServices
        private set

    override fun onCreate() {
        super.onCreate()
        services = AppServices(this)
    }
}
