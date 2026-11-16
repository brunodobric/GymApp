package com.brunodobric.gymapp.watch.glance

import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import com.brunodobric.gymapp.watch.R
import com.brunodobric.gymapp.watch.WatchApplication
import com.brunodobric.gymapp.watch.WorkoutService
import com.brunodobric.gymapp.wear.WatchGlance
import com.brunodobric.gymapp.widgets.WidgetSnapshot
import java.time.Instant

/** Komplikacija "Tjedni cilj" (`WeekGoalComplication` na iOS-u): treninga ovaj tjedan prema cilju. */
class WeekComplicationService : ComplicationDataSourceService() {
    override fun onComplicationRequest(request: ComplicationRequest, listener: ComplicationRequestListener) {
        val glance = WatchGlance.from((application as WatchApplication).store.state.value)
        listener.onComplicationData(data(request.complicationType, glance.week(Instant.now())))
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        data(type, WidgetSnapshot.Week.empty(Instant.EPOCH, sessions = 3, goal = 4, streakWeeks = 2))

    private fun data(type: ComplicationType, week: WidgetSnapshot.Week?): ComplicationData? {
        val sessions = week?.sessions ?: 0
        val goal = week?.goal
        val value = if (goal != null) "$sessions/$goal" else "$sessions"
        val text = PlainComplicationText.Builder(value).build()
        val title = PlainComplicationText.Builder(getString(R.string.glance_week)).build()
        val description = PlainComplicationText.Builder(week?.let { weekText(it) } ?: getString(R.string.complication_week)).build()
        val icon = MonochromaticImage.Builder(Icon.createWithResource(this, R.drawable.ic_notification)).build()
        val tap = WorkoutService.openAppIntent(this)
        return when (type) {
            ComplicationType.RANGED_VALUE -> {
                val max = (goal ?: maxOf(sessions, 1)).toFloat()
                RangedValueComplicationData.Builder(minOf(sessions.toFloat(), max), 0f, max, description)
                    .setText(text)
                    .setTitle(title)
                    .setMonochromaticImage(icon)
                    .setTapAction(tap)
                    .build()
            }
            ComplicationType.SHORT_TEXT -> ShortTextComplicationData.Builder(text, description)
                .setTitle(title)
                .setMonochromaticImage(icon)
                .setTapAction(tap)
                .build()
            else -> null
        }
    }
}
