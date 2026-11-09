package com.brunodobric.gymapp

import android.content.Context
import com.brunodobric.gymapp.catalog.ExerciseCatalog

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
}
