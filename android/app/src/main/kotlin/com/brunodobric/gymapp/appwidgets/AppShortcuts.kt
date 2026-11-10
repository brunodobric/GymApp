package com.brunodobric.gymapp.appwidgets

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.brunodobric.gymapp.MainActivity
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.planning.WorkoutShortcuts
import com.brunodobric.gymapp.widgets.WidgetLink

/**
 * Dinamički prečaci na ikoni aplikacije: spremljeni treninzi koji su zadnji pokretani (docs/android.md, 7.10).
 * Uz tri statička prečaca (sljedeći trening, prazan trening, težina) launcheri prikazuju četiri do pet, pa su
 * dinamička najviše dva. Objavljuju se samo kad se popis promijeni.
 */
internal class AppShortcuts(context: Context) {
    private val appContext = context.applicationContext
    private var published: List<Pair<String, String>>? = null

    fun update(store: GymStore) {
        val templates = WorkoutShortcuts(store).recentTemplates(MAX_DYNAMIC)
        val signature = templates.map { it.id.toString() to it.name }
        if (signature == published) return
        val shortcuts = templates.mapIndexed { index, template ->
            val link = WidgetLink.StartTemplate(template.id)
            ShortcutInfoCompat.Builder(appContext, "template-${template.id}")
                .setShortLabel(template.name.ifBlank { appContext.getString(R.string.start_workout) })
                .setLongLabel(appContext.getString(R.string.shortcut_start_template, template.name))
                .setIcon(IconCompat.createWithResource(appContext, R.drawable.ic_notification))
                .setRank(index)
                .setIntent(Intent(Intent.ACTION_VIEW, Uri.parse(link.uri), appContext, MainActivity::class.java))
                .build()
        }
        val done = runCatching { ShortcutManagerCompat.setDynamicShortcuts(appContext, shortcuts) }.getOrDefault(false)
        if (done) published = signature
    }

    private companion object {
        const val MAX_DYNAMIC = 2
    }
}
