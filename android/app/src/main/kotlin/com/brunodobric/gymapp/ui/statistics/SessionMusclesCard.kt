package com.brunodobric.gymapp.ui.statistics

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.stats.LoadScale
import com.brunodobric.gymapp.stats.RegionSets
import com.brunodobric.gymapp.stats.SessionRegions
import java.text.NumberFormat

/**
 * Mišići jednog treninga (`SessionMusclesSection` na iOS-u): tijelo sprijeda i straga obojeno prema broju tvrdih
 * serija po regiji (fiksna skala `LoadScale.sessionLevel`) i popis mišića, glavni i oni koji pomažu. Dodir mišića
 * na tijelu označi redak, a dodir retka označi mišić. Trening bez tvrde serije nema karticu.
 *
 * [weekSets]: tvrde serije po regiji u tjednu treninga (sažetak nakon treninga), prazno kad se ne prikazuju.
 */
@Composable
internal fun SessionMusclesCard(services: AppServices, session: Session, revision: Long, weekSets: Map<String, Double> = emptyMap()) {
    val store = services.store
    val sets = remember(revision, session.id) {
        SessionRegions.sets(session, ExerciseInfoBuilder.provider(services.catalog, store.customExercises))
    }
    if (sets.isEmpty()) return
    val heatmap = remember(sets) { SessionRegions.heatmap(sets) }
    val (primary, assisting) = remember(sets) { SessionRegions.split(sets) }
    val female = store.settings().bodyMapFemale
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    val locale = LocalConfiguration.current.locales[0]
    val number = remember(locale) { NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 1 } }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.session_muscles), style = MaterialTheme.typography.titleMedium)
            if (services.bodyMap.isNotEmpty()) {
                val names = primary.map { stringResource(regionTitle(it.region)) }.joinToString(", ")
                val description = stringResource(R.string.session_muscles_description, names)
                Row(
                    Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = description },
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    listOf(false, true).forEach { back ->
                        BodyFigure(services.bodyMap, female, back, heatmap, selected, onSelect = { selected = it }, modifier = Modifier.weight(1f))
                    }
                }
            }
            if (primary.isNotEmpty()) {
                Text(stringResource(R.string.primary_muscles), style = MaterialTheme.typography.titleSmall)
                primary.forEach { MuscleRow(it, selected == it.region, weekSets, number) { selected = if (selected == it.region) null else it.region } }
            }
            if (assisting.isNotEmpty()) {
                Text(stringResource(R.string.assisting_muscles), style = MaterialTheme.typography.titleSmall)
                assisting.forEach { MuscleRow(it, selected == it.region, weekSets, number) { selected = if (selected == it.region) null else it.region } }
            }
            Text(
                stringResource(R.string.session_muscles_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Redak mišića: naziv, glavne i pomoćne serije (i serije u tjednu), razina u četiri stupnja i broj serija. */
@Composable
private fun MuscleRow(load: RegionSets, isSelected: Boolean, weekSets: Map<String, Double>, number: NumberFormat, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    val parts = buildList {
        if (load.primarySets > 0) add(stringResource(R.string.primary_sets_count, load.primarySets))
        if (load.secondarySets > 0) add(stringResource(R.string.assisting_sets_count, load.secondarySets))
        weekSets[load.region]?.takeIf { it > 0 }?.let { add(stringResource(R.string.this_week_sets, number.format(it))) }
    }
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(if (isSelected) accent.copy(alpha = 0.12f) else androidx.compose.ui.graphics.Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(regionTitle(load.region)), fontWeight = if (isSelected) FontWeight.SemiBold else null)
            if (parts.isNotEmpty()) {
                Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            val idle = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f)
            for (step in 1..LoadScale.MAXIMUM_LEVEL) {
                Box(
                    Modifier.size(width = 10.dp, height = 14.dp).clip(RoundedCornerShape(3.dp))
                        .background(if (step <= load.level) heatColor(LoadScale.intensity(step), accent, idle) else idle),
                )
            }
        }
        Text(
            number.format(load.weightedSets),
            Modifier.widthIn(min = 28.dp),
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.End,
        )
    }
}
