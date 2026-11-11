package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.catalog.uppercaseString
import com.brunodobric.gymapp.model.BodyMeasurement
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetLog
import java.util.UUID

/**
 * CSV izvoz i uvoz: povijest treninga (jedan redak po seriji) i tjelesna mjerenja, isti stupci kao na iOS-u.
 * Težine su uvijek u kilogramima, a udaljenost u metrima, neovisno o jedinici u Postavkama.
 */
object CsvBackup {
    val historyColumns = listOf(
        "session_id", "session_name", "workout_kind", "started_at", "ended_at", "session_notes",
        "exercise_order", "exercise_key", "exercise_name", "input_type", "superset_group", "rest_seconds",
        "set_order", "set_kind", "weight_kg", "reps", "extra_weight_kg", "duration_s", "distance_m", "rpe", "completed_at",
    )
    val bodyColumns = listOf("id", "kind", "custom_name", "value", "date", "source")

    /** Uvozi CSV prema zaglavlju: povijest treninga ili tjelesna mjerenja. */
    fun importAny(text: String, store: GymStore): BackupImportResult {
        val header = Csv.parse(text).firstOrNull()
        return when (header) {
            historyColumns -> importHistory(text, store)
            bodyColumns -> importBody(text, store)
            else -> throw BackupException.InvalidCsv(1)
        }
    }

    // MARK: Povijest treninga

    fun exportHistory(store: GymStore): String {
        val lines = mutableListOf(Csv.line(historyColumns))
        for (session in store.ownFinishedSessions().sortedWith(compareBy({ it.startedAt }, { it.id.sortKey }))) {
            val head = listOf(
                session.id.uppercaseString, session.name, session.kindRaw, CsvDate.string(session.startedAt),
                CsvDate.string(session.endedAt), session.notes,
            )
            val exercises = session.orderedExercises.filter { !it.isRemoved }
            if (exercises.isEmpty()) lines += Csv.line(head + List(historyColumns.size - head.size) { "" })
            for (exercise in exercises) {
                val exerciseFields = listOf(
                    exercise.orderIndex.toString(), exercise.exerciseKey, exercise.exerciseName, exercise.inputTypeRaw,
                    exercise.supersetGroupId?.uppercaseString ?: "", exercise.restSeconds?.toString() ?: "",
                )
                val sets = exercise.orderedSets
                if (sets.isEmpty()) lines += Csv.line(head + exerciseFields + List(9) { "" })
                for (set in sets) {
                    lines += Csv.line(
                        head + exerciseFields + listOf(
                            set.orderIndex.toString(), set.kindRaw, number(set.weightKg), set.reps?.toString() ?: "",
                            number(set.extraWeightKg), set.durationSeconds?.toString() ?: "",
                            number(set.distanceMeters), number(set.rpe), CsvDate.string(set.completedAt),
                        ),
                    )
                }
            }
        }
        return lines.joinToString("\n") + "\n"
    }

    /**
     * Uvozi treninge iz CSV-a koji je izvezen ovom aplikacijom (na iOS-u ili Androidu). Treninzi čiji `session_id`
     * već postoji se preskaču. Datoteka se prvo cijela provjeri, pa neispravan redak ne ostavlja polovičan uvoz.
     */
    fun importHistory(text: String, store: GymStore): BackupImportResult {
        val rows = Csv.parse(text)
        if (rows.firstOrNull() != historyColumns) throw BackupException.InvalidCsv(1)

        val order = mutableListOf<UUID>()
        val groups = LinkedHashMap<UUID, MutableList<Pair<Int, List<String>>>>()
        rows.withIndex().drop(1).forEach { (index, row) ->
            val id = if (row.size == historyColumns.size) parseUUID(row[0]) else null
            if (id == null || CsvDate.parse(row[3]) == null) throw BackupException.InvalidCsv(index + 1)
            if (id !in groups) order += id
            groups.getOrPut(id) { mutableListOf() } += (index + 1) to row
        }

        val known = store.sessions.map { it.id }.toSet()
        val result = BackupImportResult()
        try {
            for (id in order) {
                if (id in known) {
                    result.skipped += 1
                    continue
                }
                buildSession(id, groups.getValue(id), store)
                result.added += 1
            }
        } catch (error: BackupException) {
            store.rollback()
            throw error
        }
        store.save()
        return result
    }

    private fun buildSession(id: UUID, lines: List<Pair<Int, List<String>>>, store: GymStore) {
        val head = lines[0].second
        val session = Session(id)
        session.name = head[1]
        session.startedAt = CsvDate.parse(head[3])!!
        session.kindRaw = head[2]
        session.endedAt = CsvDate.parse(head[4])
        session.notes = head[5]
        session.state = SessionState.FINISHED
        session.lastActivityAt = session.endedAt ?: session.startedAt
        store.insert(session)

        val exercises = mutableMapOf<Int, SessionExercise>()
        for ((number, fields) in lines) {
            if (fields[6].isEmpty()) continue
            val exerciseOrder = fields[6].toIntOrNull() ?: throw BackupException.InvalidCsv(number)
            val ref = ExerciseRef.fromKey(fields[7], fields[8]) ?: throw BackupException.InvalidCsv(number)
            val exercise = exercises.getOrPut(exerciseOrder) {
                session.add(SessionExercise(exerciseOrder, ref)).also {
                    it.inputTypeRaw = fields[9]
                    it.supersetGroupId = parseUUID(fields[10])
                    it.restSeconds = fields[11].toIntOrNull()
                }
            }
            if (fields[12].isEmpty()) continue
            val setOrder = fields[12].toIntOrNull() ?: throw BackupException.InvalidCsv(number)
            exercise.add(makeSet(setOrder, fields, number))
        }
    }

    private fun makeSet(order: Int, fields: List<String>, line: Int): SetLog {
        fun double(text: String): Double? {
            if (text.isEmpty()) return null
            // "inf", "nan" i negativni brojevi nisu ispravna vrijednost serije.
            val value = text.toDoubleOrNull()
            if (value == null || !value.isFinite() || value < 0) throw BackupException.InvalidCsv(line)
            return value
        }
        fun integer(text: String): Int? {
            if (text.isEmpty()) return null
            return text.toIntOrNull() ?: throw BackupException.InvalidCsv(line)
        }
        val set = SetLog(order)
        set.kindRaw = fields[13]
        set.weightKg = double(fields[14])
        set.reps = integer(fields[15])
        set.extraWeightKg = double(fields[16])
        set.durationSeconds = integer(fields[17])
        set.distanceMeters = double(fields[18])
        set.rpe = double(fields[19])
        set.completedAt = CsvDate.parse(fields[20])
        return set
    }

    // MARK: Tjelesna mjerenja

    fun exportBody(store: GymStore): String {
        val lines = mutableListOf(Csv.line(bodyColumns))
        for (item in store.bodyMeasurements.sortedWith(compareBy({ it.date }, { it.id.sortKey }))) {
            lines += Csv.line(
                listOf(
                    item.id.uppercaseString, item.kindRaw, item.customName ?: "", item.value.toString(),
                    CsvDate.string(item.date), item.sourceRaw,
                ),
            )
        }
        return lines.joinToString("\n") + "\n"
    }

    fun importBody(text: String, store: GymStore): BackupImportResult {
        val rows = Csv.parse(text)
        if (rows.firstOrNull() != bodyColumns) throw BackupException.InvalidCsv(1)
        // Datoteka se prvo cijela provjeri.
        val parsed = rows.withIndex().drop(1).map { (index, row) ->
            val id = if (row.size == bodyColumns.size) parseUUID(row[0]) else null
            val value = row.getOrNull(3)?.toDoubleOrNull()
            val date = row.getOrNull(4)?.let(CsvDate::parse)
            if (id == null || value == null || !value.isFinite() || value < 0 || date == null) {
                throw BackupException.InvalidCsv(index + 1)
            }
            Triple(id, row, value to date)
        }
        val known = store.bodyMeasurements.map { it.id }.toMutableSet()
        val result = BackupImportResult()
        for ((id, row, valueDate) in parsed) {
            if (!known.add(id)) {
                result.skipped += 1
                continue
            }
            val item = BodyMeasurement(BodyMeasurementKind.CUSTOM, valueDate.first, valueDate.second)
            item.id = id
            item.kindRaw = row[1]
            item.customName = row[2].ifEmpty { null }
            item.sourceRaw = row[5]
            store.insert(item)
            result.added += 1
        }
        store.save()
        return result
    }

    /** Broj kao `"\(value)"` u Swiftu za vrijednosti iz aplikacije (80.0, 82.5). */
    internal fun number(value: Double?): String = value?.toString() ?: ""

    private fun parseUUID(text: String): UUID? =
        if (text.length == 36) runCatching { UUID.fromString(text) }.getOrNull() else null
}
