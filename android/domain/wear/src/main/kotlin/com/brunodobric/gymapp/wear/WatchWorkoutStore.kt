package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.training.CardioPart
import com.brunodobric.gymapp.training.RestTimer
import com.brunodobric.gymapp.training.SessionMix
import com.brunodobric.gymapp.training.SetField
import com.brunodobric.gymapp.training.SetFieldValues
import com.brunodobric.gymapp.training.Stopwatch
import com.brunodobric.gymapp.training.WorkoutError
import com.brunodobric.gymapp.units.WeightUnit
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable

/** Slanje mobitelu preko Data Layera (`WatchTransport` na iOS-u). */
interface WatchLink {
    /** Poruka koja mora stići (red za slanje dok mobitel nije dostupan). */
    fun sendReliably(event: WorkoutEvent)

    /** Poruka samo ako je mobitel upravo dostupan; zadnje stanje ionako ide kao podatak ([publishSession]). */
    fun sendIfReachable(event: WorkoutEvent)

    /** Zadnje stanje treninga koji vodi sat, kao podatak ([WearPaths.WATCH_SESSION]); null ga briše. */
    fun publishSession(snapshot: SessionSnapshot?)
}

/** Rezultat mjerenja na satu. */
data class HealthResult(val activeEnergyKilocalories: Double? = null, val averageHeartRate: Double? = null)

/**
 * Mjerenje treninga na satu (Health Services, `WorkoutSessionManager` na iOS-u): puls i kalorije uživo. Trening u
 * Health Connect upisuje mobitel s podacima koje mu sat pošalje. Bez dozvole trening radi i dalje, samo bez pulsa.
 */
interface WatchHealth {
    val isRunning: Boolean

    /** Pokreće mjerenje. Vraća je li pokrenuto. */
    suspend fun start(sessionId: UUID, at: Instant): Boolean

    /** Završava mjerenje i vraća prosječni puls i kalorije. */
    suspend fun end(at: Instant): HealthResult

    fun discard()

    /** Nakon gašenja aplikacije usred treninga mjerenje se nastavlja ako ga sustav još drži. */
    fun recover()
}

enum class Haptic { SUCCESS, FAILURE, CLICK, NOTIFICATION }

/** Greška za prikaz na satu (tekst bira sučelje). */
enum class WatchError { SET_INCOMPLETE, SAVE_FAILED }

/** Stanje koje sat sprema u datoteku (`WatchStateFile` na iOS-u), da trening preživi gašenje aplikacije. */
@Serializable
data class WatchStateFile(
    val context: WatchContextPayload = WatchContextPayload.EMPTY,
    val active: SessionSnapshot? = null,
    val mirrorBase: SessionSnapshot? = null,
    @Serializable(com.brunodobric.gymapp.model.UUIDSerializer::class) val mirrorHealthSessionId: UUID? = null,
) {
    fun encode(): String = WearCoding.json.encodeToString(serializer(), this)

    companion object {
        fun decode(text: String): WatchStateFile? = runCatching { WearCoding.json.decodeFromString(serializer(), text) }.getOrNull()
    }
}

interface WatchStateStorage {
    fun save(state: WatchStateFile)
    fun load(): WatchStateFile?
}

/** Sažetak završenog treninga na satu (kao sažetak na mobitelu). */
data class WatchSummary(
    val name: String,
    val durationSeconds: Long,
    /** Završene serije bez kardio vježbi. */
    val completedSets: Int,
    val volumeKg: Double,
    val mix: SessionMix,
    val cardio: CardioPart?,
    val activeEnergyKilocalories: Double?,
    val averageHeartRate: Double?,
)

/** Sve što ekrani na satu prikazuju. */
data class WatchUiState(
    val context: WatchContextPayload = WatchContextPayload.EMPTY,
    val active: SessionSnapshot? = null,
    val summary: WatchSummary? = null,
    /** Vježba prikazana na ekranu serije. */
    val currentExerciseId: UUID? = null,
    /** Pauza traje (timer još nije istekao). */
    val isResting: Boolean = false,
    /** Sve serije su završene: nudi se završetak treninga. */
    val showsFinishPrompt: Boolean = false,
    val error: WatchError? = null,
    /** Trening koji vodi mobitel za koji sat mjeri puls i kalorije. */
    val mirrorHealthSessionId: UUID? = null,
    /** Štoperica serije s trajanjem (kardio, izdržaj). */
    val stopwatch: Stopwatch? = null,
) {
    val unit: WeightUnit get() = context.unit
    val isController: Boolean get() = active?.controllingDevice == DeviceRole.WATCH

    /** Puls i kalorije prikazuju se kad sat mjeri (vodi trening ili ga mjeri za mobitel). */
    val showsHealthMetrics: Boolean get() = isController || (mirrorHealthSessionId != null && mirrorHealthSessionId == active?.id)

    val restTimer: RestTimer? get() = active?.let { SnapshotEngine(it).restTimer }

    val currentExercise: ExerciseSnapshot? get() = currentExerciseId?.let { active?.exercise(it) }

    /** Serija koja je na redu u prikazanoj vježbi (u supersetu može biti iz druge vježbe grupe). */
    val currentSet: Pair<ExerciseSnapshot, SetSnapshot>?
        get() {
            val active = active ?: return null
            val id = currentExerciseId ?: return null
            return SnapshotEngine(active).nextSet(id)
        }

    fun isCardio(exercise: ExerciseSnapshot): Boolean = context.isCardio(exercise.exercise)

    /** "Prošli put" za seriju: vrijednosti iz zadnjeg izvođenja vježbe na istom mjestu. */
    fun previousSet(set: SetSnapshot, exercise: ExerciseSnapshot) =
        exercise.position(set.id)?.let { context.previousSet(exercise.exercise, set.kind, it) }

    fun canMoveExercise(offset: Int): Boolean {
        val active = active ?: return false
        val id = currentExerciseId ?: return false
        val visible = active.visibleExercises
        val group = SnapshotEngine(active).group(id).map { it.id }.toSet()
        val first = visible.indexOfFirst { it.id in group }
        val last = visible.indexOfLast { it.id in group }
        if (first < 0) return false
        return if (offset < 0) first > 0 else last < visible.size - 1
    }
}

/** Vrijednosti serije za polja koja mijenja kruna. */
val SetSnapshot.fieldValues: SetFieldValues
    get() = SetFieldValues(weightKg, reps, extraWeightKg, durationSeconds, distanceMeters)

fun SetSnapshot.with(values: SetFieldValues): SetSnapshot = copy(
    weightKg = values.weightKg, reps = values.reps, extraWeightKg = values.extraWeightKg,
    durationSeconds = values.durationSeconds, distanceMeters = values.distanceMeters,
)

/**
 * Stanje aplikacije na satu (`WatchWorkoutStore` na iOS-u): kontekst s mobitela, aktivni trening i sažetak završenog.
 *
 * * Trening koji vodi sat mijenja se lokalno preko [SnapshotEngine], sprema u datoteku i šalje mobitelu kao snimka.
 *   Završni zapis ide zajamčenim kanalom, pa stigne i kad je mobitel dio vremena izvan dosega.
 * * Trening koji vodi mobitel ovdje se zrcali: izmjene se odmah prikazuju i šalju mobitelu kao naredbe. Ako je mobitel
 *   zatražio mjerenje ([phoneRequestedHealthSession]), sat mjeri puls i kalorije i na kraju ih javlja mobitelu.
 *
 * Sve metode se pozivaju s iste niti (glavne), a [scope] na njoj izvodi odgođene radnje.
 */
class WatchWorkoutStore(
    private val link: WatchLink,
    private val health: WatchHealth,
    private val storage: WatchStateStorage,
    private val scope: CoroutineScope,
    private val haptics: (Haptic) -> Unit = {},
    private val now: () -> Instant = Instant::now,
) {
    private var context = WatchContextPayload.EMPTY
    private var active: SessionSnapshot? = null
    private var summary: WatchSummary? = null
    private var currentExerciseId: UUID? = null
    private var isResting = false
    private var showsFinishPrompt = false
    private var error: WatchError? = null
    private var mirrorHealthSessionId: UUID? = null
    private var stopwatch: Stopwatch? = null

    /** Zrcaljeni trening: stanje koje mobitel već zna (osnova za razliku). */
    private var mirrorBase: SessionSnapshot? = null
    private var pendingSend: Job? = null
    private var restJob: Job? = null
    private var isFinishing = false

    /** Mobitel je zatražio mjerenje, a snimka njegovog treninga još nije stigla. */
    private var mirrorHealthRequestedAt: Instant? = null

    /** Zatvaranje mjerenja koje je u tijeku: novo mjerenje čeka da završi. */
    private var mirrorHealthEnding: Job? = null
    private var mirrorHealthFallback: Job? = null

    private val mutableState = MutableStateFlow(WatchUiState())
    val state: StateFlow<WatchUiState> = mutableState.asStateFlow()

    private val isController: Boolean get() = active?.controllingDevice == DeviceRole.WATCH

    private fun emit() {
        mutableState.value = currentSnapshotState()
    }

    private fun currentSnapshotState() = WatchUiState(
        context, active, summary, currentExerciseId, isResting, showsFinishPrompt, error, mirrorHealthSessionId, stopwatch,
    )

    // MARK: Pokretanje

    fun start() {
        restore()
        // Trening završen ili odbačen prije gašenja aplikacije: završni zapis ide mobitelu (opet, bez štete, jer
        // mobitel prepoznaje duplikat), a sat se vraća na početni ekran.
        active?.let { snapshot ->
            if (snapshot.state != SessionState.ACTIVE) {
                if (isController) publish(snapshot, reliably = true)
                clearActive()
            }
        }
        if (isController || mirrorHealthSessionId != null) health.recover()
        // Mjerenje za trening s mobitela koji je u međuvremenu završio: čeka se završni zapis, ali ne zauvijek.
        mirrorHealthSessionId?.let { id -> if (active?.id != id) scheduleMirrorHealthFallback(id) }
        selectCurrentExercise()
        scheduleRestAlert()
        emit()
    }

    // MARK: Trening na satu

    fun begin(plan: PlannedWorkoutPayload) {
        if (active != null) return
        val snapshot = SnapshotEngine.start(plan, DeviceRole.WATCH, now = now())
        active = snapshot
        summary = null
        showsFinishPrompt = false
        currentExerciseId = snapshot.visibleExercises.firstOrNull()?.id
        persist()
        publish(snapshot, reliably = true)
        // Mjerenje za prethodni trening s mobitela koje još čeka završni zapis zatvara se odmah.
        mirrorHealthSessionId?.let { endMirrorHealth(it, finishedAt = now()) }
        val ending = mirrorHealthEnding
        scope.launch {
            ending?.join()
            health.start(snapshot.id, snapshot.startedAt)
        }
        emit()
    }

    fun completeCurrentSet() {
        val (exercise, set) = currentSnapshotState().currentSet ?: return
        // Izmjereno vrijeme štoperice ide u seriju prije kvačice.
        stopwatch?.takeIf { it.setId == set.id }?.let { watch ->
            val seconds = watch.elapsedSeconds(now())
            if (seconds > 0) mutate { it.updateSet(set.id, now()) { s -> s.copy(durationSeconds = seconds) } }
        }
        try {
            val watchContext = context
            mutate { it.completeSet(set.id, watchContext.restDefaults, { ref -> watchContext.isCompound(ref) }, now()) }
        } catch (_: WorkoutError.SetIncomplete) {
            haptics(Haptic.FAILURE)
            error = WatchError.SET_INCOMPLETE
            emit()
            return
        } catch (_: Exception) {
            error = WatchError.SAVE_FAILED
            emit()
            return
        }
        haptics(Haptic.SUCCESS)
        if (stopwatch?.setId == set.id) stopwatch = null
        val snapshot = active ?: return
        val engine = SnapshotEngine(snapshot)
        val next = engine.exerciseAfterCompleting(exercise.id)
        if (next != null) {
            // U supersetu ostaje prikazana ista vježba grupe, a serija dolazi po naizmjeničnom redu.
            val shown = currentExerciseId?.let { id -> engine.group(id).map { it.id } }.orEmpty()
            if (next !in shown) currentExerciseId = next
        } else {
            showsFinishPrompt = true
        }
        emit()
    }

    fun setValue(value: Double, field: SetField, setId: UUID) {
        val set = active?.set(setId) ?: return
        val unit = context.unit
        if (field.matches(value, set.fieldValues, unit)) return
        mutate { engine ->
            engine.updateSet(setId, now()) { current ->
                val values = current.fieldValues
                field.apply(value, values, unit)
                current.with(values)
            }
        }
    }

    fun uncomplete(setId: UUID) = mutate { it.uncompleteSet(setId, now()) }

    fun addSet(exerciseId: UUID) {
        mutate { it.addSet(exerciseId, now = now()) }
        currentExerciseId = exerciseId
        showsFinishPrompt = false
        emit()
    }

    fun adjustRest(seconds: Int) = mutate { it.adjustRest(seconds, now()) }

    fun skipRest() = mutate { it.cancelRest(now()) }

    /** Prethodna ili sljedeća vježba (superset se preskače kao cjelina). */
    fun moveExercise(offset: Int) {
        val active = active ?: return
        val engine = SnapshotEngine(active)
        val heads = mutableListOf<UUID>()
        val seenGroups = mutableSetOf<UUID>()
        for (exercise in active.visibleExercises) {
            val group = exercise.supersetGroupId
            if (group != null && !seenGroups.add(group)) continue
            heads += exercise.id
        }
        val currentHead = currentExerciseId?.let { engine.group(it).firstOrNull()?.id } ?: heads.firstOrNull()
        val index = heads.indexOf(currentHead)
        if (index < 0) return
        val target = heads.getOrNull(index + offset) ?: return
        currentExerciseId = target
        showsFinishPrompt = false
        emit()
    }

    fun select(exerciseId: UUID) {
        currentExerciseId = exerciseId
        showsFinishPrompt = false
        emit()
    }

    fun clearError() {
        error = null
        emit()
    }

    /** Pokreće, pauzira ili nastavlja štopericu serije. Štoperica druge serije se odbacuje. */
    fun toggleStopwatch(setId: UUID) {
        val at = now()
        val current = stopwatch
        stopwatch = if (current != null && current.setId == setId) current.toggle(at) else Stopwatch(setId, at)
        haptics(Haptic.CLICK)
        emit()
    }

    // MARK: Kraj

    /** Vraća false kad trening nema nijednu završenu seriju (nudi se odbacivanje). */
    fun finish(): Boolean {
        val snapshot = active ?: return false
        // Završetak je već u tijeku (čeka se mjerenje): to nije trening bez serija.
        if (isFinishing) return true
        val engine = SnapshotEngine(snapshot)
        try {
            engine.finish(now())
        } catch (_: Exception) {
            return false
        }
        if (isController) {
            isFinishing = true
            active = engine.snapshot
            persist()
            emit()
            scope.launch { completeFinish() }
        } else {
            sendCommands(mirrorBase ?: snapshot, engine.snapshot)
            showSummary(engine.snapshot, engine.totalVolumeKg)
            endMirrorHealth(snapshot.id, engine.snapshot.endedAt ?: now())
            clearActive()
        }
        return true
    }

    fun discard() {
        val snapshot = active ?: return
        val engine = SnapshotEngine(snapshot)
        engine.discard(now())
        if (isController) {
            health.discard()
            publish(engine.snapshot, reliably = true)
        } else {
            link.sendReliably(WorkoutEvent(sessionId = snapshot.id, createdAt = now(), origin = DeviceRole.WATCH, kind = WorkoutEvent.Kind.Commands(listOf(WorkoutCommand.Discard))))
            endMirrorHealth(snapshot.id, finishedAt = null)
        }
        clearActive()
    }

    fun closeSummary() {
        summary = null
        emit()
    }

    /** Završetak treninga koji vodi sat: mjerenje se zatvara, a završni zapis s pulsom i kalorijama ide mobitelu. */
    private suspend fun completeFinish() {
        val snapshot = active ?: return
        val result = withTimeoutOrNull(HEALTH_END_TIMEOUT_MILLIS) { health.end(snapshot.endedAt ?: now()) } ?: HealthResult()
        val engine = SnapshotEngine(snapshot)
        engine.recordHealth(result.activeEnergyKilocalories, result.averageHeartRate, now())
        publish(engine.snapshot, reliably = true)
        showSummary(engine.snapshot, engine.totalVolumeKg)
        clearActive()
        isFinishing = false
    }

    private fun showSummary(snapshot: SessionSnapshot, volume: Double) {
        val plans = context
        val isCardio: (ExerciseRef) -> Boolean = { plans.isCardio(it) }
        summary = WatchSummary(
            name = snapshot.name,
            durationSeconds = Duration.between(snapshot.startedAt, snapshot.endedAt ?: now()).seconds,
            completedSets = snapshot.strengthSetCount(isCardio),
            volumeKg = volume,
            mix = snapshot.mix(isCardio),
            cardio = snapshot.cardioPart(isCardio),
            activeEnergyKilocalories = snapshot.activeEnergyKilocalories,
            averageHeartRate = snapshot.averageHeartRate,
        )
    }

    private fun clearActive() {
        pendingSend?.cancel()
        restJob?.cancel()
        active = null
        mirrorBase = null
        currentExerciseId = null
        isResting = false
        showsFinishPrompt = false
        stopwatch = null
        persist()
        emit()
    }

    // MARK: Promjene i slanje

    private fun mutate(change: (SnapshotEngine) -> Unit) {
        val snapshot = active ?: return
        val engine = SnapshotEngine(snapshot)
        change(engine)
        if (engine.snapshot == snapshot) return
        active = engine.snapshot
        persist()
        scheduleSend()
        scheduleRestAlert()
        emit()
    }

    /** Kruna i brzi niz promjena šalju se jednom, nakon kratke stanke. */
    private fun scheduleSend() {
        pendingSend?.cancel()
        pendingSend = scope.launch {
            delay(SEND_DELAY_MILLIS)
            sendPending()
        }
    }

    private fun sendPending() {
        val snapshot = active ?: return
        if (isController) {
            publish(snapshot, reliably = false)
        } else {
            sendCommands(mirrorBase ?: snapshot, snapshot)
            mirrorBase = snapshot
            persist()
        }
    }

    private fun sendCommands(base: SessionSnapshot, edited: SessionSnapshot) {
        val commands = SnapshotDiff.commands(base, edited)
        if (commands.isEmpty()) return
        link.sendReliably(WorkoutEvent(sessionId = edited.id, createdAt = now(), origin = DeviceRole.WATCH, kind = WorkoutEvent.Kind.Commands(commands)))
    }

    /** Snimka treninga koji vodi sat. Uvijek ide i kao podatak, pa mobitel izvan dosega dobije zadnje stanje kad se spoji. */
    private fun publish(snapshot: SessionSnapshot, reliably: Boolean) {
        val event = WorkoutEvent(sessionId = snapshot.id, createdAt = now(), origin = DeviceRole.WATCH, kind = WorkoutEvent.Kind.Snapshot(snapshot))
        if (reliably) link.sendReliably(event) else link.sendIfReachable(event)
        link.publishSession(snapshot)
    }

    // MARK: Primanje

    fun handle(event: WorkoutEvent) {
        when (val kind = event.kind) {
            is WorkoutEvent.Kind.Snapshot -> applyPhoneSnapshot(kind.snapshot)
            is WorkoutEvent.Kind.Commands -> {
                val snapshot = active ?: return
                if (!isController || snapshot.id != event.sessionId || isFinishing) return
                val merged = SnapshotDiff.apply(kind.commands, snapshot, maxOf(now(), event.createdAt))
                when (merged.state) {
                    SessionState.ACTIVE -> {
                        active = merged
                        persist()
                        publish(merged, reliably = false)
                        scheduleRestAlert()
                        selectCurrentExercise()
                        emit()
                    }
                    SessionState.FINISHED -> {
                        // Trening je završen na mobitelu: sat zatvara mjerenje i šalje završni zapis.
                        isFinishing = true
                        active = merged
                        persist()
                        emit()
                        scope.launch { completeFinish() }
                    }
                    SessionState.DISCARDED -> {
                        health.discard()
                        publish(merged, reliably = true)
                        clearActive()
                    }
                }
            }
        }
    }

    /** Kontekst s mobitela ([WearPaths.CONTEXT]). */
    fun handleContext(payload: WatchContextPayload) {
        if (payload == context) return
        context = payload
        persist()
        emit()
    }

    /**
     * Snimka treninga koji vodi mobitel ([WearPaths.PHONE_SESSION]); null kad mobitel više nema aktivan trening.
     * Tada se zrcaljeni trening zatvara, a mjerenje čeka završni zapis (zajamčeni kanal), jer se iz podatka ne vidi
     * je li trening završen ili odbačen.
     */
    fun handlePhoneSession(snapshot: SessionSnapshot?) {
        if (snapshot != null) {
            applyPhoneSnapshot(snapshot)
            return
        }
        val current = active ?: return
        if (current.controllingDevice != DeviceRole.PHONE) return
        if (mirrorHealthSessionId == current.id) scheduleMirrorHealthFallback(current.id)
        clearActive()
    }

    /** Veza s mobitelom je uspostavljena: trening koji vodi sat ide mu kao zadnje stanje. */
    fun connectionChanged() {
        val snapshot = active ?: return
        if (isController) publish(snapshot, reliably = false)
    }

    /** Snimka treninga koji vodi mobitel. Trening koji vodi sat ima prednost i ne prepisuje se. */
    private fun applyPhoneSnapshot(snapshot: SessionSnapshot) {
        if (snapshot.controllingDevice != DeviceRole.PHONE) return
        if (snapshot.state != SessionState.ACTIVE) {
            val finishedAt = if (snapshot.state == SessionState.FINISHED) snapshot.endedAt ?: now() else null
            endMirrorHealth(snapshot.id, finishedAt)
        }
        val current = active
        if (current != null && current.controllingDevice == DeviceRole.WATCH) return
        if (snapshot.state != SessionState.ACTIVE) {
            if (current?.id == snapshot.id) clearActive()
            return
        }
        if (current != null && current.id == snapshot.id && !snapshot.isNewer(current.updatedAt)) return
        active = snapshot
        mirrorBase = snapshot
        summary = null
        persist()
        selectCurrentExercise()
        scheduleRestAlert()
        startMirrorHealthIfNeeded()
        emit()
    }

    // MARK: Pauza

    /** Haptika na kraju odmora: lagani dodir malo prije kraja i jači na kraju. */
    private fun scheduleRestAlert() {
        restJob?.cancel()
        val timer = active?.let { SnapshotEngine(it).restTimer }
        if (timer == null || timer.isExpired(now())) {
            isResting = false
            return
        }
        isResting = true
        restJob = scope.launch {
            val warning = timer.remaining(now()) - REST_WARNING_LEAD_SECONDS
            if (warning > 0) {
                delay((warning * 1000).toLong())
                haptics(Haptic.CLICK)
            }
            delay((timer.remaining(now()) * 1000).toLong())
            haptics(Haptic.NOTIFICATION)
            isResting = false
            // Sat koji vodi trening gasi timer; zrcaljeni čeka da ga ugasi mobitel.
            if (isController) skipRest() else emit()
        }
    }

    private fun selectCurrentExercise() {
        val snapshot = active ?: return
        val current = currentExerciseId?.let { snapshot.exercise(it) }
        if (current != null && !current.isRemoved) return
        val visible = snapshot.visibleExercises
        currentExerciseId = (visible.firstOrNull { !it.isFullyCompleted } ?: visible.firstOrNull())?.id
    }

    // MARK: Spremanje

    private fun persist() {
        runCatching { storage.save(WatchStateFile(context, active, mirrorBase, mirrorHealthSessionId)) }
    }

    private fun restore() {
        val saved = storage.load() ?: return
        context = saved.context
        active = saved.active
        mirrorBase = saved.mirrorBase
        mirrorHealthSessionId = saved.mirrorHealthSessionId
    }

    // MARK: Mjerenje za trening s mobitela

    /** Mobitel je pokrenuo trening i zatražio mjerenje. Pokreće se čim je poznat trening (snimka može stići prije ili poslije). */
    fun phoneRequestedHealthSession() {
        mirrorHealthRequestedAt = now()
        startMirrorHealthIfNeeded()
        emit()
    }

    private fun startMirrorHealthIfNeeded() {
        val requestedAt = mirrorHealthRequestedAt ?: return
        // Stari zahtjev ne smije pokrenuti mjerenje za neki kasniji trening.
        if (Duration.between(requestedAt, now()).seconds >= MIRROR_REQUEST_LIFETIME_SECONDS) {
            mirrorHealthRequestedAt = null
            return
        }
        val snapshot = active ?: return
        if (snapshot.controllingDevice != DeviceRole.PHONE || snapshot.state != SessionState.ACTIVE) return
        if (mirrorHealthSessionId != null || health.isRunning) return
        mirrorHealthRequestedAt = null
        val id = snapshot.id
        mirrorHealthSessionId = id
        persist()
        val ending = mirrorHealthEnding
        scope.launch {
            ending?.join()
            if (!health.start(id, snapshot.startedAt)) {
                // Bez dozvole trening ide dalje bez pulsa.
                if (mirrorHealthSessionId == id) {
                    mirrorHealthSessionId = null
                    persist()
                    emit()
                }
                return@launch
            }
            if (mirrorHealthSessionId != id) {
                // Trening je završen ili odbačen dok se mjerenje pokretalo.
                health.discard()
                return@launch
            }
            link.sendReliably(WorkoutEvent(sessionId = id, createdAt = now(), origin = DeviceRole.WATCH, kind = WorkoutEvent.Kind.Commands(listOf(WorkoutCommand.HealthRecordingStarted))))
        }
    }

    /** Zatvara mjerenje za trening koji vodi mobitel. Za završen trening mobitel dobiva puls i kalorije; odbačen se odbacuje. */
    private fun endMirrorHealth(sessionId: UUID, finishedAt: Instant?) {
        if (mirrorHealthSessionId != sessionId) return
        mirrorHealthSessionId = null
        mirrorHealthFallback?.cancel()
        mirrorHealthFallback = null
        persist()
        emit()
        if (finishedAt == null) {
            health.discard()
            return
        }
        val previous = mirrorHealthEnding
        mirrorHealthEnding = scope.launch {
            previous?.join()
            val result = withTimeoutOrNull(HEALTH_END_TIMEOUT_MILLIS) { health.end(finishedAt) } ?: HealthResult()
            val report = WorkoutCommand.HealthRecorded(result.activeEnergyKilocalories, result.averageHeartRate)
            link.sendReliably(WorkoutEvent(sessionId = sessionId, createdAt = now(), origin = DeviceRole.WATCH, kind = WorkoutEvent.Kind.Commands(listOf(report))))
            summary?.let { current ->
                summary = current.copy(
                    activeEnergyKilocalories = current.activeEnergyKilocalories ?: result.activeEnergyKilocalories,
                    averageHeartRate = current.averageHeartRate ?: result.averageHeartRate,
                )
                emit()
            }
        }
    }

    /**
     * Završni zapis s mobitela stiže zajamčenim kanalom, ali mobitel može ostati izvan dosega. Da mjerenje ne radi
     * satima, nakon čekanja se zatvara kao završen trening.
     */
    private fun scheduleMirrorHealthFallback(sessionId: UUID) {
        mirrorHealthFallback?.cancel()
        mirrorHealthFallback = scope.launch {
            delay(MIRROR_FALLBACK_DELAY_MILLIS)
            endMirrorHealth(sessionId, now())
        }
    }

    companion object {
        const val SEND_DELAY_MILLIS = 300L
        const val REST_WARNING_LEAD_SECONDS = 10.0
        const val HEALTH_END_TIMEOUT_MILLIS = 10_000L
        const val MIRROR_REQUEST_LIFETIME_SECONDS = 120L
        const val MIRROR_FALLBACK_DELAY_MILLIS = 5 * 60_000L
    }
}
