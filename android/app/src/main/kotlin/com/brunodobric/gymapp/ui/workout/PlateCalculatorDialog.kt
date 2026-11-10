package com.brunodobric.gymapp.ui.workout

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.UserSettings
import com.brunodobric.gymapp.training.PlateCalculator
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightUnit

/**
 * Kalkulator ploča iz serije: koje ploče staviti na svaku stranu šipke. Kao na iOS-u, postavke šipke i ploča
 * čuvaju se u kg, a za funte se koriste uobičajene ploče i šipka u funtama.
 */
@Composable
internal fun PlateCalculatorDialog(initialText: String, unit: WeightUnit, settings: UserSettings, onDismiss: () -> Unit) {
    val locale = LocalConfiguration.current.locales[0]
    var text by rememberSaveable { mutableStateOf(initialText) }
    val kilograms = unit == WeightUnit.KILOGRAMS
    val barbell = if (kilograms) settings.barbellWeightKg else PlateCalculator.DEFAULT_POUND_BARBELL
    val plates = if (kilograms) settings.availablePlatesKg else PlateCalculator.DEFAULT_POUND_PLATES
    val result = NumberInput.parse(text, locale)?.let { PlateCalculator.calculate(it, barbell, plates) }
    fun weight(value: Double) = NumberInput.format(value, locale) + " " + unit.symbol

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.plate_calculator)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text(stringResource(R.string.target_weight)) },
                    suffix = { Text(unit.symbol) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
                PlateRow(stringResource(R.string.barbell), weight(barbell))
                if (result != null) {
                    Text(stringResource(R.string.on_each_side), style = MaterialTheme.typography.titleSmall)
                    when {
                        result.isBelowBar -> Text(
                            stringResource(R.string.plates_below_bar),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        result.perSide.isEmpty() -> Text(stringResource(R.string.plates_bar_only))
                        else -> PlateCalculator.grouped(result.perSide).forEach { item ->
                            PlateRow("${item.count} ×", weight(item.plate))
                        }
                    }
                    if (!result.isExact && !result.isBelowBar) {
                        PlateRow(stringResource(R.string.plates_achieved), weight(result.achievedTotal))
                        Text(
                            stringResource(R.string.plates_not_exact),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.close)) } },
    )
}

@Composable
private fun PlateRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title)
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
