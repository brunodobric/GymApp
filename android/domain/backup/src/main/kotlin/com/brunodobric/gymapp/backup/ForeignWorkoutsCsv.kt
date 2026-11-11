package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID

/**
 * Čitanje CSV izvoza treninga iz druge aplikacije. Ne ovisi o bazi, pa se može testirati samostalno.
 *
 * Format (točka-zarez kao razdjelnik, prazan redak između treninga):
 * ```
 * "Push · Day 1 · Week 9 · Gym 2.0";"2026-11-02 4:27 pm";"53 min"
 * "1. Incline Bench Press · Dumbbells · 10 reps"
 * #;KG;REPS
 * 1;24;10
 * 2;+12.5;10        (vlastita težina + 12,5 kg)
 * 3;-;-             (prazna serija)
 * "2. Plank · Bodyweight"
 * #;MINS
 * 1;1
 * ```
 * Izvoz iste aplikacije s drugog uređaja smije se razlikovati u sitnicama: razdjelnik može biti i zarez ili
 * tabulator, razmak ispred "pm" može biti neprekinuti (U+00A0, U+202F), a "pm" može biti i "PM" ili "p.m.".
 * Datum je lokalno vrijeme bez vremenske zone. Ciljani broj ponavljanja iz retka vježbe ("10 reps") se ne uvozi.
 */
object ForeignWorkoutsCsv {

    /** Jedan odrađeni trening iz datoteke. */
    data class Workout(
        /** Cijelo zaglavlje, npr. "Push · Day 1 · Week 9 · Gym 2.0". */
        val title: String,
        /** Datum i vrijeme točno kako piše u datoteci (ključ za prepoznavanje već uvezenog treninga). */
        val rawDate: String,
        val startedAt: Instant,
        val durationSeconds: Int?,
        val exercises: MutableList<Exercise>,
        /** Redak zaglavlja u datoteci (od 1). */
        val line: Int,
    ) {
        /** Naziv treninga: prvi dio zaglavlja ("Push"). */
        val name: String get() = title.split(" · ").first().trimSwift()

        /** Ostatak zaglavlja ("Day 1 · Week 9 · Gym 2.0"), ide u bilješku treninga. */
        val details: String get() = title.split(" · ").drop(1).joinToString(" · ") { it.trimSwift() }

        /**
         * Stabilan identifikator: isti trening iz iste datoteke uvijek dobiva isti UUID (i na iPhoneu),
         * pa se ponovni uvoz prepoznaje kao već postojeći trening.
         */
        val stableId: UUID get() = StableUUID.make("foreign-workouts-csv|$title|$rawDate")
    }

    data class Exercise(
        val name: String,
        /** Oprema kako piše u datoteci ("Dumbbells", "Cable"). Prazno ako je nema. */
        val equipment: String,
        val sets: MutableList<SetRow>,
        /** Vrsta unosa prema stupcima i vrijednostima tablice. */
        var kind: Kind,
        val line: Int,
    )

    /** Vrsta unosa vježbe u datoteci. */
    enum class Kind {
        /** Težina i ponavljanja. */
        WEIGHT_REPS,

        /** Vlastita težina + teret ("+12.5"). */
        WEIGHTED_BODYWEIGHT,

        /** Samo ponavljanja. */
        REPS,

        /** Trajanje (i eventualno udaljenost). */
        DURATION,
        DURATION_DISTANCE,
    }

    /** Jedna serija. Težine u kilogramima, trajanje u sekundama, udaljenost u metrima. */
    data class SetRow(
        var weightKg: Double? = null,
        /** Teret uz vlastitu težinu (vrijednost s "+"). */
        var extraWeightKg: Double? = null,
        var reps: Int? = null,
        var durationSeconds: Int? = null,
        var distanceMeters: Double? = null,
    ) {
        /** Je li serija odrađena. Serija s "-" ili samo s težinom bez ponavljanja se ne uvozi. */
        val isDone: Boolean get() = (reps ?: 0) > 0 || (durationSeconds ?: 0) > 0 || (distanceMeters ?: 0.0) > 0
    }

    // MARK: Prepoznavanje

    /** Je li tekst u ovom formatu: prvi neprazni redak je zaglavlje treninga s datumom. */
    fun matches(text: String): Boolean {
        return separator(text) != null
    }

    /** Razdjelnik datoteke: onaj uz koji je prvi neprazni redak zaglavlje treninga. Null kad nijedan ne odgovara. */
    private fun separator(text: String): Char? {
        val line = lines(text).firstOrNull { it.second.isNotEmpty() } ?: return null
        return separators.firstOrNull { header(fields(line.second, it)) != null }
    }

    private val separators = listOf(';', ',', '\t')

    // MARK: Čitanje

    /** Čita sve treninge. Neispravan redak baca [BackupException.InvalidCsv] s brojem retka, pa se ništa ne uvozi napola. */
    fun parse(text: String, zone: ZoneId = ZoneId.systemDefault()): List<Workout> {
        val workouts = mutableListOf<Workout>()
        var columns: List<Column>? = null
        val separator = separator(text) ?: ';'

        for ((number, line) in lines(text)) {
            if (line.isEmpty()) {
                columns = null
                continue
            }
            val row = fields(line, separator)

            val header = header(row)
            if (header != null) {
                val date = parseDate(header.rawDate, zone) ?: throw BackupException.InvalidCsv(number)
                workouts += Workout(header.title, header.rawDate, date, parseDuration(header.duration), mutableListOf(), number)
                columns = null
                continue
            }

            val workout = workouts.lastOrNull() ?: throw BackupException.InvalidCsv(number)

            if (row.size == 1) {
                val exercise = exerciseLine(row[0], number)
                if (exercise != null) {
                    workout.exercises += exercise
                    columns = null
                    continue
                }
            }

            if (row.firstOrNull() == "#") {
                if (workout.exercises.isEmpty()) throw BackupException.InvalidCsv(number)
                columns = row.drop(1).map { name ->
                    Column.entries.firstOrNull { it.raw == name.uppercase() } ?: throw BackupException.InvalidCsv(number)
                }
                continue
            }

            val current = columns
            if (current != null && row.firstOrNull()?.toIntOrNull() != null && row.size == current.size + 1) {
                appendSet(row.drop(1), current, workout, number)
                continue
            }

            throw BackupException.InvalidCsv(number)
        }
        return workouts
    }

    // MARK: Dijelovi retka

    private enum class Column(val raw: String) {
        KILOGRAMS("KG"), POUNDS("LBS"), REPS("REPS"), MINUTES("MINS"), SECONDS("SECS"), KILOMETERS("KM"), MILES("MI"),
    }

    private val newlines = Regex("\r\n|[\n\r\u000B\u000C\u0085  ]")

    /** Redci s brojem retka (od 1), bez razmaka i BOM-a na krajevima (i kad su dvije datoteke spojene u jednu). */
    private fun lines(text: String): List<Pair<Int, String>> =
        text.split(newlines).mapIndexed { index, line -> (index + 1) to line.trim { it.isSwiftWhitespace() || it == '﻿' } }

    private fun fields(line: String, separator: Char): List<String> =
        (Csv.parse(line, separator).firstOrNull() ?: emptyList()).map { it.trimSwift() }

    private class Header(val title: String, val rawDate: String, val duration: String)

    private fun header(row: List<String>): Header? {
        if (row.size != 3 || row[0].isEmpty() || parseDate(row[1], ZoneOffset.UTC) == null) return null
        // Datum je ključ treninga, pa se razmaci svode na jedan običan: isti trening dobiva isti ključ i kad ga
        // je izvezao uređaj koji ispred "pm" stavlja neprekinuti razmak.
        return Header(row[0], row[1].words().joinToString(" "), row[2])
    }

    /** "3. Incline Bench Press · Dumbbells · 10 reps" → naziv i oprema. */
    private fun exerciseLine(text: String, line: Int): Exercise? {
        val dot = text.indexOf('.')
        if (dot < 0 || text.substring(0, dot).toIntOrNull() == null) return null
        val rest = text.substring(dot + 1).trimSwift()
        val parts = rest.split(" · ").map { it.trimSwift() }
        val name = parts.first()
        if (name.isEmpty()) return null
        val equipment = if (parts.size > 1 && !isTarget(parts[1])) parts[1] else ""
        return Exercise(name, equipment, mutableListOf(), Kind.WEIGHT_REPS, line)
    }

    /** Cilj iz plana ("10 reps", "1 min"), a ne oprema. */
    private fun isTarget(text: String): Boolean = text.firstOrNull()?.let {
        it.category == CharCategory.DECIMAL_DIGIT_NUMBER || it.category == CharCategory.LETTER_NUMBER ||
            it.category == CharCategory.OTHER_NUMBER
    } == true

    private fun appendSet(values: List<String>, columns: List<Column>, workout: Workout, line: Int) {
        val set = SetRow()
        var weighted = false
        for ((column, raw) in columns.zip(values)) {
            var text = raw.replace(',', '.')
            if (text == "-" || text.isEmpty()) continue
            if (text.startsWith("+")) {
                weighted = true
                text = text.drop(1)
            }
            when (column) {
                Column.KILOGRAMS, Column.POUNDS -> {
                    val value = number(text) ?: throw BackupException.InvalidCsv(line)
                    val kilograms = if (column == Column.POUNDS) value * 0.45359237 else value
                    if (weighted) set.extraWeightKg = kilograms else set.weightKg = kilograms
                }
                Column.REPS -> {
                    val value = text.toIntOrNull()?.takeIf { it >= 0 } ?: throw BackupException.InvalidCsv(line)
                    set.reps = value
                }
                Column.MINUTES, Column.SECONDS ->
                    set.durationSeconds = parseTime(text, column == Column.MINUTES) ?: throw BackupException.InvalidCsv(line)
                Column.KILOMETERS, Column.MILES -> {
                    val value = number(text) ?: throw BackupException.InvalidCsv(line)
                    set.distanceMeters = value * if (column == Column.KILOMETERS) 1000.0 else 1609.344
                }
            }
        }

        val exercise = workout.exercises.last()
        exercise.sets += set
        exercise.kind = kind(columns, weighted || exercise.kind == Kind.WEIGHTED_BODYWEIGHT)
        if (exercise.kind == Kind.WEIGHTED_BODYWEIGHT) {
            // Ista vježba ima i serije bez "+": i to je teret uz vlastitu težinu.
            for (row in exercise.sets) {
                if (row.weightKg != null) {
                    row.extraWeightKg = row.weightKg
                    row.weightKg = null
                }
            }
        }
    }

    private val decimalPattern = Regex("""^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$""")

    /** Decimalni broj kao `Double(_:)` u Swiftu, bez "Infinity", "10f" i heksadecimalnih zapisa Jave. */
    private fun decimal(text: String): Double? = if (decimalPattern.matches(text)) text.toDoubleOrNull() else null

    /** Težina ili udaljenost: broj u rasponu koji prihvaća i unos u aplikaciji. */
    private fun number(text: String): Double? = decimal(text)?.takeIf(NumberInput::isAcceptable)

    private fun kind(columns: List<Column>, weighted: Boolean): Kind {
        val hasTime = Column.MINUTES in columns || Column.SECONDS in columns
        val hasDistance = Column.KILOMETERS in columns || Column.MILES in columns
        if (hasTime || hasDistance) return if (hasDistance) Kind.DURATION_DISTANCE else Kind.DURATION
        if (weighted) return Kind.WEIGHTED_BODYWEIGHT
        if (Column.KILOGRAMS in columns || Column.POUNDS in columns) return Kind.WEIGHT_REPS
        return Kind.REPS
    }

    // MARK: Datum i trajanje

    /** Dijelovi kao `split` u Swiftu: prazni dijelovi se izostavljaju. */
    private fun String.pieces(separator: Char): List<String> = split(separator).filter { it.isNotEmpty() }

    /** Riječi odvojene bilo kojim razmakom, i neprekinutim (U+00A0, U+202F), kakav neki uređaji stave ispred "pm". */
    private fun String.words(): List<String> = split(spaces).filter { it.isNotEmpty() }

    private val spaces = Regex("""[\s\p{Z}]+""")

    /**
     * "2026-11-02 4:27 pm" ili "2026-11-02 16:27" u zadanoj vremenskoj zoni. Prihvaća i sekunde ("16:27:05")
     * te oznaku napisanu kao "PM", "p.m." ili "p. m.".
     */
    fun parseDate(text: String, zone: ZoneId): Instant? {
        val parts = text.lowercase().words()
        if (parts.size < 2) return null
        val day = parts[0].pieces('-').mapNotNull { it.toIntOrNull() }
        val rawTime = parts[1].pieces(':')
        val time = rawTime.mapNotNull { it.toIntOrNull() }
        if (day.size != 3 || time.size != rawTime.size || time.size !in 2..3) return null
        if (day[1] !in 1..12 || day[2] !in 1..31 || time[1] !in 0..59 || (time.size == 3 && time[2] !in 0..59)) return null
        var hour = time[0]
        if (parts.size > 2) {
            val marker = parts.drop(2).joinToString("").replace(".", "")
            if (hour !in 1..12 || (marker != "am" && marker != "pm")) return null
            hour = hour % 12 + if (marker == "pm") 12 else 0
        }
        if (hour !in 0..23) return null
        return try {
            LocalDateTime.of(day[0], day[1], day[2], hour, time[1]).atZone(zone).toInstant()
        } catch (_: DateTimeException) {
            null
        }
    }

    /** "53 min", "1 hr", "1:17 hr", "1 hr 5 min", "45 sec" → sekunde. Null za nepoznat zapis. */
    fun parseDuration(text: String): Int? {
        val tokens = text.lowercase().words()
        if (tokens.isEmpty() || tokens.size % 2 != 0) return null
        var total = 0
        for (index in tokens.indices step 2) {
            val multiplier = when (tokens[index + 1]) {
                "hr", "hrs", "h", "hour", "hours" -> 3600
                "min", "mins", "m", "minute", "minutes" -> 60
                "sec", "secs", "s", "second", "seconds" -> 1
                else -> return null
            }
            // "1:17 hr" je 1 sat i 17 minuta, "1:30 min" 1 minuta i 30 sekundi.
            val raw = tokens[index].pieces(':')
            val pieces = raw.mapNotNull { it.toIntOrNull() }
            if (pieces.size != raw.size || pieces.size !in 1..2) return null
            total += pieces[0] * multiplier
            if (pieces.size == 2) {
                if (pieces[1] !in 0..59 || multiplier <= 1) return null
                total += pieces[1] * multiplier / 60
            }
        }
        return if (total > 0) total else null
    }

    /** Vrijednost u stupcu MINS ili SECS: "1", "1.5" ili "1:30". */
    private fun parseTime(text: String, minutes: Boolean): Int? {
        val pieces = text.pieces(':')
        val limit = DurationInput.MAXIMUM_SECONDS
        // "1:30" je uvijek minute i sekunde.
        if (pieces.size == 2) {
            val whole = pieces[0].toIntOrNull()
            val part = pieces[1].toIntOrNull()
            if (whole != null && part != null && part in 0..59) {
                if (whole !in 0..limit / 60) return null
                return whole * 60 + part
            }
        }
        val value = decimal(text)?.takeIf { it.isFinite() && it >= 0 } ?: return null
        val seconds = value * if (minutes) 60 else 1
        if (seconds > limit) return null
        return Math.round(seconds).toInt()
    }
}

/** `CharacterSet.whitespaces` u Swiftu: razmak, tab i ostali razmaci (bez novog retka). */
private fun Char.isSwiftWhitespace(): Boolean = this == '\t' || category == CharCategory.SPACE_SEPARATOR

private fun String.trimSwift(): String = trim { it.isSwiftWhitespace() }

/**
 * Deterministički UUID iz teksta (FNV-1a, 128 bita), isti kao `StableUUID` na iOS-u. Nije kriptografski,
 * služi samo za prepoznavanje istog zapisa.
 */
object StableUUID {
    fun make(text: String): UUID {
        val bytes = text.toByteArray(Charsets.UTF_8)
        fun fnv(seed: Long): Long {
            var hash = seed
            for (byte in bytes) {
                hash = hash xor (byte.toLong() and 0xFF)
                hash *= 0x0000_0100_0000_01B3L
            }
            return hash
        }
        val high = fnv(0xCBF29CE484222325UL.toLong())
        val low = fnv(0x84222325CBF29CE4UL.toLong())
        // Verzija 5 (ime → UUID) u 7. bajtu i RFC 4122 varijanta u 9. bajtu.
        val msb = (high and 0x0000_0000_0000_F000L.inv()) or 0x0000_0000_0000_5000L
        val lsb = (low and 0x3FFF_FFFF_FFFF_FFFFL) or (0x80L shl 56)
        return UUID(msb, lsb)
    }
}
