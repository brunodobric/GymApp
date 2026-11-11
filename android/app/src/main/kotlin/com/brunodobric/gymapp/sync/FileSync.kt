package com.brunodobric.gymapp.sync

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.compose.runtime.mutableStateOf
import com.brunodobric.gymapp.AppServices
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Sinkronizacija između Android uređaja preko jedne datoteke (`apolon-sync.json`) u pohrani koju korisnik odabere
 * u sustavskom izborniku datoteka, npr. Google Drive (docs/android.md, odjeljak 6). Bez Google prijave i bez SDK-a:
 * aplikacija datoteku čita i piše kroz pružatelja pohrane, a pružatelj je sam prenosi u oblak.
 *
 * Kada: pri povratku u aplikaciju, pola minute nakon spremanja i pri odlasku u pozadinu. Spajanje je u [SyncMerge].
 * Promjene s drugog uređaja ulaze u bazu samo kad nijedan uređivač ni trening nisu otvoreni ([SyncGate]); inače
 * čekaju sljedeću sinkronizaciju.
 */
class FileSync(context: Context, private val services: AppServices) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val ledgerFile = File(File(appContext.filesDir, "sync"), "ledger.json")
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val pending = Runnable { sync() }
    private var running: Job? = null
    private var again = false

    /** Stanje za Postavke: datoteka, zadnja uspješna sinkronizacija i greška. */
    val status = mutableStateOf(readStatus())

    data class Status(
        val fileName: String?,
        val lastSync: Instant?,
        val error: SyncError?,
        val isRunning: Boolean = false,
        /** Promjene s drugog uređaja čekaju zatvaranje uređivača ili treninga. */
        val deferred: Int = 0,
    ) {
        val isOn: Boolean get() = fileName != null
    }

    enum class SyncError { UNREADABLE, NOT_SYNC_FILE, NEWER_FORMAT, NO_ACCESS }

    fun start() {
        services.store.addListener { schedule(SAVE_DELAY_MILLIS) }
        SyncGate.onOpened = { if (isOn) schedule(GATE_DELAY_MILLIS) }
    }

    val isOn: Boolean get() = prefs.getString(KEY_URI, null) != null

    /** Uključuje sinkronizaciju s odabranom datotekom i odmah je sinkronizira. */
    fun connect(uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        runCatching { appContext.contentResolver.takePersistableUriPermission(uri, flags) }
        val previous = prefs.getString(KEY_URI, null)
        if (previous != null && previous != uri.toString()) release(Uri.parse(previous))
        // Nova datoteka: ovaj uređaj se spaja s njom kao prvi put, pa datoteka ima prednost za zajedničke zapise.
        ledgerFile.delete()
        prefs.edit()
            .putString(KEY_URI, uri.toString())
            .putString(KEY_NAME, displayName(uri))
            .remove(KEY_LAST)
            .remove(KEY_ERROR)
            .apply()
        status.value = readStatus()
        sync()
    }

    /** Isključuje sinkronizaciju. Datoteka i podaci na uređaju ostaju. */
    fun disconnect() {
        prefs.getString(KEY_URI, null)?.let { release(Uri.parse(it)) }
        prefs.edit().clear().apply()
        ledgerFile.delete()
        status.value = readStatus()
    }

    private fun release(uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        runCatching { appContext.contentResolver.releasePersistableUriPermission(uri, flags) }
    }

    fun schedule(delayMillis: Long = 0) {
        if (!isOn) return
        handler.removeCallbacks(pending)
        handler.postDelayed(pending, delayMillis)
    }

    /** Sinkronizira odmah. Bez odabrane datoteke ne radi ništa. */
    fun sync() {
        val uri = prefs.getString(KEY_URI, null)?.let(Uri::parse) ?: return
        handler.removeCallbacks(pending)
        if (running?.isActive == true) {
            again = true
            return
        }
        status.value = status.value.copy(isRunning = true)
        running = scope.launch {
            val error = runCatching { run(uri) }.exceptionOrNull()
            val code = when (error) {
                null -> null
                is SyncException.NotSyncFile -> SyncError.NOT_SYNC_FILE
                is SyncException.NewerFormat -> SyncError.NEWER_FORMAT
                is SecurityException -> SyncError.NO_ACCESS
                else -> SyncError.UNREADABLE
            }
            prefs.edit().apply {
                if (code == null) putLong(KEY_LAST, System.currentTimeMillis()).remove(KEY_ERROR) else putString(KEY_ERROR, code.name)
            }.apply()
            status.value = readStatus().copy(deferred = lastDeferred)
            if (again) {
                again = false
                schedule(GATE_DELAY_MILLIS)
            }
        }
    }

    private var lastDeferred = 0

    private suspend fun run(uri: Uri) {
        val (remote, ledger) = withContext(Dispatchers.IO) {
            val text = appContext.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
                ?: error("Datoteka se ne može otvoriti")
            SyncFile.decode(text) to readLedger()
        }
        // Baza se čita i mijenja na glavnoj niti, bez prekida između čitanja i upisa promjena.
        val store = services.store
        val canApply = SyncGate.isOpen && store.activeSession() == null
        val result = SyncMerge.merge(
            local = store.persistedRecords(),
            ledger = ledger,
            remote = remote,
            now = System.currentTimeMillis(),
            excluded = store.activeSessionKeys(),
            canApply = canApply,
        )
        if (result.received > 0) store.applyExternal(result.upserts, result.deletes)
        lastDeferred = result.deferred
        withContext(Dispatchers.IO) {
            if (result.fileChanged) {
                val stream = appContext.contentResolver.openOutputStream(uri, "wt") ?: error("Datoteka se ne može zapisati")
                stream.use { it.write(result.file.encode().toByteArray(Charsets.UTF_8)) }
            }
            writeLedger(result.ledger)
        }
    }

    private fun readLedger(): SyncLedger {
        val stored = runCatching { SyncLedger.decode(ledgerFile.readText()) }.getOrNull()
        return stored ?: SyncLedger(deviceId())
    }

    private fun writeLedger(ledger: SyncLedger) {
        ledgerFile.parentFile?.mkdirs()
        val temporary = File(ledgerFile.parentFile, "${ledgerFile.name}.tmp")
        temporary.writeText(ledger.encode())
        temporary.renameTo(ledgerFile)
    }

    private fun deviceId(): String = prefs.getString(KEY_DEVICE, null) ?: UUID.randomUUID().toString().uppercase().also {
        prefs.edit().putString(KEY_DEVICE, it).apply()
    }

    private fun displayName(uri: Uri): String {
        val name = runCatching {
            appContext.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull()
        return name ?: uri.lastPathSegment ?: FILE_NAME
    }

    private fun readStatus(): Status = Status(
        fileName = prefs.getString(KEY_URI, null)?.let { prefs.getString(KEY_NAME, null) ?: FILE_NAME },
        lastSync = prefs.getLong(KEY_LAST, 0).takeIf { it > 0 }?.let(Instant::ofEpochMilli),
        error = prefs.getString(KEY_ERROR, null)?.let { raw -> SyncError.entries.firstOrNull { it.name == raw } },
    )

    companion object {
        /** Predloženo ime nove datoteke u izborniku. */
        const val FILE_NAME = "apolon-sync.json"
        private const val PREFS = "sync"
        private const val KEY_URI = "uri"
        private const val KEY_NAME = "name"
        private const val KEY_LAST = "last"
        private const val KEY_ERROR = "error"
        private const val KEY_DEVICE = "device"
        private const val SAVE_DELAY_MILLIS = 30_000L
        private const val GATE_DELAY_MILLIS = 1_000L
    }
}

/**
 * Otvoreni uređivači (trening, raspored, trening u povijesti, vlastita vježba): dok je ijedan otvoren, promjene s
 * drugog uređaja ne ulaze u bazu, jer bi ponovno učitavanje odvojilo objekte koje uređivač drži.
 */
object SyncGate {
    private var holders = 0

    val isOpen: Boolean get() = holders == 0

    /** Zove se kad se zatvori zadnji uređivač (sinkronizacija tada primjenjuje promjene koje čekaju). */
    internal var onOpened: (() -> Unit)? = null

    fun hold() {
        holders++
    }

    fun release() {
        holders = (holders - 1).coerceAtLeast(0)
        if (holders == 0) onOpened?.invoke()
    }
}
