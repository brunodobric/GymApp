package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightUnit
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Čitanje CSV izvoza iz aplikacija Strong i Hevy u isti oblik kao [ForeignWorkoutsCsv], pa uvoz radi isto.
 * Isto kao `StrongHevyCSV` na iOS-u:
 *
 *     Strong: Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
 *     Hevy:   title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,
 *             weight_kg,reps,distance_km,duration_seconds,rpe
 *
 * Oprema je u nazivu vježbe u zagradi ("Bench Press (Barbell)"). Zagrijavanje (Strong "W", Hevy "warmup")
 * uvozi se kao zagrijavanje. Strong ne piše jedinicu težine, pa se uzima jedinica iz postavki, osim kad je
 * u nazivu stupca ("Weight (lbs)"). Razdjelnik može biti zarez ili točka-zarez.
 */
object StrongHevyCsv {

    internal enum class Format { STRONG, HEVY }

    /** Je li tekst izvoz iz Stronga ili Hevyja. */
    fun matches(text: String): Boolean = detect(text) != null

    /** Čita sve treninge redom kako su u datoteci. Neispravan redak baca [BackupException.InvalidCsv]. */
    fun parse(
        text: String,
        zone: ZoneId = ZoneId.systemDefault(),
        weightUnit: WeightUnit = WeightUnit.KILOGRAMS,
    ): List<ForeignWorkoutsCsv.Workout> {
        val (format, separator) = detect(text) ?: throw BackupException.InvalidCsv(1)
        val rows = Csv.parse(text.replace("﻿", ""), separator)
        val header = rows.firstOrNull()?.map { it.trim().lowercase(Locale.ROOT) } ?: return emptyList()
        val columns = Columns(header, format, weightUnit)

        val workouts = mutableListOf<ForeignWorkoutsCsv.Workout>()
        val index = mutableMapOf<String, Int>()
        rows.drop(1).forEachIndexed { offset, row ->
            val line = offset + 2
            if (row.all { it.isBlank() }) return@forEachIndexed
            fun value(column: Int?): String = column?.let { row.getOrNull(it) }?.trim().orEmpty()
            val title = value(columns.title)
            val rawDate = value(columns.date)
            val startedAt = parseDate(rawDate, format, zone) ?: throw BackupException.InvalidCsv(line)
            val key = "$title|$rawDate"
            val position = index.getOrPut(key) {
                val duration = if (format == Format.HEVY) {
                    parseDate(value(columns.end), format, zone)?.let { maxOf(0, (it.epochSecond - startedAt.epochSecond).toInt()) }
                } else {
                    parseDuration(value(columns.duration))
                }
                workouts += ForeignWorkoutsCsv.Workout(
                    title = title.ifEmpty { "Trening" },
                    rawDate = rawDate,
                    startedAt = startedAt,
                    durationSeconds = duration,
                    exercises = mutableListOf(),
                    line = line,
                    notes = value(columns.workoutNotes),
                )
                workouts.size - 1
            }

            val (name, equipment) = splitName(value(columns.exercise))
            if (name.isEmpty()) throw BackupException.InvalidCsv(line)
            val set = setRow(::value, columns, format, line)
            val exercises = workouts[position].exercises
            val last = exercises.lastOrNull()
            val exercise = if (last != null && last.name == name && last.equipment == equipment) {
                last.also { it.sets += set }
            } else {
                ForeignWorkoutsCsv.Exercise(
                    name = name,
                    equipment = equipment,
                    sets = mutableListOf(set),
                    kind = ForeignWorkoutsCsv.Kind.WEIGHT_REPS,
                    line = line,
                    note = value(columns.exerciseNotes),
                ).also { exercises += it }
            }
            exercise.kind = kind(exercise.sets)
        }
        return workouts
    }

    /** Stupci po nazivu: Strong i Hevy ih nazivaju različito, a novije verzije dodaju ili mijenjaju stupce. */
    internal class Columns(private val header: List<String>, format: Format, defaultUnit: WeightUnit) {
        private fun find(vararg names: String): Int? = header.indexOfFirst { it in names }.takeIf { it >= 0 }
        private fun prefix(start: String): Int? = header.indexOfFirst { it.startsWith(start) }.takeIf { it >= 0 }

        var title: Int? = null
        var date: Int? = null
        var end: Int? = null
        var duration: Int? = null
        var exercise: Int? = null
        var setOrder: Int? = null
        var setType: Int? = null
        var weight: Int? = null
        var reps: Int? = null
        var distance: Int? = null
        var seconds: Int? = null
        var exerciseNotes: Int? = null
        var workoutNotes: Int? = null
        var weightUnit: WeightUnit = WeightUnit.KILOGRAMS
        var distanceInMiles = false

        init {
            when (format) {
                Format.STRONG -> {
                    title = find("workout name")
                    date = find("date")
                    duration = prefix("duration")
                    exercise = find("exercise name")
                    setOrder = find("set order")
                    weight = prefix("weight")
                    reps = find("reps")
                    distance = prefix("distance")
                    seconds = prefix("seconds")
                    exerciseNotes = find("notes")
                    workoutNotes = find("workout notes")
                    val weightName = weight?.let { header[it] }.orEmpty()
                    weightUnit = when {
                        "lb" in weightName -> WeightUnit.POUNDS
                        "kg" in weightName -> WeightUnit.KILOGRAMS
                        else -> defaultUnit
                    }
                    distanceInMiles = distance?.let { "mi" in header[it] } ?: false
                }
                Format.HEVY -> {
                    title = find("title")
                    date = find("start_time")
                    end = find("end_time")
                    exercise = find("exercise_title")
                    setOrder = find("set_index")
                    setType = find("set_type")
                    val kilograms = find("weight_kg")
                    val pounds = find("weight_lbs", "weight_lb")
                    if (kilograms != null) {
                        weight = kilograms
                    } else if (pounds != null) {
                        weight = pounds
                        weightUnit = WeightUnit.POUNDS
                    }
                    reps = find("reps")
                    val kilometers = find("distance_km")
                    val miles = find("distance_miles", "distance_mi")
                    if (kilometers != null) {
                        distance = kilometers
                    } else if (miles != null) {
                        distance = miles
                        distanceInMiles = true
                    }
                    seconds = find("duration_seconds")
                    exerciseNotes = find("exercise_notes")
                    workoutNotes = find("description")
                }
            }
        }
    }

    /** Format i razdjelnik prema prvom retku (zaglavlju). */
    internal fun detect(text: String): Pair<Format, Char>? {
        val first = text.replace("﻿", "").lineSequence().firstOrNull { it.isNotBlank() } ?: return null
        for (separator in listOf(',', ';')) {
            val names = Csv.parse(first, separator).firstOrNull().orEmpty().map { it.trim().lowercase(Locale.ROOT) }.toSet()
            if (names.containsAll(listOf("date", "workout name", "exercise name", "set order"))) return Format.STRONG to separator
            if (names.containsAll(listOf("title", "start_time", "exercise_title", "set_index"))) return Format.HEVY to separator
        }
        return null
    }

    private fun setRow(value: (Int?) -> String, columns: Columns, format: Format, line: Int): ForeignWorkoutsCsv.SetRow {
        val set = ForeignWorkoutsCsv.SetRow()
        number(value(columns.weight), line)?.takeIf { it > 0 }?.let { set.weightKg = WeightConversion.kilograms(it, columns.weightUnit) }
        number(value(columns.reps), line)?.takeIf { it > 0 }?.let { set.reps = it.roundToInt() }
        number(value(columns.seconds), line)?.takeIf { it > 0 }?.let { set.durationSeconds = it.roundToInt() }
        number(value(columns.distance), line)?.takeIf { it > 0 }?.let {
            set.distanceMeters = it * if (columns.distanceInMiles) 1609.344 else 1000.0
        }
        set.isWarmUp = when (format) {
            Format.STRONG -> value(columns.setOrder).uppercase(Locale.ROOT) == "W"
            Format.HEVY -> value(columns.setType).lowercase(Locale.ROOT) == "warmup"
        }
        return set
    }

    /** Broj s točkom ili zarezom kao decimalnim znakom; prazno je null, a neispravan broj greška. */
    private fun number(text: String, line: Int): Double? {
        if (text.isEmpty()) return null
        val value = text.replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() } ?: throw BackupException.InvalidCsv(line)
        return value
    }

    /** Vrsta unosa prema serijama: trajanje i udaljenost, težina ili samo ponavljanja. */
    internal fun kind(sets: List<ForeignWorkoutsCsv.SetRow>): ForeignWorkoutsCsv.Kind = when {
        sets.any { (it.distanceMeters ?: 0.0) > 0 } -> ForeignWorkoutsCsv.Kind.DURATION_DISTANCE
        sets.any { (it.durationSeconds ?: 0) > 0 } && sets.none { (it.reps ?: 0) > 0 } -> ForeignWorkoutsCsv.Kind.DURATION
        sets.any { (it.weightKg ?: 0.0) > 0 } -> ForeignWorkoutsCsv.Kind.WEIGHT_REPS
        else -> ForeignWorkoutsCsv.Kind.REPS
    }

    /** "Bench Press (Barbell)" → ("Bench Press", "Barbell"). Bez zagrade oprema je prazna. */
    internal fun splitName(text: String): Pair<String, String> {
        val open = text.lastIndexOf('(')
        if (!text.endsWith(")") || open < 0) return text to ""
        val name = text.substring(0, open).trim()
        val equipment = text.substring(open + 1, text.length - 1).trim()
        return if (name.isEmpty()) text to "" else name to equipment
    }

    private val strongPatterns = listOf("yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm")
    private val hevyPatterns = listOf("d MMM yyyy, HH:mm", "d MMM yyyy HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss")

    /** Strong: "2023-01-15 08:30:00". Hevy: "15 Jan 2023, 08:30" (i ISO 8601 u novijim izvozima). */
    internal fun parseDate(text: String, format: Format, zone: ZoneId): Instant? {
        if (text.isEmpty()) return null
        if (format == Format.HEVY) {
            try {
                return OffsetDateTime.parse(text).toInstant()
            } catch (_: DateTimeParseException) {
                // Nije ISO s pomakom: probaju se ostali oblici.
            }
        }
        for (pattern in if (format == Format.STRONG) strongPatterns else hevyPatterns) {
            try {
                return LocalDateTime.parse(text, DateTimeFormatter.ofPattern(pattern, Locale.US)).atZone(zone).toInstant()
            } catch (_: DateTimeParseException) {
                continue
            }
        }
        return null
    }

    /** Strong: "1h 5m", "45m", "50s" ili broj sekundi. Null kad trajanja nema. */
    internal fun parseDuration(text: String): Int? {
        val trimmed = text.trim().lowercase(Locale.ROOT)
        if (trimmed.isEmpty()) return null
        trimmed.toIntOrNull()?.let { return it }
        var total = 0
        var found = false
        val number = StringBuilder()
        for (character in trimmed) {
            if (character.isDigit()) {
                number.append(character)
                continue
            }
            val value = number.toString().toIntOrNull() ?: continue
            when (character) {
                'h' -> total += value * 3600
                'm' -> total += value * 60
                's' -> total += value
                else -> continue
            }
            found = true
            number.setLength(0)
        }
        return if (found) total else null
    }
}
