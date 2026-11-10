package com.brunodobric.gymapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.brunodobric.gymapp.ui.RootScreen
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.theme.ApolonTheme
import com.brunodobric.gymapp.ui.theme.isDark

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val services = (application as ApolonApplication).services
        setContent {
            // Tema i boja iz postavki; promjena u Postavkama odmah mijenja cijelu aplikaciju.
            rememberStoreRevision(services.store)
            val settings = services.store.settings()
            ApolonTheme(accentRaw = settings.accentColorRaw, darkTheme = settings.theme.isDark()) {
                RootScreen(services)
            }
        }
    }
}
