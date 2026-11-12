package com.brunodobric.gymapp.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.sync.FileSync
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Postavke > Sinkronizacija (mjesto iCloud stranice na iOS-u): datoteka u pohrani koju korisnik odabere, npr.
 * Google Drive. Na prvom uređaju se datoteka stvara, a na ostalima se odabire ista.
 */
@Composable
internal fun SyncSettingsSection() {
    val context = LocalContext.current
    val sync = (context.applicationContext as ApolonApplication).sync
    val status by sync.status
    val locale = LocalConfiguration.current.locales[0]
    var confirmsOff by remember { mutableStateOf(false) }

    val create = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        uri?.let(sync::connect)
    }
    val open = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(sync::connect)
    }

    if (!status.isOn) {
        ListItem(
            headlineContent = { Text(stringResource(R.string.sync_create)) },
            supportingContent = { Text(stringResource(R.string.sync_create_detail)) },
            modifier = Modifier.clickable { create.launch(FileSync.FILE_NAME) },
        )
        ListItem(
            headlineContent = { Text(stringResource(R.string.sync_choose)) },
            supportingContent = { Text(stringResource(R.string.sync_choose_detail)) },
            modifier = Modifier.clickable { open.launch(arrayOf("*/*")) },
        )
        Footer(stringResource(R.string.sync_footer))
        return
    }

    ListItem(
        headlineContent = { Text(stringResource(R.string.sync_file)) },
        supportingContent = { Text(status.fileName.orEmpty()) },
    )
    val last = status.lastSync?.let { instant ->
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale)
            .withZone(ZoneId.systemDefault()).format(instant)
    }
    ListItem(
        headlineContent = { Text(stringResource(R.string.sync_last)) },
        supportingContent = {
            val text = when {
                status.isRunning -> stringResource(R.string.sync_running)
                status.error != null -> stringResource(errorText(status.error!!))
                last != null -> last
                else -> stringResource(R.string.sync_never)
            }
            Text(text, color = if (status.error != null && !status.isRunning) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
        },
    )
    if (status.deferred > 0) Footer(stringResource(R.string.sync_deferred))
    ListItem(
        headlineContent = { Text(stringResource(R.string.sync_now)) },
        modifier = Modifier.clickable(enabled = !status.isRunning) { sync.sync() },
    )
    ListItem(
        headlineContent = { Text(stringResource(R.string.sync_choose_other)) },
        modifier = Modifier.clickable { open.launch(arrayOf("*/*")) },
    )
    ListItem(
        headlineContent = { Text(stringResource(R.string.sync_turn_off)) },
        colors = ListItemDefaults.colors(headlineColor = MaterialTheme.colorScheme.error),
        modifier = Modifier.clickable { confirmsOff = true },
    )
    Footer(stringResource(R.string.sync_on_footer))

    if (confirmsOff) {
        AlertDialog(
            onDismissRequest = { confirmsOff = false },
            title = { Text(stringResource(R.string.sync_turn_off_title)) },
            text = { Text(stringResource(R.string.sync_turn_off_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmsOff = false
                    sync.disconnect()
                }) { Text(stringResource(R.string.sync_turn_off), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmsOff = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

private fun errorText(error: FileSync.SyncError): Int = when (error) {
    FileSync.SyncError.UNREADABLE -> R.string.sync_error_unreadable
    FileSync.SyncError.NOT_SYNC_FILE -> R.string.sync_error_not_sync_file
    FileSync.SyncError.NEWER_FORMAT -> R.string.sync_error_newer
    FileSync.SyncError.NO_ACCESS -> R.string.sync_error_access
}
