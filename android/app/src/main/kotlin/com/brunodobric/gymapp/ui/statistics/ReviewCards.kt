package com.brunodobric.gymapp.ui.statistics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.stats.Dots
import com.brunodobric.gymapp.stats.DotsScore
import com.brunodobric.gymapp.stats.EffortDistribution
import com.brunodobric.gymapp.stats.IntensityDistribution
import com.brunodobric.gymapp.units.WeightFormatter
import java.text.NumberFormat
import java.util.Locale

/**
 * Napor i intenzitet radnih serija u zadnja 4 tjedna (`EffortIntensityCard` na iOS-u): ponavljanja u rezervi
 * ili udio najbolje procjene 1RM vježbe. Bez izbora korisnika prikazuje se napor kad ima ocijenjenih serija.
 */
@Composable
internal fun EffortIntensityCard(effort: EffortDistribution, intensity: IntensityDistribution) {
    // null = korisnik još nije birao.
    var showsEffortChoice by rememberSaveable { mutableStateOf<Boolean?>(null) }
    val showsEffort = showsEffortChoice ?: (effort.rated > 0)
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.effort_intensity), style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = showsEffort, onClick = { showsEffortChoice = true }, label = { Text(stringResource(R.string.effort)) })
                FilterChip(selected = !showsEffort, onClick = { showsEffortChoice = false }, label = { Text(stringResource(R.string.intensity)) })
            }
            if (showsEffort) {
                if (effort.rated == 0) {
                    Secondary(stringResource(R.string.effort_empty))
                } else {
                    BarChart(listOf("0", "1", "2", "3", "4+").zip(effort.counts))
                    Secondary(stringResource(R.string.effort_footer) + " " + stringResource(R.string.effort_unrated, effort.unrated))
                }
            } else {
                if (intensity.total == 0) {
                    Secondary(stringResource(R.string.intensity_empty))
                } else {
                    BarChart(listOf("< 60 %", "60–75 %", "75–85 %", "> 85 %").zip(intensity.counts))
                    Secondary(stringResource(R.string.intensity_footer))
                }
            }
        }
    }
}

/**
 * DOTS bodovi iz čučnja, potiska s klupe i mrtvog dizanja (`DotsCard` na iOS-u). Prikazuje se kad su upisani
 * spol i tjelesna težina i kad je u zadnjih 12 tjedana rađeno barem jedno od tri dizanja.
 */
@Composable
internal fun DotsCard(score: DotsScore, weight: WeightFormatter, locale: Locale) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.dots_points), style = MaterialTheme.typography.titleMedium)
            score.points?.let { points ->
                Text(
                    NumberFormat.getIntegerInstance(locale).format(Math.round(points)),
                    style = MaterialTheme.typography.displaySmall,
                )
            }
            Dots.lifts.forEach { lift ->
                val kilograms = score.liftsKg[lift]
                Row(Modifier.fillMaxWidth()) {
                    Text(stringResource(liftTitle(lift)), modifier = Modifier.weight(1f))
                    if (kilograms != null) {
                        Text(weight.string(kilograms))
                    } else {
                        Text(stringResource(R.string.not_done), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            score.totalKg?.let { total ->
                Row(Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.total), modifier = Modifier.weight(1f))
                    Text(weight.string(total))
                }
            }
            val explanation = stringResource(R.string.dots_footer, weight.string(score.bodyWeightKg))
            Secondary(if (score.points == null) stringResource(R.string.dots_missing) + " " + explanation else explanation)
        }
    }
}

private fun liftTitle(lift: String): Int = when (lift) {
    "barbell-squat" -> R.string.lift_squat
    "barbell-bench-press" -> R.string.lift_bench
    else -> R.string.lift_deadlift
}

/** Stupci s brojem serija iznad i oznakom ispod, na zajedničkoj skali. */
@Composable
private fun BarChart(entries: List<Pair<String, Int>>) {
    val color = MaterialTheme.colorScheme.primary
    val highest = maxOf(1, entries.maxOfOrNull { it.second } ?: 0)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        entries.forEach { (label, count) ->
            Column(Modifier.weight(1f)) {
                Text(count.toString(), style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                Canvas(Modifier.fillMaxWidth().height(120.dp)) {
                    val height = size.height * count / highest
                    if (height > 0f) {
                        drawRoundRect(
                            color,
                            topLeft = Offset(0f, size.height - height),
                            size = Size(size.width, height),
                            cornerRadius = CornerRadius(6f, 6f),
                        )
                    }
                }
                Text(label, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
internal fun Secondary(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)
}
