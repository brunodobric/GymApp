package com.brunodobric.gymapp.watch

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.brunodobric.gymapp.wear.PlannedWorkoutPayload
import com.brunodobric.gymapp.wear.plan
import com.brunodobric.gymapp.watch.ui.WatchApp

class MainActivity : ComponentActivity() {
    private val app get() = application as WatchApplication

    /** Trening čeka odgovor na dozvole; pokreće se i bez njih (bez pulsa). */
    private var pendingPlan: PlannedWorkoutPayload? = null
    private var pendingMeasure = false

    /** Dozvole za mjerenje; trening se pokreće bez obzira na odgovor. */
    private fun requestPermissions() {
        val missing = app.health.permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) permissionsAnswered() else requestPermissions(missing.toTypedArray(), PERMISSIONS_REQUEST)
    }

    @Deprecated("ComponentActivity ga i dalje poziva; ActivityResult API traži noviji Fragment od onog iz Play usluga.")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        @Suppress("DEPRECATION")
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSIONS_REQUEST) permissionsAnswered()
    }

    private fun permissionsAnswered() {
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
        requestPermissions()
    }

    /**
     * Gumb Započni na pločici (plan po id-u) i obavijest "Mjeri puls" (zahtjev s mobitela dok aplikacija nije
     * bila na zaslonu).
     */
    private fun handle(intent: Intent?) {
        intent?.getStringExtra(EXTRA_PLAN)?.let { id ->
            intent.removeExtra(EXTRA_PLAN)
            val state = app.store.state.value
            if (state.active == null) state.context.plan(id)?.let(::start)
        }
        if (intent?.getBooleanExtra(EXTRA_MEASURE, false) != true) return
        intent.removeExtra(EXTRA_MEASURE)
        pendingMeasure = true
        requestPermissions()
    }

    companion object {
        const val EXTRA_MEASURE = "measure"
        const val EXTRA_PLAN = "plan"
        private const val PERMISSIONS_REQUEST = 1
    }
}
