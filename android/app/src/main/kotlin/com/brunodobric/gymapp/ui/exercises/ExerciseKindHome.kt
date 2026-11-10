package com.brunodobric.gymapp.ui.exercises

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseKind

/** Odredište s početne kataloga: popis jedne vrste, svih ili samo vlastitih vježbi. */
internal sealed interface ExerciseListRoute {
    data class Kind(val kind: ExerciseKind) : ExerciseListRoute
    data object All : ExerciseListRoute
    data object Custom : ExerciseListRoute
}

/**
 * Početna kataloga, kao `ExerciseKindHome` na iOS-u: kartice vrsta (2 × 2, jedan stupac uz vrlo veliki
 * tekst) s mozaikom sličica, broj vježbi i retci "Sve vježbe" i "Moje vježbe".
 */
@Composable
internal fun ExerciseKindHome(
    counts: Map<ExerciseKind, Int>,
    customCount: Int,
    posters: (ExerciseKind) -> List<String>,
    onOpen: (ExerciseListRoute) -> Unit,
    modifier: Modifier = Modifier,
) {
    val columns = if (LocalDensity.current.fontScale >= 1.5f) 1 else 2
    LazyVerticalGrid(
        columns = GridCells.Fixed(columns),
        modifier = modifier,
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(ExerciseKind.entries, key = { it.raw }) { kind ->
            ExerciseKindCard(kind, counts[kind] ?: 0, posters(kind)) { onOpen(ExerciseListRoute.Kind(kind)) }
        }
        item(span = { GridItemSpan(maxLineSpan) }, key = "links") {
            Card(Modifier.padding(top = 8.dp)) {
                LinkRow(stringResource(R.string.all_exercises), counts.values.sum()) { onOpen(ExerciseListRoute.All) }
                HorizontalDivider(Modifier.padding(start = 16.dp))
                LinkRow(stringResource(R.string.my_exercises), customCount) { onOpen(ExerciseListRoute.Custom) }
            }
        }
    }
}

@Composable
private fun LinkRow(title: String, count: Int, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(count.toString(), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(onClick = onClick),
    )
}

/** Kartica vrste: četiri sličice u kvadratu, naziv i broj vježbi. */
@Composable
private fun ExerciseKindCard(kind: ExerciseKind, count: Int, posters: List<String>, onClick: () -> Unit) {
    val title = stringResource(kindTitle(kind))
    val countText = pluralStringResource(R.plurals.exercise_count, count, count)
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().clearAndSetSemantics {
            contentDescription = "$title, $countText"
            role = Role.Button
        },
    ) {
        Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Mosaic(kind, posters)
            Column(Modifier.padding(start = 4.dp, end = 4.dp, bottom = 4.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                Text(countText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** 2 × 2 sličice. Bez MoveKit dodatka (manje od četiri sličice) stoji simbol vrste. */
@Composable
private fun Mosaic(kind: ExerciseKind, posters: List<String>) {
    val shape = RoundedCornerShape(8.dp)
    if (posters.size == 4) {
        Column(Modifier.clip(shape), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            posters.chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    row.forEach { ExercisePosterTile(it, Modifier.weight(1f)) }
                }
            }
        }
    } else {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clip(shape)
                .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                painterResource(kindIcon(kind)),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(40.dp),
            )
        }
    }
}
