package com.brunodobric.gymapp.ui.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.brunodobric.gymapp.R

/**
 * Stanje optimizacije baterije za aplikaciju i put do postavki (docs/android.md, odjeljak 7.4). Neki proizvođači
 * (Samsung, Xiaomi) odgađaju alarme i obavijesti aplikacija koje štede bateriju, pa kraj odmora zakasni. Aplikacija
 * ne traži izuzeće dijaloškim okvirom (dozvola REQUEST_IGNORE_BATTERY_OPTIMIZATIONS je na Google Playu ograničena),
 * nego otvara podatke o aplikaciji, gdje korisnik sam bira "Bez ograničenja".
 */
@Composable
internal fun BatteryOptimizationItem() {
    val context = LocalContext.current
    var unrestricted by remember { mutableStateOf(isUnrestricted(context)) }
    // Povratak iz postavki sustava: stanje se čita iznova.
    LifecycleResumeEffect(Unit) {
        unrestricted = isUnrestricted(context)
        onPauseOrDispose { }
    }
    ListItem(
        modifier = Modifier.clickable { openAppDetails(context) },
        headlineContent = { Text(stringResource(R.string.battery_usage)) },
        supportingContent = {
            Text(
                stringResource(if (unrestricted) R.string.battery_unrestricted else R.string.battery_optimized),
                color = if (unrestricted) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error,
            )
        },
    )
    Footer(stringResource(R.string.battery_footer))
}

private fun isUnrestricted(context: Context): Boolean =
    context.getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(context.packageName) == true

private fun openAppDetails(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
}
