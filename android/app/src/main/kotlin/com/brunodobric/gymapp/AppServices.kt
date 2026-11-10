package com.brunodobric.gymapp

import android.content.Context
import com.brunodobric.gymapp.catalog.ExerciseCatalog
import com.brunodobric.gymapp.data.ExerciseImages
import com.brunodobric.gymapp.data.SqliteRecordPersistence
import com.brunodobric.gymapp.health.HealthLocalFile
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.stats.BodyMap
import com.brunodobric.gymapp.stats.BodyMapDiagram
import java.io.File

/**
 * Usluge koje dijele svi ekrani. Katalog se učitava jednom i lijeno, izvan glavne niti kad ga ekran
 * prvi put zatraži (pregled koda 9. 11., P2-1: jedan katalog).
 */
class AppServices(context: Context) {
    private val appContext = context.applicationContext

    val catalog: ExerciseCatalog by lazy {
        val json = appContext.assets.open("catalog.json").bufferedReader().use { it.readText() }
        ExerciseCatalog.decode(json)
    }

    /**
     * Korisnička baza (`ModelContext` na iOS-u). Učitava se pri prvom pristupu; ekrani je koriste s glavne niti,
     * a teški izračuni rade nad kopijama podataka.
     */
    val store: GymStore by lazy { GymStore(SqliteRecordPersistence(appContext)).also { it.health = healthLocal } }

    /**
     * Lokalna baza podataka iz Health Connecta (`HealthLocal` na iOS-u): kardio treninzi drugih aplikacija, težina i
     * visina. Datoteka je izvan korisničke baze i ne ide u sigurnosnu kopiju (data_extraction_rules.xml).
     */
    val healthLocal: HealthLocalFile by lazy { HealthLocalFile(File(File(appContext.filesDir, "health"), "local.json")) }

    /** Crteži tijela (MuscleMap, MIT) po spolu i strani; prazno ako se datoteka ne može pročitati. */
    val bodyMap: Map<String, BodyMapDiagram> by lazy {
        runCatching {
            appContext.assets.open("body.json").bufferedReader().use { BodyMap.decode(it.readText()) }
        }.getOrDefault(emptyMap())
    }

    /** Tekst MIT licence crteža tijela, za "O aplikaciji". */
    fun muscleMapLicense(): String =
        runCatching { appContext.assets.open("LICENSE-MuscleMap.txt").bufferedReader().use { it.readText() } }.getOrDefault("")

    /** Slike vlastitih vježbi. */
    val exerciseImages: ExerciseImages by lazy { ExerciseImages(appContext) }
}
