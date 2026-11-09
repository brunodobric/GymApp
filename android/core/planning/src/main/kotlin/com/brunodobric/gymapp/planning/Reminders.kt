package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.ReminderMode
import com.brunodobric.gymapp.model.ScheduleItemKind
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** Podsjetnik koji treba zakazati. */
data class PlannedReminder(
    val scheduleId: UUID,
    val scheduleName: String,
    val workoutName: String?,
    val fireDate: Instant,
    /** Sljedeći trening rasporeda na koji podsjetnik upućuje. */
    val scheduleItemId: UUID? = null,
    val templateId: UUID? = null,
    val cycle: Int = 1,
) {
    internal constructor(planned: PlannedWorkout, fireDate: Instant) : this(
        planned.schedule.id, planned.schedule.name, planned.template.name, fireDate,
        planned.item.id, planned.template.id, planned.cycle,
    )

    /** Stabilan identifikator za zakazivanje i otkazivanje (isti oblik kao na iOS-u). */
    val identifier: String get() = "schedule-${scheduleId.toString().uppercase()}-${fireDate.epochSecond}"
}

/**
 * Dan u tjednu kao `Calendar.weekday` na iOS-u (1 = nedjelja, 2 = ponedjeljak … 7 = subota).
 * Tako se sprema u `Schedule.weekdaysRaw`, pa je raspored isti na obje platforme.
 */
val DayOfWeek.appleWeekday: Int get() = value % 7 + 1

/** Računanje termina podsjetnika. Čista logika, bez baze i obavijesti. */
object ReminderPlanner {
    /** Koliko dana unaprijed se zakazuju fiksni podsjetnici. */
    const val HORIZON_DAYS = 14

    /**
     * Fiksni dani: svaki odabrani dan u tjednu u zadano vrijeme, osim dana kad je trening već odrađen.
     * `weekdays` su vrijednosti kao [appleWeekday] (1 = nedjelja).
     */
    fun fixedDates(
        weekdays: List<Int>,
        minutesOfDay: Int,
        now: Instant,
        completedDays: Set<LocalDate>,
        zone: ZoneId = ZoneId.systemDefault(),
        horizonDays: Int = HORIZON_DAYS,
    ): List<Instant> {
        val today = now.atZone(zone).toLocalDate()
        return (0 until horizonDays).mapNotNull { offset ->
            val day = today.plusDays(offset.toLong())
            if (day.dayOfWeek.appleWeekday !in weekdays || day in completedDays) return@mapNotNull null
            day.at(minutesOfDay, zone).takeIf { it > now }
        }
    }

    /**
     * Fleksibilno: `gapDays` dana nakon zadnjeg odrađenog treninga, a svaki rest dan u nizu prije sljedećeg
     * treninga dodaje još jedan dan. Bez ijednog treninga ili kad je termin prošao, sljedeće zadano vrijeme.
     */
    fun flexibleDate(
        lastWorkoutAt: Instant?,
        gapDays: Int,
        restDaysBeforeNext: Int,
        minutesOfDay: Int,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Instant {
        if (lastWorkoutAt != null) {
            val days = maxOf(gapDays, 0) + maxOf(restDaysBeforeNext, 0)
            val fire = lastWorkoutAt.atZone(zone).toLocalDate().plusDays(days.toLong()).at(minutesOfDay, zone)
            if (fire > now) return fire
        }
        val todayFire = now.atZone(zone).toLocalDate().at(minutesOfDay, zone)
        if (todayFire > now) return todayFire
        return todayFire.atZone(zone).plusDays(1).toInstant()
    }

    /** Početak dana plus minute (kao `Calendar.date(byAdding: .minute, …)` na iOS-u). */
    private fun LocalDate.at(minutes: Int, zone: ZoneId): Instant =
        atStartOfDay(zone).toInstant().plusSeconds(minutes * 60L)
}

/** Podsjetnici svih aktivnih rasporeda, spremni za zakazivanje. */
class ReminderBuilder(private val store: GymStore) {

    /**
     * Tijekom aktivnog treninga nema podsjetnika (već zakazani se otkazuju); isto vrijedi
     * za raspored bez vremena podsjetnika, neaktivan raspored i raspored bez sljedećeg treninga.
     */
    fun reminders(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<PlannedReminder> {
        if (store.activeSession() != null) return emptyList()
        return plannedReminders(now, zone)
    }

    /** Termini podsjetnika bez obzira na aktivni trening. */
    fun plannedReminders(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<PlannedReminder> {
        val engine = ScheduleEngine(store)
        val finished = store.finishedSessions()
        val result = mutableListOf<PlannedReminder>()

        for (schedule in store.schedules.sortedBy { it.createdAt }) {
            val minutes = schedule.reminderMinutes ?: continue
            if (!schedule.isActive) continue
            val next = engine.nextWorkout(schedule) ?: continue
            val own = finished.filter { it.scheduleId == schedule.id }

            when (schedule.reminderMode) {
                ReminderMode.FIXED_DAYS -> {
                    val completed = own.map { it.startedAt.atZone(zone).toLocalDate() }.toSet()
                    ReminderPlanner.fixedDates(schedule.weekdays, minutes, now, completed, zone)
                        .forEach { result += PlannedReminder(next, it) }
                }
                ReminderMode.FLEXIBLE -> {
                    val last = own.maxOfOrNull { it.endedAt ?: it.startedAt }
                    val items = schedule.orderedItems
                    val position = schedule.currentPosition
                    val nextIndex = items.indexOfFirst { it.id == next.item.id }.takeIf { it >= 0 } ?: position
                    val rests = if (position in items.indices && nextIndex >= position) {
                        items.subList(position, nextIndex).count { it.kind == ScheduleItemKind.REST_DAY }
                    } else {
                        0
                    }
                    val date = ReminderPlanner.flexibleDate(last, schedule.reminderGapDays, rests, minutes, now, zone)
                    result += PlannedReminder(next, date)
                }
            }
        }
        return result.sortedBy { it.fireDate }
    }
}

/** Vrijeme podsjetnika: u rasporedu se sprema kao minute od ponoći, a birač vremena radi s datumom. */
object ReminderTime {
    /** Zadani dan u zadano vrijeme (minute od ponoći). */
    fun date(minutes: Int, day: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant {
        val clamped = minutes.coerceIn(0, 24 * 60 - 1)
        return day.atZone(zone).toLocalDate().atTime(clamped / 60, clamped % 60).atZone(zone).toInstant()
    }

    /** Minute od ponoći za vrijeme iz datuma (sekunde se zanemaruju). */
    fun minutes(date: Instant, zone: ZoneId = ZoneId.systemDefault()): Int {
        val time = date.atZone(zone).toLocalTime()
        return time.hour * 60 + time.minute
    }

    /** Dani u tjednu redom od ponedjeljka ([appleWeekday]: nedjelja je 1, ponedjeljak 2). */
    val weekdaysFromMonday = listOf(2, 3, 4, 5, 6, 7, 1)

    /** Uključuje ili isključuje dan u popisu dana podsjetnika. Rezultat je sortiran i bez ponavljanja. */
    fun toggling(weekday: Int, weekdays: List<Int>): List<Int> {
        val days = weekdays.toMutableSet()
        if (!days.remove(weekday)) days += weekday
        return days.sorted()
    }
}
