package com.brunodobric.gymapp.ui.body

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.BodyMeasurement
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.MeasurementSource
import com.brunodobric.gymapp.stats.BodyTracking
import com.brunodobric.gymapp.stats.BodyTrackingException
import com.brunodobric.gymapp.ui.LineChart
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightUnit
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Prikaz i unos mjera (`BodyFormat` na iOS-u): težina u jedinici korisnika, ostalo u centimetrima. */
object BodyFormat {
    fun displayValue(value: Double, kind: BodyMeasurementKind, unit: WeightUnit): Double =
        if (kind == BodyMeasurementKind.WEIGHT) WeightConversion.displayValue(value, unit) else value

    fun unitSymbol(kind: BodyMeasurementKind, unit: WeightUnit): String =
        if (kind == BodyMeasurementKind.WEIGHT) unit.symbol else "cm"

    fun text(value: Double, kind: BodyMeasurementKind, unit: WeightUnit): String =
        "${NumberInput.format(displayValue(value, kind, unit))} ${unitSymbol(kind, unit)}"

    fun change(delta: Double, kind: BodyMeasurementKind, unit: WeightUnit): String {
        val shown = displayValue(delta, kind, unit)
        val sign = if (shown > 0) "+" else ""
        return "$sign${NumberInput.format(shown)} ${unitSymbol(kind, unit)}"
    }

    /** Unos u prikazanoj jedinici natrag u kg ili cm. */
    fun storedValue(input: Double, kind: BodyMeasurementKind, unit: WeightUnit): Double =
        if (kind == BodyMeasurementKind.WEIGHT) WeightConversion.kilograms(input, unit) else input
}

/** Mjere u istom redu kao na iOS-u; vlastite mjere dolaze kasnije. */
private val shownKinds = listOf(
    BodyMeasurementKind.WEIGHT,
    BodyMeasurementKind.HEIGHT,
    BodyMeasurementKind.WAIST,
    BodyMeasurementKind.CHEST,
    BodyMeasurementKind.ARM,
    BodyMeasurementKind.LEG,
)

private fun kindTitle(kind: BodyMeasurementKind): Int = when (kind) {
    BodyMeasurementKind.WEIGHT -> R.string.body_weight
    BodyMeasurementKind.HEIGHT -> R.string.body_height
    BodyMeasurementKind.WAIST -> R.string.body_waist
    BodyMeasurementKind.CHEST -> R.string.body_chest
    BodyMeasurementKind.ARM -> R.string.body_arm
    BodyMeasurementKind.LEG -> R.string.body_leg
    BodyMeasurementKind.CUSTOM -> R.string.body_custom
}

/** Tijelo: zadnja vrijednost i promjena svake mjere; dodir otvara povijest mjere. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BodyScreen(services: AppServices, onClose: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val tracking = remember(store) { BodyTracking(store) }
    val unit = store.settings().weightUnit
    var opened by rememberSaveable { mutableStateOf<BodyMeasurementKind?>(null) }

    opened?.let { kind ->
        MeasurementDetailScreen(services, kind, onClose = { opened = null })
        return
    }
    BackHandler(onBack = onClose)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.body)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            shownKinds.forEach { kind ->
                val list = remember(revision, kind) { tracking.measurements(kind) }
                ListItem(
                    modifier = Modifier.clickable { opened = kind },
                    headlineContent = { Text(stringResource(kindTitle(kind))) },
                    trailingContent = {
                        val last = list.lastOrNull()
                        if (last == null) {
                            Text(stringResource(R.string.no_entries), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        } else {
                            Column(horizontalAlignment = Alignment.End) {
                                Text(BodyFormat.text(last.value, kind, unit))
                                if (list.size >= 2) {
                                    Text(
                                        BodyFormat.change(last.value - list.first().value, kind, unit),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    },
                )
                HorizontalDivider()
            }
        }
    }
}

/** Povijest jedne mjere: crta, unosi od najnovijeg (brisanje) i dodavanje nove vrijednosti za danas. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MeasurementDetailScreen(services: AppServices, kind: BodyMeasurementKind, onClose: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val tracking = remember(store) { BodyTracking(store) }
    val unit = store.settings().weightUnit
    val list = remember(revision, kind) { tracking.measurements(kind) }
    val locale = LocalConfiguration.current.locales[0]
    val formatter = remember(locale) {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(ZoneId.systemDefault())
    }
    var adding by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<BodyMeasurement?>(null) }
    BackHandler(onBack = onClose)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(kindTitle(kind))) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    IconButton(onClick = { adding = true }) {
                        Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_entry))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (list.size >= 2) {
                LineChart(list.map { BodyFormat.displayValue(it.value, kind, unit) }, Modifier.fillMaxWidth().height(180.dp))
            }
            if (list.isEmpty()) {
                Text(stringResource(R.string.no_entries_yet), color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Card {
                    list.reversed().forEachIndexed { index, measurement ->
                        if (index > 0) HorizontalDivider()
                        ListItem(
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            headlineContent = { Text(BodyFormat.text(measurement.value, kind, unit)) },
                            supportingContent = {
                                val source = if (measurement.source == MeasurementSource.HEALTH_KIT) {
                                    " · " + stringResource(R.string.from_apple_health)
                                } else {
                                    ""
                                }
                                Text(formatter.format(measurement.date) + source)
                            },
                            trailingContent = {
                                IconButton(onClick = { deleting = measurement }) {
                                    Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete_entry))
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    if (adding) {
        AddMeasurementDialog(
            symbol = BodyFormat.unitSymbol(kind, unit),
            onSave = { input ->
                try {
                    tracking.add(kind, BodyFormat.storedValue(input, kind, unit))
                    adding = false
                    true
                } catch (_: BodyTrackingException) {
                    false
                }
            },
            onDismiss = { adding = false },
        )
    }
    deleting?.let { measurement ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(stringResource(R.string.delete_entry_title)) },
            text = { Text(BodyFormat.text(measurement.value, kind, unit) + " · " + formatter.format(measurement.date)) },
            confirmButton = {
                TextButton(onClick = {
                    tracking.delete(measurement)
                    deleting = null
                }) { Text(stringResource(R.string.delete_entry), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** Nova vrijednost za danas. [onSave] vraća false kad vrijednost nije veća od nule. */
@Composable
private fun AddMeasurementDialog(symbol: String, onSave: (Double) -> Boolean, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<Int?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.new_entry)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = text,
                        onValueChange = {
                            text = it
                            error = null
                        },
                        label = { Text(stringResource(R.string.value)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.weight(1f),
                    )
                    Text(symbol, modifier = Modifier.padding(start = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val input = NumberInput.parse(text)
                error = when {
                    input == null -> R.string.enter_number
                    !onSave(input) -> R.string.value_must_be_positive
                    else -> null
                }
            }) { Text(stringResource(R.string.save)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
