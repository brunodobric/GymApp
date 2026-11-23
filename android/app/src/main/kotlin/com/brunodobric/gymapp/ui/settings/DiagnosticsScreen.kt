package com.brunodobric.gymapp.ui.settings

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Vrsta izlaska procesa koja se prikazuje u dijagnostici; ostali izlasci (korisnik, sustav) se preskaču. */
private enum class ExitKind(val title: Int) {
    CRASH(R.string.diagnostics_crashes),
    ANR(R.string.diagnostics_hangs),
    LOW_MEMORY(R.string.diagnostics_low_memory),
    EXCESSIVE_RESOURCES(R.string.diagnostics_excessive_resources),
    ;

    companion object {
        fun of(reason: Int): ExitKind? = when (reason) {
            ApplicationExitInfo.REASON_CRASH, ApplicationExitInfo.REASON_CRASH_NATIVE -> CRASH
            ApplicationExitInfo.REASON_ANR -> ANR
            ApplicationExitInfo.REASON_LOW_MEMORY -> LOW_MEMORY
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> EXCESSIVE_RESOURCES
            else -> null
        }
    }
}

private class ExitEntry(val kind: ExitKind, val at: Instant, val description: String?, val importance: Int)

/** Zadnji izlasci aplikacije koje sustav pamti (`ApplicationExitInfo`, najviše 30). */
private fun loadExits(context: Context): List<ExitEntry> {
    val manager = context.getSystemService(ActivityManager::class.java) ?: return emptyList()
    return runCatching { manager.getHistoricalProcessExitReasons(context.packageName, 0, 30) }.getOrDefault(emptyList())
        .mapNotNull { info ->
            ExitKind.of(info.reason)?.let { ExitEntry(it, Instant.ofEpochMilli(info.timestamp), info.description, info.importance) }
        }
}

/**
 * Postavke > O aplikaciji > Dijagnostika (`DiagnosticsScreen` na iOS-u, gdje su to MetricKit izvještaji): rušenja,
 * zastoji i gašenja zbog memorije ili prekomjernog trošenja koja sustav pamti za aplikaciju. Ostaju na uređaju i
 * ne sadrže treninge; korisnik ih može izvesti i poslati uz prijavu greške, a aplikacija ih sama nikamo ne šalje.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DiagnosticsScreen(onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val entries = remember { loadExits(context) }
    val dates = remember(locale) {
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale).withZone(ZoneId.systemDefault())
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.diagnostics)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            Text(
                stringResource(R.string.diagnostics_intro),
                modifier = Modifier.padding(16.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (entries.isNotEmpty()) {
                SectionHeader(stringResource(R.string.diagnostics_totals))
                ExitKind.entries.forEach { kind ->
                    val count = entries.count { it.kind == kind }
                    if (count > 0) ListItem(headlineContent = { Text(stringResource(kind.title)) }, trailingContent = { Text(count.toString()) })
                }
            }
            SectionHeader(stringResource(R.string.diagnostics_reports))
            if (entries.isEmpty()) {
                Text(
                    stringResource(R.string.diagnostics_empty),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            entries.forEach { entry ->
                ListItem(
                    headlineContent = { Text(stringResource(entry.kind.title)) },
                    supportingContent = {
                        Text(listOfNotNull(dates.format(entry.at), entry.description?.takeIf { it.isNotBlank() }).joinToString("\n"))
                    },
                )
                HorizontalDivider()
            }
            if (entries.isNotEmpty()) {
                val titles = ExitKind.entries.associateWith { stringResource(it.title) }
                val chooserTitle = stringResource(R.string.diagnostics_export)
                ListItem(
                    headlineContent = { Text(chooserTitle, color = MaterialTheme.colorScheme.primary) },
                    modifier = Modifier.clickable {
                        // Običan tekst kroz sustavski izbornik dijeljenja; korisnik bira kamo ide.
                        val text = entries.joinToString("\n\n") { entry ->
                            listOfNotNull(
                                "${titles[entry.kind]} · ${entry.at}",
                                "importance=${entry.importance}",
                                entry.description,
                            ).joinToString("\n")
                        }
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                        runCatching { context.startActivity(Intent.createChooser(send, chooserTitle)) }
                    },
                )
            }
        }
    }
}
