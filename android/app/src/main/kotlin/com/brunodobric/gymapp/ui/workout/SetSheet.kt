package com.brunodobric.gymapp.ui.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.EffortScale
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.ui.theme.success
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightUnit
import com.brunodobric.gymapp.units.WheelOptions
import kotlin.math.abs
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/**
 * Unos serije u donjem listu (kao `WheelInputField` na iOS-u, prema prijedlogu dizajna): vrsta serije, prošli
 * put, kotačići za težinu i ponavljanja, napor i dvije radnje. Kotačić mijenja samo nacrt; u seriju (i bazu)
 * vrijednosti idu tek na "Spremi" ili "Potvrdi seriju". Dodir na označeni broj otvara tipkovnicu.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SetSheet(
    title: String,
    exerciseName: String,
    set: SetLog,
    inputType: ExerciseInputType,
    unit: WeightUnit,
    weightStep: Double,
    effortScale: EffortScale,
    previousText: String?,
    onSave: () -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val locale = LocalConfiguration.current.locales[0]
    val isExtraLoad = inputType == ExerciseInputType.WEIGHTED_BODYWEIGHT || inputType == ExerciseInputType.ASSISTED
    val usesWeight = inputType == ExerciseInputType.WEIGHT_REPS || isExtraLoad
    val storedWeight = if (isExtraLoad) set.extraWeightKg else set.weightKg
    var kind by remember(set.id) { mutableStateOf(set.kind) }
    var rpe by remember(set.id) { mutableStateOf(set.rpe) }
    var weight by remember(set.id) {
        mutableStateOf(storedWeight?.let { WeightConversion.displayValue(it, unit) } ?: WheelOptions.defaultWeight(unit, isExtraLoad))
    }
    var reps by remember(set.id) { mutableStateOf(set.reps ?: WheelOptions.DEFAULT_REPS) }
    // Vrijednost izvan koraka (početna ili upisana tipkovnicom) koju kotačić mora imati na popisu.
    var weightExtra by remember(set.id) { mutableStateOf(weight) }
    var repsExtra by remember(set.id) { mutableStateOf(reps) }

    fun apply() {
        set.kind = kind
        set.rpe = rpe
        if (usesWeight) {
            val kilograms = WeightConversion.kilograms(weight, unit)
            if (isExtraLoad) set.extraWeightKg = kilograms else set.weightKg = kilograms
        }
        set.reps = reps
    }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = MaterialTheme.colorScheme.surfaceContainerHighest) {
        Column(
            Modifier.padding(horizontal = 20.dp).padding(bottom = 16.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(exerciseName, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.ExtraBold)
                }
                val kinds = listOf(SetKind.WORKING, SetKind.WARM_UP)
                SingleChoiceSegmentedButtonRow {
                    kinds.forEachIndexed { index, option ->
                        SegmentedButton(
                            selected = kind == option,
                            onClick = { kind = option },
                            shape = SegmentedButtonDefaults.itemShape(index, kinds.size),
                            icon = {},
                        ) {
                            Text(stringResource(if (option == SetKind.WORKING) R.string.working_short else R.string.kind_warm_up))
                        }
                    }
                }
            }

            previousText?.let { text ->
                Text(
                    stringResource(R.string.previous_value, text.replace("\n", " · ")),
                    Modifier.fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainer)
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (usesWeight) {
                    val options = remember(unit, weightStep, weightExtra) { WheelOptions.weights(unit, weightStep, including = weightExtra) }
                    val sign = when (inputType) {
                        ExerciseInputType.WEIGHTED_BODYWEIGHT -> "+"
                        ExerciseInputType.ASSISTED -> "−"
                        else -> ""
                    }
                    WheelColumn(
                        label = "$sign${unit.symbol}",
                        note = stringResource(R.string.weight_step_note, "${NumberInput.format(weightStep, locale)} ${unit.symbol}"),
                        options = options,
                        selected = weight,
                        format = { NumberInput.format(it, locale) },
                        parse = { NumberInput.parse(it, locale)?.takeIf { value -> value >= 0 } },
                        decimal = true,
                        onSelect = { weight = it },
                        onTyped = {
                            weightExtra = it
                            weight = it
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
                val repOptions = remember(repsExtra) { WheelOptions.reps(including = repsExtra).map(Int::toDouble) }
                WheelColumn(
                    label = stringResource(R.string.reps_label),
                    note = null,
                    options = repOptions,
                    selected = reps.toDouble(),
                    format = { it.toInt().toString() },
                    parse = { it.trim().toIntOrNull()?.takeIf { value -> value >= 0 }?.toDouble() },
                    decimal = false,
                    onSelect = { reps = it.toInt() },
                    onTyped = {
                        repsExtra = it.toInt()
                        reps = it.toInt()
                    },
                    modifier = Modifier.weight(1f),
                )
            }

            EffortChips(effortScale, rpe) { rpe = it }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = {
                        apply()
                        onSave()
                    },
                    modifier = Modifier.weight(1f).height(52.dp),
                ) { Text(stringResource(R.string.save)) }
                if (!set.isCompleted) {
                    Button(
                        onClick = {
                            apply()
                            onConfirm()
                        },
                        modifier = Modifier.weight(2f).height(52.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.success),
                    ) {
                        Icon(Icons.Filled.Check, contentDescription = null, Modifier.size(18.dp))
                        Text(stringResource(R.string.confirm_set), Modifier.padding(start = 8.dp))
                    }
                }
            }
        }
    }
}

/** Napor kao niz gumba: RPE 6–10 ili RIR 5–0. Dodir na odabrani gumb briše ocjenu. */
@Composable
private fun EffortChips(scale: EffortScale, rpe: Double?, onChange: (Double?) -> Unit) {
    val locale = LocalConfiguration.current.locales[0]
    val options = if (scale == EffortScale.RPE) listOf(6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0) else listOf(5.0, 6.0, 7.0, 8.0, 9.0, 10.0)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "${stringResource(R.string.effort)} (${if (scale == EffortScale.RPE) "RPE" else "RIR"})",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            options.forEach { option ->
                val selected = rpe != null && abs(rpe - option) < 0.01
                val text = NumberInput.format(if (scale == EffortScale.RPE) option else 10 - option, locale)
                val shape = RoundedCornerShape(12.dp)
                Box(
                    Modifier.weight(1f)
                        .height(40.dp)
                        .clip(shape)
                        .background(if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer)
                        .clickable { onChange(if (selected) null else option) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = if (selected) FontWeight.ExtraBold else FontWeight.SemiBold,
                        color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
    }
}

/** Naslov stupca, kotačić i napomena ispod njega. */
@Composable
private fun WheelColumn(
    label: String,
    note: String?,
    options: List<Double>,
    selected: Double,
    format: (Double) -> String,
    parse: (String) -> Double?,
    decimal: Boolean,
    onSelect: (Double) -> Unit,
    onTyped: (Double) -> Unit,
    modifier: Modifier,
) {
    var typing by remember { mutableStateOf(false) }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            label.uppercase(LocalConfiguration.current.locales[0]),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        ValueWheel(options, selected, format, onSelect, onTapSelected = { typing = true })
        TextButton(onClick = { typing = true }) { Text(note?.let { "$it · " }.orEmpty() + stringResource(R.string.type_value)) }
    }
    if (typing) {
        var text by remember { mutableStateOf(format(selected)) }
        AlertDialog(
            onDismissRequest = { typing = false },
            title = { Text(label) },
            text = {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = if (decimal) KeyboardType.Decimal else KeyboardType.Number),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    parse(text)?.let(onTyped)
                    typing = false
                }) { Text(stringResource(R.string.done)) }
            },
            dismissButton = { TextButton(onClick = { typing = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

private val ITEM_HEIGHT = 44.dp
private const val VISIBLE_ITEMS = 5

/**
 * Kotačić: popis koji se zaustavlja na vrijednosti u sredini. Odabrana vrijednost je ona koja stoji u
 * sredini; dodir na drugu vrijednost dovodi je u sredinu.
 */
@Composable
private fun ValueWheel(
    options: List<Double>,
    selected: Double,
    format: (Double) -> String,
    onSelect: (Double) -> Unit,
    onTapSelected: () -> Unit,
) {
    val selectedIndex = options.indexOfFirst { abs(it - selected) < 0.001 }
        .takeIf { it >= 0 } ?: WheelOptions.nearest(selected, options)?.let(options::indexOf) ?: 0
    // Uz razmak od dvije vrijednosti iznad i ispod, vrijednost na vrhu popisa stoji u sredini kotačića.
    val state = rememberLazyListState(initialFirstVisibleItemIndex = selectedIndex)
    val scope = rememberCoroutineScope()
    val centered by remember {
        derivedStateOf {
            val info = state.layoutInfo
            val center = (info.viewportStartOffset + info.viewportEndOffset) / 2
            info.visibleItemsInfo.firstOrNull { center >= it.offset && center < it.offset + it.size }?.index
        }
    }

    // Vrijednost upisana tipkovnicom pomiče kotačić na sebe.
    LaunchedEffect(selectedIndex) {
        if (!state.isScrollInProgress && centered != null && centered != selectedIndex) state.animateScrollToItem(selectedIndex)
    }
    val currentSelected by rememberUpdatedState(selected)
    val currentOnSelect by rememberUpdatedState(onSelect)
    LaunchedEffect(state, options) {
        snapshotFlow { centered }.distinctUntilChanged().collect { index ->
            if (index != null && index in options.indices && abs(options[index] - currentSelected) > 0.001) {
                currentOnSelect(options[index])
            }
        }
    }

    Box(
        Modifier.fillMaxWidth()
            .height(ITEM_HEIGHT * VISIBLE_ITEMS)
            .clip(RoundedCornerShape(18.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.fillMaxWidth()
                .padding(horizontal = 8.dp)
                .height(ITEM_HEIGHT + 8.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)),
        )
        LazyColumn(
            state = state,
            flingBehavior = rememberSnapFlingBehavior(state, SnapPosition.Center),
            contentPadding = PaddingValues(vertical = ITEM_HEIGHT * (VISIBLE_ITEMS / 2)),
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxWidth(),
        ) {
            itemsIndexed(options) { index, value ->
                val distance = centered?.let { abs(it - index) } ?: 2
                val text = format(value)
                Box(
                    Modifier.fillMaxWidth()
                        .height(ITEM_HEIGHT)
                        .semantics { contentDescription = text }
                        .clickable {
                            if (index == centered) onTapSelected() else scope.launch { state.animateScrollToItem(index) }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text,
                        fontSize = when (distance) {
                            0 -> 28.sp
                            1 -> 21.sp
                            else -> 17.sp
                        },
                        fontWeight = if (distance == 0) FontWeight.ExtraBold else FontWeight.Normal,
                        color = when (distance) {
                            0 -> MaterialTheme.colorScheme.primary
                            1 -> MaterialTheme.colorScheme.onSurfaceVariant
                            else -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                        },
                    )
                }
            }
        }
    }
}
