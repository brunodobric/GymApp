package com.brunodobric.gymapp.model

import java.io.File
import java.io.IOException
import java.time.Instant

/**
 * Oporavak kad se baza na uređaju ne može otvoriti (`GymPersistence.moveStoresAside` na iOS-u): datoteke baze
 * premještaju se u novu mapu pokraj njih, da se aplikacija pri sljedećem pokretanju otvori s praznom bazom,
 * a stari podaci ostanu na uređaju za oporavak. Ništa se ne briše.
 */
object StoreRecovery {
    /** Dodaci uz datoteku SQLite baze (dnevnik transakcija i WAL, ako postoje). */
    private val SUFFIXES = listOf("", "-journal", "-wal", "-shm")

    /**
     * Premješta `database` i njegove pomoćne datoteke u mapu "Neotvorena baza <sekunde>" pokraj nje i vraća tu
     * mapu. Baca [IOException] kad se mapa ne može stvoriti ili se datoteka ne može premjestiti.
     */
    fun moveAside(database: File, now: Instant = Instant.now()): File {
        val directory = database.absoluteFile.parentFile ?: throw IOException("Baza nema mapu: $database")
        val destination = File(directory, "Neotvorena baza ${now.epochSecond}")
        if (!destination.isDirectory && !destination.mkdirs()) throw IOException("Mapa se nije stvorila: $destination")
        for (suffix in SUFFIXES) {
            val source = File(directory, database.name + suffix)
            if (!source.exists()) continue
            val target = File(destination, source.name)
            if (!source.renameTo(target)) {
                source.copyTo(target, overwrite = true)
                if (!source.delete()) throw IOException("Datoteka se nije premjestila: $source")
            }
        }
        return destination
    }
}
