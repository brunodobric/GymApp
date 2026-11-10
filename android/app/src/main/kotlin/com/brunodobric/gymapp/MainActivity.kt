package com.brunodobric.gymapp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableIntStateOf
import com.brunodobric.gymapp.notifications.WorkoutNotification
import com.brunodobric.gymapp.ui.RootScreen
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.theme.ApolonTheme
import com.brunodobric.gymapp.ui.theme.isDark

class MainActivity : ComponentActivity() {
    /** Raste svaki put kad obavijest traži ekran treninga; RootScreen ga tada otvara. */
    private val openWorkoutRequests = mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handle(intent)
        val services = (application as ApolonApplication).services
        setContent {
            // Tema i boja iz postavki; promjena u Postavkama odmah mijenja cijelu aplikaciju.
            rememberStoreRevision(services.store)
            val settings = services.store.settings()
            ApolonTheme(accentRaw = settings.accentColorRaw, darkTheme = settings.theme.isDark()) {
                RootScreen(services, openWorkoutRequests = openWorkoutRequests.intValue)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        if (intent?.getBooleanExtra(WorkoutNotification.EXTRA_OPEN_WORKOUT, false) == true) {
            openWorkoutRequests.intValue += 1
        }
    }
}
