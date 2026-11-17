package com.brunodobric.gymapp.watch.glance

import androidx.compose.ui.graphics.toArgb
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.brunodobric.gymapp.watch.MainActivity
import com.brunodobric.gymapp.watch.R
import com.brunodobric.gymapp.watch.WatchApplication
import com.brunodobric.gymapp.watch.ui.Accent
import com.brunodobric.gymapp.watch.ui.OnAccent
import com.brunodobric.gymapp.wear.WatchGlance
import com.google.common.util.concurrent.ListenableFuture
import java.time.Instant

/**
 * Pločica "Sljedeći trening": sljedeći trening rasporeda s gumbom Započni, ili trening u tijeku s gumbom
 * Nastavi, te napredak tjedna. Sadržaj osvježava [GlanceRefresher] kad se stanje promijeni.
 */
class NextWorkoutTileService : TileService() {
    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> {
        val glance = WatchGlance.from((application as WatchApplication).store.state.value)
        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(layout(glance, Instant.now())))
            .build()
        return immediate(tile)
    }

    override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        immediate(ResourceBuilders.Resources.Builder().setVersion(RESOURCES_VERSION).build())

    private fun <T> immediate(value: T): ListenableFuture<T> = CallbackToFutureAdapter.getFuture { completer ->
        completer.set(value)
        "glance"
    }

    private fun layout(glance: WatchGlance, now: Instant): LayoutElementBuilders.LayoutElement {
        val kind = glance.kind(now)
        val accent = Accent.toArgb()
        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(text(glanceTitle(kind), 13f, accent, bold = true))
            .addContent(spacer(4f))
        when (kind) {
            WatchGlance.Kind.RESTING, WatchGlance.Kind.ACTIVE -> {
                column.addContent(text(glance.activeName.orEmpty(), 18f, WHITE, bold = true, maxLines = 2))
                column.addContent(spacer(10f))
                column.addContent(button(getString(R.string.continue_workout), accent, planId = null))
            }
            WatchGlance.Kind.NEXT -> {
                val next = glance.next ?: return column.build()
                column.addContent(text(next.name, 18f, WHITE, bold = true, maxLines = 2))
                val detail = listOfNotNull(
                    next.scheduleName,
                    resources.getQuantityString(R.plurals.exercise_count, next.exerciseCount, next.exerciseCount).takeIf { next.exerciseCount > 0 },
                ).joinToString(" · ")
                if (detail.isNotEmpty()) column.addContent(text(detail, 13f, SECONDARY))
                column.addContent(spacer(10f))
                column.addContent(button(getString(R.string.start), accent, planId = next.planId))
            }
            WatchGlance.Kind.EMPTY -> {
                column.addContent(text(getString(R.string.glance_none), 14f, SECONDARY, maxLines = 2))
                column.addContent(spacer(10f))
                column.addContent(button(getString(R.string.glance_open), accent, planId = null))
            }
        }
        glance.week(now)?.let { week ->
            column.addContent(spacer(8f))
            column.addContent(text(weekText(week), 12f, SECONDARY))
        }
        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setPadding(ModifiersBuilders.Padding.Builder().setStart(dp(20f)).setEnd(dp(20f)).build())
                    .build(),
            )
            .addContent(column.build())
            .build()
    }

    private fun text(value: String, size: Float, color: Int, bold: Boolean = false, maxLines: Int = 1) =
        LayoutElementBuilders.Text.Builder()
            .setText(value)
            .setMaxLines(maxLines)
            .setMultilineAlignment(LayoutElementBuilders.TEXT_ALIGN_CENTER)
            .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(sp(size))
                    .setColor(argb(color))
                    .setWeight(if (bold) LayoutElementBuilders.FONT_WEIGHT_BOLD else LayoutElementBuilders.FONT_WEIGHT_NORMAL)
                    .build(),
            )
            .build()

    private fun spacer(height: Float) = LayoutElementBuilders.Spacer.Builder().setHeight(dp(height)).build()

    /** Gumb koji otvara aplikaciju; s [planId] aplikacija odmah pokreće taj trening. */
    private fun button(label: String, color: Int, planId: String?): LayoutElementBuilders.LayoutElement {
        val activity = ActionBuilders.AndroidActivity.Builder()
            .setPackageName(packageName)
            .setClassName(MainActivity::class.java.name)
        if (planId != null) {
            activity.addKeyToExtraMapping(MainActivity.EXTRA_PLAN, ActionBuilders.AndroidStringExtra.Builder().setValue(planId).build())
        }
        val clickable = ModifiersBuilders.Clickable.Builder()
            .setId(planId ?: "open")
            .setOnClick(ActionBuilders.LaunchAction.Builder().setAndroidActivity(activity.build()).build())
            .build()
        return LayoutElementBuilders.Box.Builder()
            .setWidth(dp(120f))
            .setHeight(dp(44f))
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(clickable)
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(color))
                            .setCorner(ModifiersBuilders.Corner.Builder().setRadius(dp(22f)).build())
                            .build(),
                    )
                    .build(),
            )
            .addContent(text(label, 15f, OnAccent.toArgb(), bold = true))
            .build()
    }

    private companion object {
        const val RESOURCES_VERSION = "1"
        const val WHITE = 0xFFFFFFFF.toInt()
        const val SECONDARY = 0xFFB0B4BA.toInt()
    }
}
