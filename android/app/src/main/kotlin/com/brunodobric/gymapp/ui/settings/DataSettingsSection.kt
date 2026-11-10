package com.brunodobric.gymapp.ui.settings

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.annotation.StringRes
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.backup.BackupException
import com.brunodobric.gymapp.backup.BackupImportResult
import com.brunodobric.gymapp.backup.CsvBackup
import com.brunodobric.gymapp.backup.DataReset
import com.brunodobric.gymapp.backup.ForeignWorkoutImport
import com.brunodobric.gymapp.backup.ForeignWorkoutsCsv
import com.brunodobric.gymapp.backup.JsonBackup
import com.brunodobric.gymapp.ui.catalogLanguage
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Vrste izvoza, s istim imenima datoteka kao na iOS-u. */
private enum class ExportKind(val baseName: String, val extension: String) {
    JSON("Apolon-sigurnosna-kopija", "json"),
    HISTORY("Apolon-treninzi", "csv"),
    BODY("Apolon-mjerenja", "csv"),
}

/** Poruka nakon izvoza, uvoza ili brisanja: naslov, tekst i brojevi za tekst. */
private class Message(@StringRes val title: Int, @StringRes val text: Int, vararg val args: Any)

/** Datoteka veća od ovoga se ne uvozi (isto kao na iOS-u). */
private const val MAX_IMPORT_BYTES = 50L * 1024 * 1024

private class ImportTooLarge : Exception()

/**
 * Postavke > Podaci: izvoz (JSON i CSV), uvoz iz datoteke i brisanje svih podataka.
 * Baza se mijenja na glavnoj niti; čitanje i pisanje datoteka ide u pozadini.
 */
@Composable
fun DataSettingsSection(services: AppServices) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = services.store
    val language = catalogLanguage()

    var pendingExport by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<Message?>(null) }
    var foreignPreview by remember { mutableStateOf<ForeignWorkoutImport.Preview?>(null) }
    var showsDeleteStart by remember { mutableStateOf(false) }
    var showsDeleteConfirm by remember { mutableStateOf(false) }

    fun importMessage(result: BackupImportResult) =
        Message(R.string.import_done, R.string.import_done_message, result.added, result.skipped)

    // Vrsta datoteke se zadaje pri stvaranju ugovora, pa JSON i CSV imaju svaki svoj.
    val onExportUri: (Uri?) -> Unit = { uri ->
        val text = pendingExport
        pendingExport = null
        if (uri != null && text != null) {
            scope.launch {
                val written = withContext(Dispatchers.IO) { runCatching { write(context, uri, text) }.isSuccess }
                if (!written) message = Message(R.string.export_failed, R.string.export_write_failed_message)
            }
        }
    }
    val jsonExporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json"), onExportUri)
    val csvExporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv"), onExportUri)

    fun export(kind: ExportKind) {
        val text = try {
            when (kind) {
                ExportKind.JSON -> JsonBackup.export(store, imageData = { exercise ->
                    exercise.imageFile?.let(services.exerciseImages::read)
                })
                ExportKind.HISTORY -> CsvBackup.exportHistory(store)
                ExportKind.BODY -> CsvBackup.exportBody(store)
            }
        } catch (_: Exception) {
            message = Message(R.string.export_failed, R.string.export_failed_message)
            return
        }
        pendingExport = text
        val name = "${kind.baseName}-${LocalDate.now()}.${kind.extension}"
        if (kind == ExportKind.JSON) jsonExporter.launch(name) else csvExporter.launch(name)
    }

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val text = try {
                withContext(Dispatchers.IO) { read(context, uri) }
            } catch (_: ImportTooLarge) {
                message = Message(R.string.import_failed, R.string.import_too_large)
                return@launch
            } catch (_: Exception) {
                message = Message(R.string.import_failed, R.string.import_not_backup)
                return@launch
            }
            message = try {
                if (text.trimStart().startsWith("{")) {
                    importMessage(JsonBackup.import(text, store, services.exerciseImages::save))
                } else if (ForeignWorkoutsCsv.matches(text)) {
                    foreignPreview = ForeignWorkoutImport.preview(text, services.catalog, language, store)
                    null
                } else {
                    importMessage(CsvBackup.importAny(text, store))
                }
            } catch (_: BackupException.NewerVersion) {
                Message(R.string.import_failed, R.string.import_newer_version)
            } catch (error: BackupException.InvalidCsv) {
                Message(R.string.import_failed, R.string.import_invalid_csv, error.line)
            } catch (_: Exception) {
                Message(R.string.import_failed, R.string.import_not_backup)
            }
        }
    }

    Column {
        ActionRow(stringResource(R.string.export_json)) { export(ExportKind.JSON) }
        ActionRow(stringResource(R.string.export_history_csv)) { export(ExportKind.HISTORY) }
        ActionRow(stringResource(R.string.export_body_csv)) { export(ExportKind.BODY) }
        ActionRow(stringResource(R.string.import_from_file)) {
            importer.launch(arrayOf("application/json", "text/*", "application/octet-stream"))
        }
        ActionRow(stringResource(R.string.delete_all_data), destructive = true) { showsDeleteStart = true }
        Text(
            stringResource(R.string.data_footer),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
    }

    foreignPreview?.let { preview ->
        AlertDialog(
            onDismissRequest = { foreignPreview = null },
            title = { Text(stringResource(R.string.foreign_import_title)) },
            text = {
                Text(
                    pluralStringResource(R.plurals.foreign_import_workouts, preview.newWorkouts.size, preview.newWorkouts.size) +
                        "\n" + pluralStringResource(R.plurals.completed_sets, preview.setCount, preview.setCount) +
                        "\n" + pluralStringResource(R.plurals.foreign_import_new_custom, preview.newCustomCount, preview.newCustomCount),
                )
            },
            confirmButton = {
                TextButton(
                    enabled = preview.newWorkouts.isNotEmpty(),
                    onClick = {
                        foreignPreview = null
                        message = try {
                            importMessage(ForeignWorkoutImport.apply(preview, store))
                        } catch (_: Exception) {
                            Message(R.string.import_failed, R.string.import_foreign_failed)
                        }
                    },
                ) { Text(stringResource(R.string.import_action)) }
            },
            dismissButton = { TextButton(onClick = { foreignPreview = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    if (showsDeleteStart) {
        AlertDialog(
            onDismissRequest = { showsDeleteStart = false },
            title = { Text(stringResource(R.string.delete_all_title)) },
            text = { Text(stringResource(R.string.delete_all_message)) },
            confirmButton = {
                TextButton(onClick = {
                    showsDeleteStart = false
                    showsDeleteConfirm = true
                }) { Text(stringResource(R.string.delete_continue), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = {
                    showsDeleteStart = false
                    export(ExportKind.JSON)
                }) { Text(stringResource(R.string.delete_export_first)) }
            },
        )
    }

    if (showsDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showsDeleteConfirm = false },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = { Text(stringResource(R.string.delete_confirm_message)) },
            confirmButton = {
                TextButton(onClick = {
                    showsDeleteConfirm = false
                    message = try {
                        DataReset.deleteAll(store)
                        // Lokalni podaci iz Health Connecta brišu se s ostalima; u Health Connectu ostaju.
                        services.healthLocal.clear()
                        store.healthChanged()
                        Message(R.string.data_deleted, R.string.data_deleted_message)
                    } catch (_: Exception) {
                        Message(R.string.delete_failed, R.string.delete_failed_message)
                    }
                }) { Text(stringResource(R.string.delete_all), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { showsDeleteConfirm = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    message?.let { shown ->
        AlertDialog(
            onDismissRequest = { message = null },
            title = { Text(stringResource(shown.title)) },
            text = { Text(stringResource(shown.text, *shown.args)) },
            confirmButton = { TextButton(onClick = { message = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

@Composable
private fun ActionRow(title: String, destructive: Boolean = false, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        colors = if (destructive) {
            ListItemDefaults.colors(headlineColor = MaterialTheme.colorScheme.error)
        } else {
            ListItemDefaults.colors()
        },
        modifier = Modifier.clickable(onClick = onClick),
    )
}

private fun write(context: Context, uri: Uri, text: String) {
    val stream = context.contentResolver.openOutputStream(uri, "wt") ?: error("Datoteka se ne može otvoriti")
    stream.use { it.write(text.toByteArray(Charsets.UTF_8)) }
}

private fun read(context: Context, uri: Uri): String {
    val stream = context.contentResolver.openInputStream(uri) ?: error("Datoteka se ne može otvoriti")
    return stream.use { input ->
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            output.write(buffer, 0, count)
            if (output.size() > MAX_IMPORT_BYTES) throw ImportTooLarge()
        }
        output.toString(Charsets.UTF_8.name())
    }
}
