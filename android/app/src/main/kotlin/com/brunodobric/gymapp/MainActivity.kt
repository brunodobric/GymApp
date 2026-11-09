package com.brunodobric.gymapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.brunodobric.gymapp.ui.RootScreen
import com.brunodobric.gymapp.ui.theme.ApolonTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val services = (application as ApolonApplication).services
        setContent {
            ApolonTheme {
                RootScreen(services)
            }
        }
    }
}
