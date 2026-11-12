package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.uppercaseString
import kotlinx.serialization.KSerializer
import java.time.Instant
import java.util.UUID

/** Jedan spremljeni zapis: vrsta, id i sadržaj kao JSON. */
data class StoredRecord(val type: String, val id: String, val json: String)

/**
 * Trajno spremanje zapisa. Na Androidu je to SQLite tablica (type, id, json), u testovima popis u memoriji.
 * [write] dobiva samo promijenjene i obrisane zapise.
 */
interface RecordPersistence {
    fun loadAll(): List<StoredRecord>
    fun write(upserts: List<StoredRecord>, deletes: List<Pair<String, String>>)
}

class InMemoryPersistence(initial: List<StoredRecord> = emptyList()) : RecordPersistence {
    val records = linkedMapOf<Pair<String, String>, StoredRecord>().apply {
        initial.forEach { put(it.type to it.id, it) }
    }
    var writeCount = 0
        private set

    override fun loadAll(): List<StoredRecord> = records.values.toList()

    override fun write(upserts: List<StoredRecord>, deletes: List<Pair<String, String>>) {
        writeCount++
        deletes.forEach { records.remove(it) }
        upserts.forEach { records[it.type to it.id] = it }
    }
}

/**
 * Korisnička baza u memoriji: graf zapisa (trening → vježbe → serije, predložak → vježbe → serije,
 * raspored → stavke) koji se pri [save] zapisuje u [RecordPersistence].
 *
 * Isto mjesto koje na iOS-u ima SwiftDatin `ModelContext`: logika mijenja objekte, a [save] sprema.
 * Upiti idu nad memorijom, pa su trenutni i ne opterećuju bazu (podaci jednog korisnika su mali: dvije
 * godine treninga je desetak tisuća serija). Sprema se samo ono što se promijenilo, a [revision] raste
 * nakon svakog spremanja s promjenom (`DataVersion` na iOS-u), pa se statistika i kartice preračunavaju
 * kad se podaci stvarno promijene.
 *
 * Nije za više niti: aplikacija ga koristi s glavne niti, a teški izračuni rade nad kopijama podataka.
 */
class GymStore(internal val persistence: RecordPersistence = InMemoryPersistence()) {
    val customExercises = mutableListOf<CustomExercise>()
    val templates = mutableListOf<WorkoutTemplate>()
    val schedules = mutableListOf<Schedule>()
    val cycleOverrides = mutableListOf<CycleOverride>()
    val sessions = mutableListOf<Session>()
    val bodyMeasurements = mutableListOf<BodyMeasurement>()
    val dashboardCards = mutableListOf<DashboardCard>()
    val settingsRecords = mutableListOf<UserSettings>()

    /** Raste nakon svakog spremanja koje je nešto promijenilo. */
    var revision: Long = 0
        private set

    private val listeners = mutableListOf<(Long) -> Unit>()

    /** Podaci iz Health Connecta (zasebna lokalna baza): samo za prikaz, ne spremaju se ovdje ni u kopiju. */
    var health: HealthLocalSource = HealthLocalSource.None

    /** Lokalni podaci iz Health Connecta su se promijenili: ekrani se osvježavaju kao nakon spremanja. */
    fun healthChanged() {
        revision++
        listeners.toList().forEach { it(revision) }
    }

    /** Zadnje spremljeno stanje, po (vrsta, id). */
    private var saved: Map<Pair<String, String>, StoredRecord> = emptyMap()

    init {
        load(persistence.loadAll())
    }

    fun addListener(listener: (Long) -> Unit) {
        listeners += listener
    }

    fun removeListener(listener: (Long) -> Unit) {
        listeners -= listener
    }

    // MARK: Umetanje i brisanje

    /** Umeće zapis najviše razine. Djecu (vježbe, serije, stavke) dodaje roditelj (`session.add`). */
    fun <T : GymRecord> insert(record: T): T {
        when (record) {
            is CustomExercise -> customExercises.addIfAbsent(record)
            is WorkoutTemplate -> templates.addIfAbsent(record)
            is Schedule -> schedules.addIfAbsent(record)
            is CycleOverride -> cycleOverrides.addIfAbsent(record)
            is Session -> sessions.addIfAbsent(record)
            is BodyMeasurement -> bodyMeasurements.addIfAbsent(record)
            is DashboardCard -> dashboardCards.addIfAbsent(record)
            is UserSettings -> settingsRecords.addIfAbsent(record)
            is TemplateExercise, is TemplateSet, is ScheduleItem, is SessionExercise, is SetLog ->
                error("${record::class.simpleName} se dodaje preko roditelja")
        }
        return record
    }

    /** Briše zapis i njegovu djecu (kao `deleteRule: .cascade`). */
    fun delete(record: GymRecord) {
        when (record) {
            is CustomExercise -> customExercises.removeAll { it === record }
            is WorkoutTemplate -> templates.removeAll { it === record }
            is Schedule -> schedules.removeAll { it === record }
            is CycleOverride -> cycleOverrides.removeAll { it === record }
            is Session -> sessions.removeAll { it === record }
            is BodyMeasurement -> bodyMeasurements.removeAll { it === record }
            is DashboardCard -> dashboardCards.removeAll { it === record }
            is UserSettings -> settingsRecords.removeAll { it === record }
            is TemplateExercise -> record.template?.exercises?.removeAll { it === record }
            is TemplateSet -> record.exercise?.sets?.removeAll { it === record }
            is ScheduleItem -> record.schedule?.items?.removeAll { it === record }
            is SessionExercise -> record.session?.exercises?.removeAll { it === record }
            is SetLog -> record.exercise?.sets?.removeAll { it === record }
        }
    }

    // MARK: Spremanje

    /** Ima li izmjena koje nisu spremljene. */
    fun hasChanges(): Boolean = snapshot() != saved

    /** Sprema promijenjene i obrisane zapise. Vraća broj promjena (0 kad nije bilo ničega). */
    fun save(): Int {
        val current = snapshot()
        val upserts = current.values.filter { saved[it.type to it.id] != it }
        val deletes = saved.keys.filter { it !in current }
        if (upserts.isEmpty() && deletes.isEmpty()) return 0
        persistence.write(upserts, deletes)
        saved = current
        revision++
        listeners.toList().forEach { it(revision) }
        return upserts.size + deletes.size
    }

    /**
     * Svi zapisi u bazi nakon spremanja izmjena, i oni koji se ne učitavaju (bez roditelja ili iz novije verzije).
     * Za sinkronizaciju: ono što je na uređaju, a ne samo učitani graf.
     */
    fun persistedRecords(): List<StoredRecord> {
        save()
        return persistence.loadAll()
    }

    /**
     * Zapisi koji su stigli s drugog uređaja (sinkronizacija): spremaju se u bazu i graf se ponovno učitava.
     * Prije toga se spremaju lokalne izmjene. Objekti koje je ekran držao nakon toga više nisu u grafu, pa se
     * zove samo kad nijedan uređivač ni trening nisu otvoreni.
     */
    fun applyExternal(upserts: List<StoredRecord>, deletes: List<Pair<String, String>>) {
        save()
        if (upserts.isEmpty() && deletes.isEmpty()) return
        persistence.write(upserts, deletes)
        load(persistence.loadAll())
        revision++
        listeners.toList().forEach { it(revision) }
    }

    /** Ključevi (vrsta, id) treninga u tijeku i njegovih vježbi i serija: sinkroniziraju se tek kad trening završi. */
    fun activeSessionKeys(): Set<Pair<String, String>> {
        val result = mutableSetOf<Pair<String, String>>()
        for (session in sessions.filter { it.state == SessionState.ACTIVE }) {
            result += encodeType(session) to session.id.uppercaseString
            for (exercise in session.exercises) {
                result += encodeType(exercise) to exercise.id.uppercaseString
                exercise.sets.forEach { result += encodeType(it) to it.id.uppercaseString }
            }
        }
        return result
    }

    /** Odbacuje nespremljene izmjene: graf se vraća na zadnje spremljeno stanje. */
    fun rollback() {
        load(saved.values.toList())
    }

    // MARK: Svi zapisi

    val templateExercises: List<TemplateExercise> get() = templates.flatMap { it.exercises }
    val scheduleItems: List<ScheduleItem> get() = schedules.flatMap { it.items }
    val sessionExercises: List<SessionExercise> get() = sessions.flatMap { it.exercises }
    val setLogs: List<SetLog> get() = sessionExercises.flatMap { it.sets }

    private fun allRecords(): Sequence<GymRecord> = sequence {
        yieldAll(customExercises)
        for (template in templates) {
            yield(template)
            for (exercise in template.exercises) {
                yield(exercise)
                yieldAll(exercise.sets)
            }
        }
        for (schedule in schedules) {
            yield(schedule)
            yieldAll(schedule.items)
        }
        yieldAll(cycleOverrides)
        for (session in sessions) {
            yield(session)
            for (exercise in session.exercises) {
                yield(exercise)
                yieldAll(exercise.sets)
            }
        }
        yieldAll(bodyMeasurements)
        yieldAll(dashboardCards)
        yieldAll(settingsRecords)
    }

    private fun snapshot(): Map<Pair<String, String>, StoredRecord> {
        val result = LinkedHashMap<Pair<String, String>, StoredRecord>()
        for (record in allRecords()) {
            val stored = encode(record)
            result[stored.type to stored.id] = stored
        }
        return result
    }

    private fun load(records: List<StoredRecord>) {
        customExercises.clear(); templates.clear(); schedules.clear(); cycleOverrides.clear()
        sessions.clear(); bodyMeasurements.clear(); dashboardCards.clear(); settingsRecords.clear()

        val byType = records.groupBy { it.type }
        fun <T> decodeAll(type: RecordType<T>): List<T> =
            byType[type.name].orEmpty().mapNotNull { runCatching { RecordJson.decodeFromString(type.serializer, it.json) }.getOrNull() }

        customExercises += decodeAll(RecordType.CustomExercise)
        cycleOverrides += decodeAll(RecordType.CycleOverride)
        bodyMeasurements += decodeAll(RecordType.BodyMeasurement)
        dashboardCards += decodeAll(RecordType.DashboardCard)
        settingsRecords += decodeAll(RecordType.UserSettings)

        val templateById = decodeAll(RecordType.WorkoutTemplate).associateBy { it.id }
        templates += templateById.values
        val templateExerciseById = LinkedHashMap<UUID, TemplateExercise>()
        for (exercise in decodeAll(RecordType.TemplateExercise)) {
            val parent = exercise.templateId?.let(templateById::get) ?: continue
            parent.add(exercise)
            templateExerciseById[exercise.id] = exercise
        }
        for (set in decodeAll(RecordType.TemplateSet)) {
            set.exerciseId?.let(templateExerciseById::get)?.add(set)
        }

        val scheduleById = decodeAll(RecordType.Schedule).associateBy { it.id }
        schedules += scheduleById.values
        for (item in decodeAll(RecordType.ScheduleItem)) {
            item.scheduleId?.let(scheduleById::get)?.add(item)
        }

        val sessionById = decodeAll(RecordType.Session).associateBy { it.id }
        sessions += sessionById.values
        val sessionExerciseById = LinkedHashMap<UUID, SessionExercise>()
        for (exercise in decodeAll(RecordType.SessionExercise)) {
            val parent = exercise.sessionId?.let(sessionById::get) ?: continue
            parent.add(exercise)
            sessionExerciseById[exercise.id] = exercise
        }
        for (set in decodeAll(RecordType.SetLog)) {
            set.exerciseId?.let(sessionExerciseById::get)?.add(set)
        }
        // Zapisi bez roditelja i oni koji se ne mogu pročitati (iz novije verzije) ne učitavaju se, ali ostaju
        // u bazi netaknuti: `saved` je samo učitani graf, pa ih spremanje ne briše.
        saved = snapshot()
    }

    // MARK: Upiti (GymQueries na iOS-u)

    /** Trening koji je trenutno u tijeku. Ako ih je više, vraća najnoviji. */
    fun activeSession(): Session? = sessions.filter { it.state == SessionState.ACTIVE }.maxByOrNull { it.startedAt }

    /**
     * Završeni treninzi čiji je početak u rasponu [from, to), od najnovijeg prema starijem. Kao na iOS-u
     * uključuje treninge uvezene iz Health Connecta (iz [health], kao `Session` za prikaz), pa ih broje
     * statistika, tjedni napredak i podsjetnici.
     */
    fun finishedSessions(from: Instant = Instant.MIN, to: Instant = Instant.MAX): List<Session> = mergedSessions(
        ownFinishedSessions(from, to),
        health.workouts.filter { it.startedAt >= from && it.startedAt < to },
    )

    /** Samo vlastiti završeni treninzi (sigurnosna kopija, rekordi u widgetu), od najnovijeg prema starijem. */
    fun ownFinishedSessions(from: Instant = Instant.MIN, to: Instant = Instant.MAX): List<Session> =
        sessions.filter { it.state == SessionState.FINISHED && it.startedAt >= from && it.startedAt < to }
            .sortedByDescending { it.startedAt }

    /** Zadnje izvođenje vježbe u završenom treningu (smart defaults i inline povijest). */
    fun lastPerformance(exercise: ExerciseRef): SessionExercise? {
        val key = exercise.key
        return sessions.asSequence()
            .filter { it.state == SessionState.FINISHED }
            .flatMap { session -> session.exercises.asSequence().filter { it.exerciseKey == key && !it.isRemoved } }
            .maxByOrNull { it.session?.startedAt ?: Instant.MIN }
    }

    /** Sva izvođenja vježbe u završenim treninzima, od najnovijeg. */
    fun finishedPerformances(key: String): List<SessionExercise> =
        sessions.asSequence()
            .filter { it.state == SessionState.FINISHED }
            .sortedByDescending { it.startedAt }
            .flatMap { session -> session.exercises.asSequence().filter { it.exerciseKey == key && !it.isRemoved } }
            .toList()

    /**
     * Jedini zapis postavki. Ako ga nema, stvara se sa zadanim vrijednostima.
     * Ako ih zbog sinkronizacije ili uvoza ima više, vraća onaj koji bi ostao nakon uklanjanja duplikata.
     */
    fun settings(): UserSettings = UserSettingsChoice.preferred(settingsRecords) ?: insert(UserSettings())

    fun customExercise(id: UUID): CustomExercise? = customExercises.firstOrNull { it.id == id }

    fun template(id: UUID): WorkoutTemplate? = templates.firstOrNull { it.id == id }

    fun schedule(id: UUID): Schedule? = schedules.firstOrNull { it.id == id }

    fun session(id: UUID): Session? = sessions.firstOrNull { it.id == id }

    companion object {
        internal fun encode(record: GymRecord): StoredRecord {
            val type = RecordType.of(record)
            @Suppress("UNCHECKED_CAST")
            val json = RecordJson.encodeToString(type.serializer as KSerializer<GymRecord>, record)
            return StoredRecord(type.name, record.id.uppercaseString, json)
        }

        internal fun encodeType(record: GymRecord): String = RecordType.of(record).name
    }
}

private fun <T> MutableList<T>.addIfAbsent(element: T) {
    if (none { it === element }) add(element)
}

/** Vrste zapisa i njihovi serijalizatori. Naziv vrste je isti kao naziv modela na iOS-u. */
internal class RecordType<T> private constructor(val name: String, val serializer: KSerializer<T>) {
    companion object {
        val CustomExercise = RecordType("CustomExercise", com.brunodobric.gymapp.model.CustomExercise.serializer())
        val WorkoutTemplate = RecordType("WorkoutTemplate", com.brunodobric.gymapp.model.WorkoutTemplate.serializer())
        val TemplateExercise = RecordType("TemplateExercise", com.brunodobric.gymapp.model.TemplateExercise.serializer())
        val TemplateSet = RecordType("TemplateSet", com.brunodobric.gymapp.model.TemplateSet.serializer())
        val Schedule = RecordType("Schedule", com.brunodobric.gymapp.model.Schedule.serializer())
        val ScheduleItem = RecordType("ScheduleItem", com.brunodobric.gymapp.model.ScheduleItem.serializer())
        val CycleOverride = RecordType("CycleOverride", com.brunodobric.gymapp.model.CycleOverride.serializer())
        val Session = RecordType("Session", com.brunodobric.gymapp.model.Session.serializer())
        val SessionExercise = RecordType("SessionExercise", com.brunodobric.gymapp.model.SessionExercise.serializer())
        val SetLog = RecordType("SetLog", com.brunodobric.gymapp.model.SetLog.serializer())
        val BodyMeasurement = RecordType("BodyMeasurement", com.brunodobric.gymapp.model.BodyMeasurement.serializer())
        val DashboardCard = RecordType("DashboardCard", com.brunodobric.gymapp.model.DashboardCard.serializer())
        val UserSettings = RecordType("UserSettings", com.brunodobric.gymapp.model.UserSettings.serializer())

        fun of(record: GymRecord): RecordType<*> = when (record) {
            is com.brunodobric.gymapp.model.CustomExercise -> CustomExercise
            is com.brunodobric.gymapp.model.WorkoutTemplate -> WorkoutTemplate
            is com.brunodobric.gymapp.model.TemplateExercise -> TemplateExercise
            is com.brunodobric.gymapp.model.TemplateSet -> TemplateSet
            is com.brunodobric.gymapp.model.Schedule -> Schedule
            is com.brunodobric.gymapp.model.ScheduleItem -> ScheduleItem
            is com.brunodobric.gymapp.model.CycleOverride -> CycleOverride
            is com.brunodobric.gymapp.model.Session -> Session
            is com.brunodobric.gymapp.model.SessionExercise -> SessionExercise
            is com.brunodobric.gymapp.model.SetLog -> SetLog
            is com.brunodobric.gymapp.model.BodyMeasurement -> BodyMeasurement
            is com.brunodobric.gymapp.model.DashboardCard -> DashboardCard
            is com.brunodobric.gymapp.model.UserSettings -> UserSettings
        }
    }
}
