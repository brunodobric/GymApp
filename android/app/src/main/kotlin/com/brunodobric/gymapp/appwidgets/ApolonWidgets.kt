package com.brunodobric.gymapp.appwidgets

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.Button
import androidx.glance.ButtonDefaults
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider as DayNightColor
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.brunodobric.gymapp.MainActivity
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.ui.theme.AccentPalette
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.widgets.WidgetDates
import com.brunodobric.gymapp.widgets.WidgetLink
import com.brunodobric.gymapp.widgets.WidgetSnapshot
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import java.time.format.TextStyle as DayTextStyle

/**
 * Widgeti na početnom zaslonu (Jetpack Glance), isti kao na iPhoneu: sljedeći trening, ovaj tjedan, težina,
 * zadnji trening i zadnji rekord. Svi čitaju snimku ([widgetSnapshots]) koju slaže [WidgetRefresher].
 * Pozadina je bijela, a u tamnoj temi crna, kao widgeti na iOS-u.
 */
object ApolonWidgets {
    private val all: List<GlanceAppWidget>
        get() = listOf(NextWorkoutWidget(), WeekWidget(), BodyWeightWidget(), LastWorkoutWidget(), RecordWidget())

    suspend fun updateAll(context: Context) {
        all.forEach { runCatching { it.updateAll(context) } }
    }
}

/** Zajedničko učitavanje snimke i crtanje okvira; svaki widget daje samo sadržaj. */
abstract class SnapshotWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = widgetSnapshots(context).load() ?: WidgetSnapshot.EMPTY
        val now = Instant.now()
        provideContent {
            WidgetFrame(link(snapshot)) { Content(snapshot, now) }
        }
    }

    /** Kamo vodi dodir na widget. */
    protected open fun link(snapshot: WidgetSnapshot): WidgetLink = WidgetLink.Home

    @Composable
    protected abstract fun ColumnScope.Content(snapshot: WidgetSnapshot, now: Instant)
}

class NextWorkoutWidget : SnapshotWidget() {
    override fun link(snapshot: WidgetSnapshot) = if (snapshot.activeWorkout != null) WidgetLink.ActiveWorkout else WidgetLink.Home

    @Composable
    override fun ColumnScope.Content(snapshot: WidgetSnapshot, now: Instant) {
        val context = LocalContext.current
        val accent = accent(snapshot)
        val active = snapshot.activeWorkout
        val next = snapshot.nextWorkout
        when {
            active != null -> {
                Heading(context.getString(R.string.workout_in_progress), accent)
                Title(active.name)
                Spacer(GlanceModifier.defaultWeight())
                Secondary(context.getString(R.string.widget_started_at, time(active.startedAt)))
            }
            next != null -> {
                Heading(context.getString(R.string.widget_next), accent)
                Title(next.name)
                Secondary(context.resources.getQuantityString(R.plurals.exercise_count, next.exerciseCount, next.exerciseCount))
                next.exercises.forEach { exercise ->
                    val plan = exercise.summary(snapshot.unit)
                    Secondary(if (plan.isEmpty()) exercise.name else "${exercise.name} · $plan")
                }
                Spacer(GlanceModifier.defaultWeight())
                Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Vertical.CenterVertically) {
                    Secondary(next.scheduleName ?: "", GlanceModifier.defaultWeight())
                    StartButton(accent)
                }
            }
            else -> {
                Heading(context.getString(R.string.app_name), accent)
                Secondary(context.getString(R.string.widget_no_scheduled))
                Spacer(GlanceModifier.defaultWeight())
                Row(GlanceModifier.fillMaxWidth()) {
                    Spacer(GlanceModifier.defaultWeight())
                    StartButton(accent)
                }
            }
        }
    }
}

class WeekWidget : SnapshotWidget() {
    override fun link(snapshot: WidgetSnapshot) = WidgetLink.Week

    @Composable
    override fun ColumnScope.Content(snapshot: WidgetSnapshot, now: Instant) {
        val context = LocalContext.current
        val calendar = StatsCalendar.system()
        val accent = accent(snapshot)
        val week = snapshot.week?.current(now, calendar)
            ?: WidgetSnapshot.Week.empty(calendar.weekInterval(now).start, 0, null, 0, calendar)
        Heading(context.getString(R.string.widget_this_week), accent)
        Row(verticalAlignment = Alignment.Vertical.Bottom) {
            Text(
                week.sessions.toString(),
                style = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Bold, color = primaryText),
            )
            week.goal?.let { goal ->
                Secondary(" " + context.resources.getQuantityString(R.plurals.widget_of_goal, goal, goal))
            }
        }
        Spacer(GlanceModifier.height(6.dp))
        Row(GlanceModifier.fillMaxWidth()) {
            week.days.forEach { day ->
                val isToday = calendar.date(day.date) == calendar.date(now)
                Column(GlanceModifier.defaultWeight(), horizontalAlignment = Alignment.Horizontal.CenterHorizontally) {
                    Box(
                        GlanceModifier.size(20.dp).cornerRadius(10.dp)
                            .background(if (day.isTrained) accent else if (isToday) secondaryText else fill),
                    ) {}
                    Text(
                        calendar.date(day.date).dayOfWeek.getDisplayName(DayTextStyle.NARROW_STANDALONE, Locale.getDefault()),
                        style = TextStyle(fontSize = 11.sp, color = secondaryText),
                    )
                }
            }
        }
        Spacer(GlanceModifier.defaultWeight())
        if (week.streakWeeks > 0) {
            Secondary(context.resources.getQuantityString(R.plurals.widget_weeks_in_row, week.streakWeeks, week.streakWeeks))
        } else if (week.sessions > 0) {
            Secondary("${context.getString(R.string.widget_total)}: ${DurationInput.format(week.totalSeconds)}")
        }
    }
}

class BodyWeightWidget : SnapshotWidget() {
    override fun link(snapshot: WidgetSnapshot) = WidgetLink.BodyWeight

    @Composable
    override fun ColumnScope.Content(snapshot: WidgetSnapshot, now: Instant) {
        val context = LocalContext.current
        val accent = accent(snapshot)
        Heading(context.getString(R.string.body_weight), accent)
        val weight = snapshot.bodyWeight
        if (weight == null) {
            Secondary(context.getString(R.string.widget_log_weight))
            return
        }
        val formatter = WeightFormatter(snapshot.unit)
        Text(formatter.string(weight.latestKg), style = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold, color = primaryText))
        weight.changeKg?.let { change ->
            val sign = if (change > 0) "+" else if (change < 0) "−" else ""
            Secondary(context.getString(R.string.widget_change_30_days, sign + formatter.string(kotlin.math.abs(change))))
        }
        Secondary(relativeDay(context, weight.date, now))
        Spacer(GlanceModifier.defaultWeight())
        val points = weight.normalizedPoints
        if (points.isNotEmpty()) {
            Image(
                ImageProvider(sparkline(points, accentColor(snapshot))),
                contentDescription = null,
                modifier = GlanceModifier.fillMaxWidth().height(36.dp),
            )
        }
    }
}

class LastWorkoutWidget : SnapshotWidget() {
    override fun link(snapshot: WidgetSnapshot) = if (snapshot.lastWorkout != null) WidgetLink.LastWorkout else WidgetLink.Home

    @Composable
    override fun ColumnScope.Content(snapshot: WidgetSnapshot, now: Instant) {
        val context = LocalContext.current
        val accent = accent(snapshot)
        Heading(context.getString(R.string.widget_last_workout), accent)
        val last = snapshot.lastWorkout
        if (last == null) {
            Secondary(context.getString(R.string.widget_no_workouts))
            return
        }
        Title(last.name)
        Secondary(relativeDay(context, last.startedAt, now))
        val figures = listOfNotNull(
            last.durationSeconds?.let(DurationInput::format),
            last.hardSets.takeIf { it > 0 }?.let { context.resources.getQuantityString(R.plurals.set_count, it, it) },
        )
        if (figures.isNotEmpty()) Secondary(figures.joinToString(" · "))
        Spacer(GlanceModifier.defaultWeight())
        last.highlights.forEach { Secondary("${it.exercise}: ${it.value}") }
    }
}

class RecordWidget : SnapshotWidget() {
    override fun link(snapshot: WidgetSnapshot) = snapshot.latestRecord?.session?.let { WidgetLink.Session(it) } ?: WidgetLink.Home

    @Composable
    override fun ColumnScope.Content(snapshot: WidgetSnapshot, now: Instant) {
        val context = LocalContext.current
        val accent = accent(snapshot)
        Heading(context.getString(R.string.records), accent)
        val record = snapshot.latestRecord
        if (record == null) {
            Secondary(context.getString(R.string.widget_no_records))
            return
        }
        Title(record.exercise)
        Text(record.value, style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, color = accent))
        Spacer(GlanceModifier.defaultWeight())
        Secondary(relativeDay(context, record.date, now))
    }
}

class NextWorkoutWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NextWorkoutWidget()
}

class WeekWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = WeekWidget()
}

class BodyWeightWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = BodyWeightWidget()
}

class LastWorkoutWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = LastWorkoutWidget()
}

class RecordWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = RecordWidget()
}

// MARK: Dijelovi

private val widgetBackground = DayNightColor(day = Color.White, night = Color.Black)
private val primaryText = DayNightColor(day = Color(0xFF111111), night = Color.White)
private val secondaryText = DayNightColor(day = Color(0xFF6B6B70), night = Color(0xFF9A9AA0))
private val fill = DayNightColor(day = Color(0xFFE5E5EA), night = Color(0xFF2C2C2E))

private fun accent(snapshot: WidgetSnapshot): ColorProvider {
    val pair = AccentPalette.forRaw(snapshot.accent)
    return DayNightColor(day = pair.light, night = pair.dark)
}

/** Boja krivulje težine: tamnija inačica naglasne boje vidi se na bijeloj i na crnoj pozadini (slika se ne mijenja s temom). */
private fun accentColor(snapshot: WidgetSnapshot): Int = AccentPalette.forRaw(snapshot.accent).dark.toArgb()

/** Poveznica widgeta otvara MainActivity, koja je predaje aplikaciji (`onOpenURL` na iOS-u). */
private fun open(context: Context, link: WidgetLink): Action = actionStartActivity(
    Intent(context, MainActivity::class.java)
        .setAction(Intent.ACTION_VIEW)
        .setData(Uri.parse(link.uri))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
)

@Composable
private fun WidgetFrame(link: WidgetLink, content: @Composable ColumnScope.() -> Unit) {
    val context = LocalContext.current
    Column(
        GlanceModifier.fillMaxSize().appWidgetBackground().cornerRadius(20.dp).background(widgetBackground)
            .padding(14.dp).clickable(open(context, link)),
    ) { content() }
}

@Composable
private fun Heading(text: String, accent: ColorProvider) {
    Text(text, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium, color = accent), maxLines = 1)
}

@Composable
private fun Title(text: String) {
    Text(text, style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold, color = primaryText), maxLines = 2)
}

@Composable
private fun Secondary(text: String, modifier: GlanceModifier = GlanceModifier) {
    Text(text, style = TextStyle(fontSize = 13.sp, color = secondaryText), maxLines = 1, modifier = modifier)
}

/** Gumb ▶ pokreće sljedeći trening (ili nastavlja trening u tijeku), kao na iPhoneu. */
@Composable
private fun StartButton(accent: ColorProvider) {
    val context = LocalContext.current
    Button(
        text = "▶",
        onClick = open(context, WidgetLink.StartWorkout),
        colors = ButtonDefaults.buttonColors(backgroundColor = accent, contentColor = DayNightColor(Color.White, Color.White)),
        modifier = GlanceModifier.width(52.dp),
    )
}

private fun time(instant: Instant): String =
    DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withZone(ZoneId.systemDefault()).format(instant)

/** "Danas", "Jučer", "Prije 3 dana" po kalendarskim danima. */
private fun relativeDay(context: Context, date: Instant, now: Instant): String = when (val days = WidgetDates.daysAgo(date, now)) {
    0 -> context.getString(R.string.widget_today)
    1 -> context.getString(R.string.widget_yesterday)
    else -> context.resources.getQuantityString(R.plurals.widget_days_ago, days, days)
}

/** Krivulja težine kao slika (Glance nema crtanje). Točke su između 0 (najniža) i 1 (najviša). */
private fun sparkline(points: List<Double>, color: Int): Bitmap {
    val width = 300
    val height = 72
    val stroke = 6f
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val path = Path()
    points.forEachIndexed { index, value ->
        val x = stroke + (width - 2 * stroke) * index / (points.size - 1).coerceAtLeast(1)
        val y = stroke + (height - 2 * stroke) * (1 - value).toFloat()
        if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    Canvas(bitmap).drawPath(path, paint)
    return bitmap
}
