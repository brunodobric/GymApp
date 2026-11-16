package com.brunodobric.gymapp.watch

import android.content.Context
import android.net.Uri
import com.brunodobric.gymapp.wear.SessionSnapshot
import com.brunodobric.gymapp.wear.WatchLink
import com.brunodobric.gymapp.wear.WearCoding
import com.brunodobric.gymapp.wear.WearPaths
import com.brunodobric.gymapp.wear.WorkoutEvent
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Slanje mobitelu preko Wearable Data Layera (`WatchTransport` na iOS-u). Zajamčeni događaji idu kao podatak, koji
 * Data Layer dostavi i kad mobitel dio vremena nije u dosegu; ostali kao poruka samo dostupnom mobitelu.
 */
class DataLayerLink(context: Context, private val scope: CoroutineScope) : WatchLink {
    private val data = Wearable.getDataClient(context)
    private val messages = Wearable.getMessageClient(context)
    private val capabilities = Wearable.getCapabilityClient(context)

    override fun sendReliably(event: WorkoutEvent) {
        val bytes = event.encode()
        scope.launch {
            runCatching {
                val request = PutDataRequest.create(WearPaths.eventItem(event.id)).setData(bytes).setUrgent()
                data.putDataItem(request).await()
            }
        }
    }

    override fun sendIfReachable(event: WorkoutEvent) {
        val bytes = event.encode()
        scope.launch {
            runCatching {
                for (node in phoneNodes()) messages.sendMessage(node, WearPaths.EVENT, bytes).await()
            }
        }
    }

    override fun publishSession(snapshot: SessionSnapshot?) {
        val bytes = snapshot?.let(WearCoding::encodeSnapshot)
        scope.launch {
            runCatching {
                if (bytes == null) {
                    data.deleteDataItems(anyNode(WearPaths.WATCH_SESSION)).await()
                } else {
                    data.putDataItem(PutDataRequest.create(WearPaths.WATCH_SESSION).setData(bytes).setUrgent()).await()
                }
            }
        }
    }

    /** Briše primljeni zajamčeni događaj, da se ne obradi ponovno. */
    fun consume(uri: Uri) {
        scope.launch { runCatching { data.deleteDataItems(uri).await() } }
    }

    /** Je li mobitel s aplikacijom upravo dostupan. */
    suspend fun isPhoneReachable(): Boolean = runCatching { phoneNodes().isNotEmpty() }.getOrDefault(false)

    /** Trenutni podaci s mobitela (kontekst i snimka), npr. nakon pokretanja aplikacije: put → bajtovi. */
    suspend fun currentItems(): Map<String, Pair<Uri, ByteArray>> = runCatching {
        val buffer = data.dataItems.await()
        try {
            buffer.mapNotNull { item -> item.data?.let { item.uri.path.orEmpty() to (item.uri to it) } }.toMap()
        } finally {
            buffer.release()
        }
    }.getOrDefault(emptyMap())

    private suspend fun phoneNodes(): List<String> =
        capabilities.getCapability(WearPaths.PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE).await().nodes.map { it.id }

    private fun anyNode(path: String): Uri = Uri.Builder().scheme(PutDataRequest.WEAR_URI_SCHEME).path(path).build()
}
