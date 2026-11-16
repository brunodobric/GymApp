package com.brunodobric.gymapp.watch

import android.os.Handler
import android.os.Looper
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/** Podaci i poruke s mobitela. Sustav pokreće aplikaciju i kad ne radi; obrada ide na glavnoj niti. */
class WatchListenerService : WearableListenerService() {
    private val main = Handler(Looper.getMainLooper())
    private val app get() = application as WatchApplication

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        // Međuspremnik vrijedi samo za vrijeme poziva, pa se podaci kopiraju.
        val changes = dataEvents.map { event ->
            val item = event.dataItem
            Triple(item.uri, if (event.type == DataEvent.TYPE_CHANGED) item.data else null, event.type)
        }
        main.post {
            for ((uri, bytes, type) in changes) {
                if (type == DataEvent.TYPE_DELETED || bytes != null) app.receiveData(uri.path.orEmpty(), uri, bytes)
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        val path = messageEvent.path
        val bytes = messageEvent.data ?: ByteArray(0)
        main.post { app.receiveMessage(path, bytes) }
    }

    override fun onCapabilityChanged(capabilityInfo: CapabilityInfo) {
        if (capabilityInfo.nodes.isNotEmpty()) main.post { app.phoneConnectionChanged() }
    }
}
