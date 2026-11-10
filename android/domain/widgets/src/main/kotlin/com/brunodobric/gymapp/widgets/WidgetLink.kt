package com.brunodobric.gymapp.widgets

import java.util.Locale
import java.util.UUID

/**
 * Poveznice kojima widgeti otvaraju aplikaciju (`WidgetLink` na iOS-u), iste kao na iPhoneu:
 * `apolon://pocetna`, `apolon://trening`, `apolon://povijest/<UUID>`…
 */
sealed class WidgetLink(internal val host: String) {
    /** Početna. */
    data object Home : WidgetLink("pocetna")

    /** Pokreće sljedeći trening (ili nastavlja trening u tijeku). */
    data object StartWorkout : WidgetLink("zapocni")

    /** Ekran treninga u tijeku. */
    data object ActiveWorkout : WidgetLink("trening")

    /** Pregled tekućeg tjedna. */
    data object Week : WidgetLink("tjedan")

    /** Praćenje tijela (unos težine). */
    data object BodyWeight : WidgetLink("tezina")

    /** Zadnji odrađeni trening. */
    data object LastWorkout : WidgetLink("zadnji-trening")

    /** Određeni odrađeni trening (npr. onaj s rekordom). */
    data class Session(val id: UUID) : WidgetLink("povijest")

    /** Pokreće prazan trening (prečac na ikoni; samo Android). */
    data object EmptyWorkout : WidgetLink("prazan-trening")

    /** Pokreće spremljeni trening (dinamički prečac na ikoni; samo Android). */
    data class StartTemplate(val id: UUID) : WidgetLink("zapocni")

    val uri: String
        get() = when (this) {
            is Session -> "$SCHEME://$host/${id.toString().uppercase(Locale.ROOT)}"
            is StartTemplate -> "$SCHEME://$host/${id.toString().uppercase(Locale.ROOT)}"
            else -> "$SCHEME://$host"
        }

    companion object {
        const val SCHEME = "apolon"

        private val simple: List<WidgetLink> get() = listOf(Home, StartWorkout, ActiveWorkout, Week, BodyWeight, LastWorkout, EmptyWorkout)

        /** Poveznica iz zapisa; null za tuđu ili nepoznatu poveznicu. */
        fun parse(uri: String): WidgetLink? {
            val prefix = "$SCHEME://"
            if (!uri.lowercase(Locale.ROOT).startsWith(prefix)) return null
            val rest = uri.substring(prefix.length).trimEnd('/')
            val host = rest.substringBefore('/').lowercase(Locale.ROOT)
            fun id(): UUID? {
                val text = rest.substringAfterLast('/', "")
                return runCatching { UUID.fromString(text) }.getOrNull()?.takeIf { it.toString().equals(text, ignoreCase = true) }
            }
            if (host == "povijest") return id()?.let(::Session)
            if (host == "zapocni" && rest.contains('/')) return id()?.let(::StartTemplate)
            return simple.firstOrNull { it.host == host }
        }
    }
}
