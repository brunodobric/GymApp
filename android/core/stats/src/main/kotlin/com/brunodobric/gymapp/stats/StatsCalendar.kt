package com.brunodobric.gymapp.stats

import java.text.Collator
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

/** Vremenski raspon s uključenim krajem, kao `DateInterval` na iOS-u. */
data class DateInterval(val start: Instant, val end: Instant) {
    fun contains(date: Instant): Boolean = date >= start && date <= end

    val durationSeconds: Double get() = (end.toEpochMilli() - start.toEpochMilli()) / 1000.0
}

/**
 * Kalendar za statistiku: vremenska zona i prvi dan tjedna (`Calendar` na iOS-u). Zadani kalendar prati
 * uređaj, a testovi zadaju UTC i ponedjeljak, kao `calendar` u testovima GymKita.
 */
data class StatsCalendar(val zone: ZoneId, val firstDayOfWeek: DayOfWeek) {

    fun date(instant: Instant): LocalDate = instant.atZone(zone).toLocalDate()

    fun startOfDay(day: LocalDate): Instant = day.atStartOfDay(zone).toInstant()

    fun startOfDay(instant: Instant): Instant = startOfDay(date(instant))

    /** Dodaje dane po kalendaru (isto vrijeme na satu i preko promjene ljetnog vremena). */
    fun addDays(instant: Instant, days: Long): Instant = instant.atZone(zone).plusDays(days).toInstant()

    fun addWeeks(instant: Instant, weeks: Long): Instant = instant.atZone(zone).plusWeeks(weeks).toInstant()

    fun addMonths(instant: Instant, months: Long): Instant = instant.atZone(zone).plusMonths(months).toInstant()

    fun addYears(instant: Instant, years: Long): Instant = instant.atZone(zone).plusYears(years).toInstant()

    fun dayInterval(instant: Instant): DateInterval {
        val day = date(instant)
        return DateInterval(startOfDay(day), startOfDay(day.plusDays(1)))
    }

    fun weekInterval(instant: Instant): DateInterval {
        val start = date(instant).with(TemporalAdjusters.previousOrSame(firstDayOfWeek))
        return DateInterval(startOfDay(start), startOfDay(start.plusWeeks(1)))
    }

    fun monthInterval(instant: Instant): DateInterval {
        val start = date(instant).withDayOfMonth(1)
        return DateInterval(startOfDay(start), startOfDay(start.plusMonths(1)))
    }

    fun yearInterval(instant: Instant): DateInterval {
        val start = date(instant).withDayOfYear(1)
        return DateInterval(startOfDay(start), startOfDay(start.plusYears(1)))
    }

    fun zoned(instant: Instant): ZonedDateTime = instant.atZone(zone)

    companion object {
        /** Kalendar uređaja: zona i prvi dan tjedna prema jeziku i regiji. */
        fun system(locale: Locale = Locale.getDefault()): StatsCalendar =
            StatsCalendar(ZoneId.systemDefault(), WeekFields.of(locale).firstDayOfWeek)
    }
}

/** Abecedni poredak bez razlike velikih i malih slova (`localizedCaseInsensitiveCompare` na iOS-u). */
internal fun caseInsensitiveOrder(locale: Locale = Locale.getDefault()): Comparator<String> {
    val collator = Collator.getInstance(locale).apply { strength = Collator.SECONDARY }
    return Comparator { a, b -> collator.compare(a, b) }
}
