package com.brunodobric.gymapp.ui.statistics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.stats.BodyRegion
import com.brunodobric.gymapp.stats.RegionLoad
import com.brunodobric.gymapp.stats.StrengthTrend
import java.text.NumberFormat
import java.util.Locale

/** Razdoblja kartice Mišići u danima: 4 tjedna, 12 tjedana i godina, kao na iOS-u. */
internal val MUSCLE_PERIODS = listOf(28, 84, 365)

/**
 * Mišići: prosjek tvrdih serija tjedno po mišiću sa sivom zonom od 10 do 20 serija i popisom glavnih mišića
 * ispod 5 serija. Glavni mišići uvijek su na popisu (i s nula serija), ostali samo kad imaju serija.
 * Mapa tijela dolazi kasnije.
 */
@Composable
internal fun MusclesCard(days: Int, onDaysChange: (Int) -> Unit, loads: Map<String, RegionLoad>, locale: Locale) {
    val number = NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 1 }
    val rows = BodyRegion.all
        .filter { it in BodyRegion.major || (loads[it]?.weeklySets ?: 0.0) > 0 }
        .map { it to (loads[it]?.weeklySets ?: 0.0) }
        .sortedWith(compareByDescending<Pair<String, Double>> { it.second }.thenBy { it.first })
    val lagging = BodyRegion.major.filter { (loads[it]?.weeklySets ?: 0.0) < 5 }
    val scaleMax = maxOf(22.0, (rows.maxOfOrNull { it.second } ?: 0.0) + 2)

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.muscles), style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MUSCLE_PERIODS.forEach { option ->
                    FilterChip(
                        selected = option == days,
                        onClick = { onDaysChange(option) },
                        label = { Text(stringResource(periodLabel(option))) },
                    )
                }
            }
            val lagNames = lagging.map { stringResource(regionTitle(it)) }
            Text(
                when {
                    loads.isEmpty() -> stringResource(R.string.muscles_empty)
                    lagging.isEmpty() -> stringResource(R.string.muscles_all_ok)
                    else -> stringResource(R.string.muscles_lagging, lagNames.joinToString(", "))
                },
                style = MaterialTheme.typography.bodyMedium,
            )
            rows.forEach { (region, sets) ->
                SetsBar(stringResource(regionTitle(region)), sets, scaleMax, number.format(sets))
            }
            Text(
                stringResource(R.string.muscles_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Jedan redak grafa: naziv, stupac na zajedničkoj skali sa sivom zonom 10 do 20 serija i broj serija. */
@Composable
private fun SetsBar(name: String, sets: Double, scaleMax: Double, value: String) {
    val bar = MaterialTheme.colorScheme.primary
    val zone = MaterialTheme.colorScheme.surfaceVariant
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(name, style = MaterialTheme.typography.bodySmall, modifier = Modifier.width(110.dp))
        Canvas(Modifier.weight(1f).height(14.dp)) {
            val zoneStart = (10 / scaleMax * size.width).toFloat()
            val zoneEnd = (20 / scaleMax * size.width).toFloat()
            drawRect(zone, topLeft = Offset(zoneStart, 0f), size = Size(zoneEnd - zoneStart, size.height))
            val width = (sets / scaleMax * size.width).toFloat().coerceIn(0f, size.width)
            if (width > 0f) {
                drawRoundRect(
                    bar,
                    topLeft = Offset(0f, size.height * 0.2f),
                    size = Size(width, size.height * 0.6f),
                    cornerRadius = CornerRadius(4f, 4f),
                )
            }
        }
        Text(value, style = MaterialTheme.typography.bodySmall, modifier = Modifier.width(32.dp))
    }
}

/** Mjesečna promjena procjene 1RM po mišiću u zadnjih 8 tjedana, s brojem vježbi. Bez podataka se ne prikazuje. */
@Composable
internal fun StrengthTrendCard(trends: List<StrengthTrend>, locale: Locale) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.strength_trend), style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(R.string.strength_trend_caption),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            trends.forEach { trend ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(regionTitle(trend.region)))
                        Text(
                            stringResource(R.string.exercises_count, trend.exercises),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(signedPercent(trend.change, locale), color = changeColor(trend.change))
                }
            }
        }
    }
}

/** Zeleno za rast, crveno za pad, sivo oko nule (`ChangeFormat.color` na iOS-u). */
@Composable
private fun changeColor(change: Double, threshold: Double = 0.005): Color = when {
    change >= threshold -> Color(0xFF2E7D32)
    change <= -threshold -> MaterialTheme.colorScheme.error
    else -> MaterialTheme.colorScheme.onSurfaceVariant
}

private fun periodLabel(days: Int): Int = when (days) {
    28 -> R.string.weeks_4
    84 -> R.string.weeks_12
    else -> R.string.period_year
}

/** Naziv regije tijela (`BodyRegion.title` na iOS-u). */
internal fun regionTitle(region: String): Int = when (region) {
    "chest" -> R.string.muscle_chest
    "shoulders" -> R.string.muscle_shoulders
    "biceps" -> R.string.muscle_biceps
    "triceps" -> R.string.muscle_triceps
    "forearms" -> R.string.muscle_forearms
    "abs" -> R.string.region_abs
    "quads" -> R.string.muscle_quadriceps
    "hamstrings" -> R.string.muscle_hamstrings
    "innerThigh" -> R.string.region_inner_thigh
    "outerThigh" -> R.string.region_outer_thigh
    "traps" -> R.string.muscle_traps
    "upperBack" -> R.string.region_upper_back
    "lats" -> R.string.muscle_lats
    "lowerBack" -> R.string.muscle_lower_back
    "glutes" -> R.string.muscle_glutes
    "calves" -> R.string.muscle_calves
    else -> R.string.muscles
}
