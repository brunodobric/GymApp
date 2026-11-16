package com.brunodobric.gymapp.watch

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import com.brunodobric.gymapp.wear.PlannedWorkoutPayload
import com.brunodobric.gymapp.watch.ui.WatchApp

class MainActivity : ComponentActivity() {
    private val app get() = application as WatchApplication

    /** Trening čeka odgovor na dozvole; pokreće se i bez njih (bez pulsa). */
    private var pendingPlan: PlannedWorkoutPayload? = null
    private var pendingMeasure = false

    private val permissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        pendingPlan?.let(app.store::begin)
        pendingPlan = null
        if (pendingMeasure) app.store.phoneRequestedHealthSession()
        pendingMeasure = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WatchApp(store = app.store, health = app.health, onStart = ::start)
        }
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        app.refreshFromPhone()
    }

    private fun start(plan: PlannedWorkoutPayload) {
        pendingPlan = plan
        permissions.launch(app.health.permissions)
    }

    /** Obavijest "Mjeri puls" (zahtjev s mobitela dok aplikacija nije bila na zaslonu). */
    private fun handle(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_MEASURE, false) != true) return
        intent.removeExtra(EXTRA_MEASURE)
        pendingMeasure = true
        permissions.launch(app.health.permissions)
    }

    companion object {
        const val EXTRA_MEASURE = "measure"
    }
}
