package com.brunodobric.gymapp.watch

import android.util.AtomicFile
import com.brunodobric.gymapp.wear.WatchStateFile
import com.brunodobric.gymapp.wear.WatchStateStorage
import java.io.File

/** Stanje sata u datoteci u mapi aplikacije (`WatchStateFile` na iOS-u), zapisano atomski. */
class FileStateStorage(directory: File) : WatchStateStorage {
    private val file = AtomicFile(File(directory, "state.json"))

    init {
        directory.mkdirs()
    }

    override fun save(state: WatchStateFile) {
        val stream = file.startWrite()
        try {
            stream.write(state.encode().toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    override fun load(): WatchStateFile? = runCatching { WatchStateFile.decode(file.readFully().toString(Charsets.UTF_8)) }.getOrNull()
}
