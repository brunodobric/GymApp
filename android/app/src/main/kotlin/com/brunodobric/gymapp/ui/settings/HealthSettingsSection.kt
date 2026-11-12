package com.brunodobric.gymapp.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.clickable
import androidx.compose.material3.ListItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.health.HealthConnect
import com.brunodobric.gymapp.ui.rememberStoreRevision

/**
 * Postavke > Health Connect: uključivanje upisa treninga i težine (`wantsHealthKit`, isto polje kao Zdravlje na
 * iOS-u). Dozvole se traže tek kad korisnik uključi prekidač. Bez Health Connecta nudi se instalacija.
 */
@Composable
internal fun HealthSettingsSection(services: AppServices) {
    val context = LocalContext.current
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    var status by remember { mutableIntStateOf(HealthConnect.status(context)) }
    var granted by remember { mutableStateOf<Boolean?>(null) }
    var checks by remember { mutableIntStateOf(0) }
    var denied by remember { mutableStateOf(false) }

    // Povratak iz Trgovine Play ili postavki Health Connecta: stanje i dozvole se čitaju iznova.
    LifecycleResumeEffect(Unit) {
        status = HealthConnect.status(context)
        checks++
        onPauseOrDispose { }
    }
    LaunchedEffect(status, checks) {
        granted = status == HealthConnectClient.SDK_AVAILABLE && HealthConnect.hasPermissions(context)
    }

    fun enable() {
        store.settings().wantsHealthKit = true
        store.save()
        (context.applicationContext as ApolonApplication).health.sync()
    }

    val request = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { result ->
        val all = result.containsAll(HealthConnect.WRITE_PERMISSIONS)
        granted = all
        denied = !all
        if (all) enable()
    }

    if (status != HealthConnectClient.SDK_AVAILABLE) {
        ListItem(
            headlineContent = { Text(stringResource(R.string.health_install)) },
            modifier = Modifier.clickable { runCatching { context.startActivity(HealthConnect.installIntent()) } },
        )
        Footer(stringResource(R.string.health_install_footer))
        return
    }
    ListItem(
        headlineContent = { Text(stringResource(R.string.health_write_workouts)) },
        trailingContent = {
            Switch(checked = settings.wantsHealthKit && granted == true, onCheckedChange = { on ->
                if (!on) {
                    settings.wantsHealthKit = false
                    store.save()
                } else if (granted == true) {
                    enable()
                } else {
                    request.launch(HealthConnect.PERMISSIONS)
                }
            })
        },
    )
    if (settings.wantsHealthKit && granted == true) {
        // Uvoz inače ide sam pri povratku u aplikaciju; gumb je za slučaj kad korisnik ne želi čekati (kao na iOS-u).
        ListItem(
            headlineContent = { Text(stringResource(R.string.health_import_now)) },
            modifier = Modifier.clickable { (context.applicationContext as ApolonApplication).health.sync() },
        )
    }
    ListItem(
        headlineContent = { Text(stringResource(R.string.health_permissions)) },
        modifier = Modifier.clickable { runCatching { context.startActivity(HealthConnect.settingsIntent()) } },
    )
    Footer(stringResource(if (denied) R.string.health_denied else R.string.health_footer))
}
