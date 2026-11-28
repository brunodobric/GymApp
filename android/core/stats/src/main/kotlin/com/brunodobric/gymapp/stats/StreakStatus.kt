package com.brunodobric.gymapp.stats

import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Streak za karticu na Početnoj (`StreakStatus` na iOS-u): uzastopni tjedni s ispunjenim tjednim ciljem
 * ([WeekProgress.streakWeeks]) i što tekući tjedan znači za niz. Kartica tako daje blagi pritisak: koliko
 * treninga još treba do kraja tjedna i gubi li se niz ako ih korisnik ne odradi.
 */
data class StreakStatus(
    /** Tjedni zaredom, s tekućim tjednom ako je cilj već ispunjen. */
    val weeks: Int,
    val state: State,
    /** Odrađeni treninzi u tekućem tjednu. */
    val sessions: Int,
    /** Treninzi tjedno koji tjedan stavljaju u niz (cilj iz onboardinga, bez cilja 1). */
    val target: Int,
    /** Dani do kraja tjedna, s današnjim (1 je zadnji dan tjedna). */
    val daysLeft: Int,
) {
    enum class State {
        /** Cilj tekućeg tjedna je ispunjen: tjedan je već u nizu. */
        SECURED,

        /** Niz postoji, a tjedan s premalo treninga bi ga prekinuo. */
        AT_RISK,

        /**
         * Niz postoji, a tjedan bez ijednog treninga bio bi pauza ([WeekProgress.streakLength]): niz ostaje,
         * ali ne raste. Kartica tada samo poziva na sljedeći tjedan niza, bez prijetnje gubitkom.
         */
        CAN_GROW,

        /** Niza još nema: ispunjen cilj ovog tjedna ga započinje. */
        NOT_STARTED,
    }

    /** Treninzi koji još nedostaju do cilja ovog tjedna. */
    val remaining: Int get() = maxOf(target - sessions, 0)

    /** Zadnji dan tjedna, a cilj još nije ispunjen. */
    val isLastChance: Boolean get() = state == State.AT_RISK && daysLeft <= 1

    companion object {
        /** Stanje iz tekućeg tjedna ([WeekProgress.make]) u trenutku `now`. */
        fun of(progress: WeekProgress, now: Instant, calendar: StatsCalendar = StatsCalendar.system()): StreakStatus {
            val target = progress.weeklyTarget
            val state = when {
                progress.sessions >= target -> State.SECURED
                progress.previousStreakWeeks == 0 -> State.NOT_STARTED
                progress.streakIfWeekEndsNow < progress.previousStreakWeeks -> State.AT_RISK
                else -> State.CAN_GROW
            }
            val end = calendar.date(calendar.addDays(progress.start, progress.days.size.toLong()))
            val days = ChronoUnit.DAYS.between(calendar.date(now), end).toInt()
            return StreakStatus(progress.streakWeeks, state, progress.sessions, target, days.coerceIn(1, 7))
        }
    }
}
