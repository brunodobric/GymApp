package com.brunodobric.gymapp.wear

import android.os.Handler
import android.os.Looper
import com.brunodobric.gymapp.ApolonApplication
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/** Podaci i poruke sa sata. Sustav pokreće aplikaciju i kad ne radi; obrada ide na glavnoj niti. */
class PhoneListenerService : WearableListenerService() {
    private val main = Handler(Looper.getMainLooper())
    private val sync get() = (application as ApolonApplication).watchSync

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        // Međuspremnik vrijedi samo za vrijeme poziva, pa se podaci kopiraju.
        val changes = dataEvents.filter { it.type == DataEvent.TYPE_CHANGED }.map { it.dataItem.uri to it.dataItem.data }
        main.post { for ((uri, bytes) in changes) sync.receiveData(uri.path.orEmpty(), uri, bytes) }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        val path = messageEvent.path
        val bytes = messageEvent.data ?: ByteArray(0)
        main.post { sync.receiveMessage(path, bytes) }
    }

    override fun onCapabilityChanged(capabilityInfo: CapabilityInfo) {
        main.post { sync.watchConnectionChanged() }
    }
}
