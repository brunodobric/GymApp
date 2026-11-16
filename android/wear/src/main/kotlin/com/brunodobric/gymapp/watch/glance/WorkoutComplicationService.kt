package com.brunodobric.gymapp.watch.glance

import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.CountDownTimeReference
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.data.TimeDifferenceStyle
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationDataTimeline
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.TimeInterval
import androidx.wear.watchface.complications.datasource.TimelineEntry
import com.brunodobric.gymapp.watch.R
import com.brunodobric.gymapp.watch.WatchApplication
import com.brunodobric.gymapp.watch.WorkoutService
import com.brunodobric.gymapp.wear.WatchGlance
import java.time.Instant

/**
 * Komplikacija "Trening i odmor" (`GymComplication` na iOS-u): odbrojavanje odmora, trening u tijeku ili
 * sljedeći trening. Odbrojavanje crta sustav; za kraj odmora komplikacija dobiva vremensku crtu, pa se
 * vraća na trening u tijeku i kad aplikacija ne radi.
 */
class WorkoutComplicationService : ComplicationDataSourceService() {
    override fun onComplicationRequest(request: ComplicationRequest, listener: ComplicationRequestListener) {
        val glance = WatchGlance.from((application as WatchApplication).store.state.value)
        val now = Instant.now()
        val restEnd = glance.restEndsAt
        if (glance.isResting(now) && restEnd != null) {
            val afterRest = data(request.complicationType, glance.copy(restStartedAt = null, restEndsAt = null), now)
            val rest = data(request.complicationType, glance, now)
            if (afterRest != null && rest != null) {
                listener.onComplicationDataTimeline(
                    ComplicationDataTimeline(afterRest, listOf(TimelineEntry(TimeInterval(now, restEnd), rest))),
                )
                return
            }
        }
        listener.onComplicationData(data(request.complicationType, glance, now))
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val preview = WatchGlance(next = WatchGlance.Next(planId = "", name = "Push", scheduleName = "PPL", exerciseCount = 5))
        return data(type, preview, Instant.now())
    }

    private fun data(type: ComplicationType, glance: WatchGlance, now: Instant): ComplicationData? {
        val kind = glance.kind(now)
        val restEnd = glance.restEndsAt
        val title = plain(glanceTitle(kind))
        val main: ComplicationText = when (kind) {
            WatchGlance.Kind.RESTING -> TimeDifferenceComplicationText.Builder(TimeDifferenceStyle.STOPWATCH, CountDownTimeReference(restEnd ?: now)).build()
            WatchGlance.Kind.ACTIVE -> plain(glance.activeName.orEmpty())
            WatchGlance.Kind.NEXT -> plain(glance.next?.name.orEmpty())
            WatchGlance.Kind.EMPTY -> plain(getString(if (type == ComplicationType.LONG_TEXT) R.string.glance_none else R.string.app_name))
        }
        val description = plain(listOf(glanceTitle(kind), glance.activeName ?: glance.next?.name).filterNotNull().joinToString(", "))
        val icon = MonochromaticImage.Builder(Icon.createWithResource(this, R.drawable.ic_notification)).build()
        val tap = WorkoutService.openAppIntent(this)
        return when (type) {
            ComplicationType.SHORT_TEXT -> ShortTextComplicationData.Builder(if (kind == WatchGlance.Kind.RESTING) main else shortName(glance, kind), description)
                .setMonochromaticImage(icon)
                .setTapAction(tap)
                .build()
            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(main, description)
                .setTitle(title)
                .setMonochromaticImage(icon)
                .setTapAction(tap)
                .build()
            else -> null
        }
    }

    /** Kratki tekst ima mjesta za oko sedam znakova. */
    private fun shortName(glance: WatchGlance, kind: WatchGlance.Kind): ComplicationText {
        val name = when (kind) {
            WatchGlance.Kind.ACTIVE -> glance.activeName
            WatchGlance.Kind.NEXT -> glance.next?.name
            else -> null
        } ?: getString(R.string.app_name)
        return plain(name.take(SHORT_TEXT_LENGTH))
    }

    private fun plain(text: String): ComplicationText = PlainComplicationText.Builder(text).build()

    private companion object {
        const val SHORT_TEXT_LENGTH = 7
    }
}
