package com.brunodobric.gymapp.wear

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.appwidgets.widgetSnapshots
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.WeightStepSettings
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import java.time.Duration
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Veza aplikacije na mobitelu sa satom (`PhoneWatchSync` na iOS-u; specifikacija, odjeljak 6).
 *
 * * Trening koji vodi sat stiže kao snimka i upisuje se u bazu (bez duplikata, zadnja promjena pobjeđuje). Izmjene na
 *   mobitelu šalju se satu kao naredbe (razlika prema zadnjoj snimci sa sata).
 * * Trening koji vodi mobitel šalje se satu kao snimka, a naredbe sa sata upisuju se u bazu.
 * * Satu se šalje kontekst: sljedeći treninzi, predlošci s pretpunjenim serijama, jedinica i pauza.
 *
 * Sve radi na glavnoj niti; Data Layer pozivi idu u pozadini. Bez sata s aplikacijom ne radi ništa.
 */
class PhoneWatchSync(context: Context, private val services: AppServices) {
    private val appContext = context.applicationContext
    private val scope = MainScope()
    private val handler = Handler(Looper.getMainLooper())
    private val data = Wearable.getDataClient(appContext)
    private val messages = Wearable.getMessageClient(appContext)
    private val capabilities = Wearable.getCapabilityClient(appContext)
    private val deduplicator = WorkoutEventDeduplicator()
    private val store get() = services.store

    /** Sat s aplikacijom je uparen (ne mora biti u dosegu). */
    private var hasWatch = false

    /** Zadnja poznata snimka treninga koji vodi sat: osnova za razliku kad se trening mijenja na mobitelu. */
    private val watchBases = mutableMapOf<UUID, SessionSnapshot>()

    /** Zadnja snimka treninga s mobitela poslana satu. */
    private var lastSent: SessionSnapshot? = null

    /** Zadnji kontekst poslan satu, bez vremena nastanka. */
    private var lastContext: WatchContextPayload? = null

    /** Trening s mobitela za koji je sat već pozvan da mjeri. */
    private var requestedHealthFor: UUID? = null

    private val pendingFlush = Runnable { flush() }
    private val pendingContext = Runnable { sendContext() }

    fun start() {
        store.addListener {
            if (!hasWatch) return@addListener
            schedule()
            handler.removeCallbacks(pendingContext)
            handler.postDelayed(pendingContext, CONTEXT_DELAY_MILLIS)
        }
        SessionSnapshotStore(store).purgeDiscarded()
        refreshWatch()
    }

    /** Provjerava je li sat uparen i, ako jest, čita ono što je sat poslao dok aplikacija nije radila. */
    fun refreshWatch() {
        scope.launch {
            hasWatch = runCatching {
                capabilities.getCapability(WearPaths.WATCH_CAPABILITY, CapabilityClient.FILTER_ALL).await().nodes.isNotEmpty()
            }.getOrDefault(false)
            if (!hasWatch) return@launch
            readPending()
            lastContext = null
            sendContext()
            flush()
        }
    }

    private suspend fun readPending() {
        val items = runCatching {
            val buffer = data.dataItems.await()
            try {
                buffer.mapNotNull { item -> item.data?.let { Triple(item.uri.path.orEmpty(), item.uri, it) } }
            } finally {
                buffer.release()
            }
        }.getOrDefault(emptyList())
        for ((path, uri, bytes) in items) receiveData(path, uri, bytes)
    }

    // MARK: Slanje

    private fun schedule() {
        handler.removeCallbacks(pendingFlush)
        handler.postDelayed(pendingFlush, FLUSH_DELAY_MILLIS)
    }

    private fun weightSteps(): (ExerciseRef) -> Double? {
        val resolver = WeightStepSettings.resolver(store.settings(), services.catalog, store.customExercises)
        return { resolver(it) }
    }

    /** Šalje satu promjene treninga s mobitela (snimka) ili treninga koji vodi sat (naredbe). */
    private fun flush() {
        handler.removeCallbacks(pendingFlush)
        if (!hasWatch) return
        val weightStep = weightSteps()
        val active = store.activeSession()?.takeIf { it.controllingDevice == DeviceRole.PHONE }
        if (active != null) {
            if (requestedHealthFor != active.id) sessionStarted(active)
            broadcast(active.snapshot(weightStep))
        } else {
            lastSent?.let { previous ->
                // Trening s mobitela je završen ili odbačen (obrisan): sat dobiva završni zapis zajamčeno.
                val final = store.session(previous.id)?.snapshot(weightStep)
                    ?: previous.copy(state = SessionState.DISCARDED, updatedAt = Instant.now().truncatedTo(ChronoUnit.MILLIS))
                broadcast(final)
            }
        }
        for ((id, base) in watchBases.toMap()) {
            val session = store.session(id)
            if (session == null) {
                // Trening sa sata obrisan je na mobitelu.
                send(id, listOf(WorkoutCommand.Discard))
                watchBases.remove(id)
                continue
            }
            if (session.controllingDevice != DeviceRole.WATCH) continue
            val snapshot = session.snapshot(weightStep)
            val commands = SnapshotDiff.commands(base, snapshot)
            if (commands.isEmpty()) continue
            send(id, commands)
            watchBases[id] = snapshot
        }
    }

    /** Snimka treninga koji vodi mobitel: odmah ako je sat dostupan, a uvijek i kao zadnje stanje. */
    private fun broadcast(snapshot: SessionSnapshot) {
        if (snapshot == lastSent) return
        val event = WorkoutEvent(sessionId = snapshot.id, origin = DeviceRole.PHONE, kind = WorkoutEvent.Kind.Snapshot(snapshot))
        if (snapshot.state == SessionState.ACTIVE) {
            lastSent = snapshot
            sendIfReachable(event)
            put(WearPaths.PHONE_SESSION, WearCoding.encodeSnapshot(snapshot))
        } else {
            lastSent = null
            sendReliably(event)
            delete(WearPaths.PHONE_SESSION)
            handler.removeCallbacks(pendingContext)
            handler.post(pendingContext)
        }
    }

    /**
     * Trening je upravo pokrenut na mobitelu. Ako je to uključeno u Postavkama, sat se poziva da mjeri puls i
     * kalorije (vidi `WorkoutCommand.HealthRecordingStarted`). Stari trening (nakon ponovnog pokretanja) se ne javlja.
     */
    private fun sessionStarted(session: Session) {
        requestedHealthFor = session.id
        if (session.kind != WorkoutKind.STRENGTH || !store.settings().startsWatchWorkout) return
        if (Duration.between(session.startedAt, Instant.now()).seconds > HEALTH_REQUEST_WINDOW_SECONDS) return
        scope.launch {
            runCatching {
                for (node in reachableWatches()) messages.sendMessage(node, WearPaths.HEALTH_REQUEST, ByteArray(0)).await()
            }
        }
    }

    private fun send(sessionId: UUID, commands: List<WorkoutCommand>) {
        sendReliably(WorkoutEvent(sessionId = sessionId, origin = DeviceRole.PHONE, kind = WorkoutEvent.Kind.Commands(commands)))
    }

    /** Kontekst za sat; isti se ne šalje ponovno (svaka izmjena baze ga inače složi iznova). */
    private fun sendContext() {
        handler.removeCallbacks(pendingContext)
        if (!hasWatch) return
        val info = ExerciseInfoBuilder.provider(services.catalog, store.customExercises)
        // Tjedni cilj i težina za sat, iz iste snimke kao widgeti na mobitelu.
        val widgets = runCatching { widgetSnapshots(appContext).load() }.getOrNull()
        val context = runCatching {
            WatchContextBuilder(
                store,
                isCardio = ExerciseInfoBuilder.isCardio(info),
                isCompound = { key ->
                    if (key.startsWith("c:")) services.catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND } else null
                },
                weightStep = weightSteps(),
            ).make(week = widgets?.week, bodyWeightKg = widgets?.bodyWeight?.latestKg)
        }.getOrNull() ?: return
        val comparable = context.copy(generatedAt = Instant.EPOCH)
        if (comparable == lastContext) return
        lastContext = comparable
        put(WearPaths.CONTEXT, WearCoding.encodeContext(context))
    }

    // MARK: Primanje (s glavne niti)

    fun receiveData(path: String, uri: Uri, bytes: ByteArray?) {
        when {
            path == WearPaths.WATCH_SESSION -> bytes?.let(WearCoding::decodeSnapshot)?.let(::applyWatchSnapshot)
            path.startsWith(WearPaths.EVENT + "/") && bytes != null -> {
                val event = WorkoutEvent.decode(bytes) ?: return
                // Vlastiti događaji ostaju dok ih sat ne obriše.
                if (event.origin == DeviceRole.PHONE) return
                handle(event)
                scope.launch { runCatching { data.deleteDataItems(uri).await() } }
            }
        }
    }

    fun receiveMessage(path: String, bytes: ByteArray) {
        if (path == WearPaths.EVENT) WorkoutEvent.decode(bytes)?.let(::handle)
    }

    fun watchConnectionChanged() {
        refreshWatch()
    }

    private fun handle(event: WorkoutEvent) {
        if (event.origin != DeviceRole.WATCH || !deduplicator.accept(event)) return
        when (val kind = event.kind) {
            is WorkoutEvent.Kind.Snapshot -> applyWatchSnapshot(kind.snapshot)
            is WorkoutEvent.Kind.Commands -> {
                val sessionId = event.sessionId ?: return
                if (kind.commands.any { it.isHealthReport }) SessionSnapshotStore(store).applyWatchHealth(kind.commands, sessionId)
                val edits = kind.commands.filter { !it.isHealthReport }
                if (edits.isNotEmpty()) applyCommands(edits, sessionId, event.createdAt)
            }
        }
    }

    /** Snimka treninga koji vodi sat. Trening koji vodi mobitel ovdje se ne mijenja: mobitel je za njega izvor istine. */
    private fun applyWatchSnapshot(snapshot: SessionSnapshot) {
        if (snapshot.controllingDevice != DeviceRole.WATCH) return
        val base = watchBases[snapshot.id]
        // Starija snimka (npr. iz reda za slanje): osnova ostaje novija.
        if (base == null || !base.updatedAt.isAfter(snapshot.updatedAt)) watchBases[snapshot.id] = snapshot
        val snapshots = SessionSnapshotStore(store)
        when (val outcome = snapshots.apply(snapshot)) {
            is SessionSnapshotStore.Outcome.Applied -> {
                if (snapshot.state == SessionState.FINISHED && outcome.previousState != SessionState.FINISHED) {
                    // Sat je završio trening koji je vodio: raspored napreduje, a mobitel ga upisuje u Health Connect.
                    snapshots.session(snapshot.id)?.let { ScheduleEngine(store).sessionFinished(it) }
                }
                if (snapshot.state != SessionState.ACTIVE) watchBases.remove(snapshot.id)
            }
            SessionSnapshotStore.Outcome.Discarded -> {
                watchBases.remove(snapshot.id)
                purgeLater()
            }
            SessionSnapshotStore.Outcome.IgnoredOlder -> Unit
        }
    }

    /** Naredbe sa sata za trening koji vodi mobitel. */
    private fun applyCommands(commands: List<WorkoutCommand>, sessionId: UUID, sentAt: Instant) {
        val snapshots = SessionSnapshotStore(store)
        val session = snapshots.session(sessionId) ?: return
        if (session.controllingDevice != DeviceRole.PHONE || session.state != SessionState.ACTIVE) return
        val merged = SnapshotDiff.apply(commands, session.snapshot(weightSteps()), maxOf(Instant.now(), sentAt))
        snapshots.apply(merged, force = true)
        when (merged.state) {
            // Završeno sa sata: isto kao završetak na mobitelu.
            SessionState.FINISHED -> ScheduleEngine(store).sessionFinished(session)
            SessionState.DISCARDED -> purgeLater()
            SessionState.ACTIVE -> Unit
        }
    }

    /** Odbačeni trening briše se tek kad ga ekran koji ga je prikazivao zatvori. */
    private fun purgeLater() {
        handler.postDelayed({ SessionSnapshotStore(store).purgeDiscarded() }, PURGE_DELAY_MILLIS)
    }

    // MARK: Data Layer

    private fun sendReliably(event: WorkoutEvent) {
        val bytes = event.encode()
        scope.launch {
            runCatching { data.putDataItem(PutDataRequest.create(WearPaths.eventItem(event.id)).setData(bytes).setUrgent()).await() }
        }
    }

    private fun sendIfReachable(event: WorkoutEvent) {
        val bytes = event.encode()
        scope.launch {
            runCatching { for (node in reachableWatches()) messages.sendMessage(node, WearPaths.EVENT, bytes).await() }
        }
    }

    private fun put(path: String, bytes: ByteArray) {
        scope.launch { runCatching { data.putDataItem(PutDataRequest.create(path).setData(bytes).setUrgent()).await() } }
    }

    private fun delete(path: String) {
        val uri = Uri.Builder().scheme(PutDataRequest.WEAR_URI_SCHEME).path(path).build()
        scope.launch { runCatching { data.deleteDataItems(uri).await() } }
    }

    private suspend fun reachableWatches(): List<String> =
        capabilities.getCapability(WearPaths.WATCH_CAPABILITY, CapabilityClient.FILTER_REACHABLE).await().nodes.map { it.id }

    private companion object {
        const val FLUSH_DELAY_MILLIS = 300L
        const val CONTEXT_DELAY_MILLIS = 2_000L
        const val PURGE_DELAY_MILLIS = 2_000L
        const val HEALTH_REQUEST_WINDOW_SECONDS = 120L
    }
}
