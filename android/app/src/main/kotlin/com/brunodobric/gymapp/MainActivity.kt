package com.brunodobric.gymapp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import com.brunodobric.gymapp.notifications.ReminderNotifications
import com.brunodobric.gymapp.notifications.WorkoutNotification
import com.brunodobric.gymapp.ui.RootScreen
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.theme.ApolonTheme
import com.brunodobric.gymapp.ui.theme.isDark
import com.brunodobric.gymapp.widgets.WidgetLink

class MainActivity : ComponentActivity() {
    /** Raste svaki put kad obavijest traži ekran treninga; RootScreen ga tada otvara. */
    private val openWorkoutRequests = mutableIntStateOf(0)

    /** Raspored iz dodirnutog podsjetnika; RootScreen otvara njegov sljedeći trening i briše zahtjev. */
    private val openScheduleRequest = mutableStateOf<String?>(null)

    /** Poveznica iz widgeta (`apolon://…`); RootScreen je otvara i briše zahtjev. */
    private val widgetLinkRequest = mutableStateOf<WidgetLink?>(null)

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
                RootScreen(
                    services,
                    openWorkoutRequests = openWorkoutRequests.intValue,
                    openScheduleRequest = openScheduleRequest.value,
                    onScheduleRequestHandled = { openScheduleRequest.value = null },
                    widgetLink = widgetLinkRequest.value,
                    onWidgetLinkHandled = { widgetLinkRequest.value = null },
                )
            }
        }
    }

    /** Health Connect dopušta čitanje samo dok je aplikacija na zaslonu: novi podaci čitaju se pri svakom povratku. */
    override fun onResume() {
        super.onResume()
        (application as ApolonApplication).health.sync()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        if (intent?.getBooleanExtra(WorkoutNotification.EXTRA_OPEN_WORKOUT, false) == true) {
            openWorkoutRequests.intValue += 1
        }
        intent?.getStringExtra(ReminderNotifications.EXTRA_OPEN_SCHEDULE)?.let { openScheduleRequest.value = it }
        intent?.dataString?.let { WidgetLink.parse(it) }?.let { widgetLinkRequest.value = it }
    }
}
