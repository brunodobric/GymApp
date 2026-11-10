package com.brunodobric.gymapp.ui.statistics

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.stats.ReviewLevel
import com.brunodobric.gymapp.stats.Suggestion
import com.brunodobric.gymapp.stats.WeeklyReview
import java.text.NumberFormat
import java.util.Locale

/**
 * Savjeti za zadnja 4 tjedna (`WeeklyReviewCard` na iOS-u): ocjena četiri dijela (snaga, volumen, redovitost,
 * napor) i prijedlozi za dalje. Brojke iza ocjena su na svojim karticama, pa uz ocjenu stoji samo uputa kad
 * podataka nema.
 */
@Composable
internal fun WeeklyReviewCard(review: WeeklyReview, suggestions: List<Suggestion>, locale: Locale) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.tips), style = MaterialTheme.typography.titleMedium)
            Row(Modifier.fillMaxWidth()) {
                Secondary(stringResource(R.string.last_four_weeks), Modifier.weight(1f))
                if (review.ratedCount > 0) {
                    Secondary(stringResource(R.string.review_good_count, review.goodCount, review.ratedCount))
                }
            }
            LevelRow(R.string.review_strength, review.strength.level, R.string.review_strength_hint)
            LevelRow(R.string.review_volume, review.volume.level, R.string.review_volume_hint)
            LevelRow(R.string.review_consistency, review.consistency.level, null)
            LevelRow(R.string.effort, review.effort.level, R.string.review_effort_hint)
            if (suggestions.isNotEmpty()) {
                HorizontalDivider()
                val context = LocalContext.current
                suggestions.forEach { suggestion ->
                    val (title, detail) = suggestionText(context, suggestion, locale)
                    Column(Modifier.semantics(mergeDescendants = true) {}) {
                        Text(title, style = MaterialTheme.typography.titleSmall)
                        Secondary(detail)
                    }
                }
            }
            Text(
                stringResource(R.string.tips_disclaimer),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.outline,
            )
        }
    }
}

@Composable
private fun LevelRow(title: Int, level: ReviewLevel, hint: Int?) {
    val titleText = stringResource(title)
    val levelText = stringResource(levelTitle(level))
    Row(
        Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "$titleText: $levelText" },
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        LevelDot(level, Modifier.padding(top = 4.dp))
        Column(Modifier.weight(1f)) {
            Row {
                Text(titleText, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                Text(levelText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (level == ReviewLevel.NO_DATA && hint != null) Secondary(stringResource(hint))
        }
    }
}

/** Krug u boji ocjene; bez podataka samo obrub. */
@Composable
private fun LevelDot(level: ReviewLevel, modifier: Modifier = Modifier) {
    val shape = CircleShape
    val base = modifier.size(14.dp)
    when (level) {
        ReviewLevel.NO_DATA -> Box(base.border(2.dp, MaterialTheme.colorScheme.outline, shape))
        else -> Box(base.background(levelColor(level), shape))
    }
}

private fun levelColor(level: ReviewLevel): Color = when (level) {
    ReviewLevel.GOOD -> Color(0xFF34C759)
    ReviewLevel.FAIR -> Color(0xFFFFCC00)
    ReviewLevel.ATTENTION -> Color(0xFFFF9500)
    ReviewLevel.NO_DATA -> Color.Gray
}

private fun levelTitle(level: ReviewLevel): Int = when (level) {
    ReviewLevel.GOOD -> R.string.review_good
    ReviewLevel.FAIR -> R.string.review_fair
    ReviewLevel.ATTENTION -> R.string.review_attention
    ReviewLevel.NO_DATA -> R.string.review_no_data
}

/** Naslov i objašnjenje prijedloga s izvorom, kao `Suggestion.text` na iOS-u. */
private fun suggestionText(context: android.content.Context, suggestion: Suggestion, locale: Locale): Pair<String, String> =
    when (suggestion) {
        is Suggestion.Deload -> context.getString(R.string.suggestion_deload) to
            context.getString(R.string.suggestion_deload_detail, suggestion.exercises)
        is Suggestion.FewerDays -> {
            val average = NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 1 }.format(suggestion.sessionsPerWeek)
            context.getString(R.string.suggestion_fewer_days) to
                context.getString(R.string.suggestion_fewer_days_detail, average, suggestion.planned)
        }
        is Suggestion.AddSets -> context.getString(R.string.suggestion_add_sets, context.getString(regionTitle(suggestion.region))) to
            context.getString(R.string.suggestion_add_sets_detail, suggestion.exerciseName)
        is Suggestion.ReduceVolume -> context.getString(R.string.suggestion_reduce_volume, context.getString(regionTitle(suggestion.region))) to
            context.getString(R.string.suggestion_reduce_volume_detail, suggestion.exerciseName)
        is Suggestion.IncreaseLoad -> context.getString(R.string.suggestion_increase_load, suggestion.exerciseName) to
            context.getString(R.string.suggestion_increase_load_detail)
        is Suggestion.MissedMuscle -> context.getString(R.string.suggestion_missed_muscle, context.getString(regionTitle(suggestion.region)), suggestion.days) to
            context.getString(R.string.suggestion_missed_muscle_detail)
    }
