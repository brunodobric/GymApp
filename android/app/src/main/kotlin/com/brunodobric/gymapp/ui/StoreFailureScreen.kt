package com.brunodobric.gymapp.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.data.SqliteRecordPersistence
import com.brunodobric.gymapp.model.StoreRecovery

/**
 * Prikazuje se umjesto aplikacije kad se baza na uređaju ne može otvoriti (`StoreFailureScreen` na iOS-u).
 * Aplikacija se tako ne ruši pri svakom pokretanju, a podaci se ne brišu: korisnik može pričekati popravak
 * ili staru bazu premjestiti u stranu ([StoreRecovery]) i krenuti s praznom.
 */
@Composable
fun StoreFailureScreen(error: Throwable?) {
    val context = LocalContext.current
    var confirmsReset by rememberSaveable { mutableStateOf(false) }
    var movedTo by rememberSaveable { mutableStateOf<String?>(null) }
    var moveFailed by rememberSaveable { mutableStateOf(false) }

    Scaffold { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.store_failure_title), style = MaterialTheme.typography.headlineSmall)
            Text(stringResource(R.string.store_failure_message), style = MaterialTheme.typography.bodyLarge)
            Text(
                stringResource(R.string.store_failure_hint),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            val moved = movedTo
            if (moved != null) {
                Text(stringResource(R.string.store_failure_moved, moved), color = Color(0xFF2E7D32))
            } else {
                OutlinedButton(onClick = { confirmsReset = true }) {
                    Text(stringResource(R.string.store_failure_reset), color = MaterialTheme.colorScheme.error)
                }
            }
            if (moveFailed) Text(stringResource(R.string.store_failure_move_failed), color = MaterialTheme.colorScheme.error)
            error?.let {
                Text(stringResource(R.string.store_failure_details), style = MaterialTheme.typography.titleSmall)
                SelectionContainer {
                    Text(it.toString(), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
                }
            }
        }
    }

    if (confirmsReset) {
        AlertDialog(
            onDismissRequest = { confirmsReset = false },
            title = { Text(stringResource(R.string.store_failure_reset_title)) },
            text = { Text(stringResource(R.string.store_failure_reset_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmsReset = false
                    val database = context.getDatabasePath(SqliteRecordPersistence.DATABASE_NAME)
                    runCatching { StoreRecovery.moveAside(database) }
                        .onSuccess { movedTo = it.name; moveFailed = false }
                        .onFailure { moveFailed = true }
                }) { Text(stringResource(R.string.store_failure_reset_confirm), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmsReset = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}
