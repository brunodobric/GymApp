package com.brunodobric.gymapp.health

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.theme.ApolonTheme
import com.brunodobric.gymapp.ui.theme.isDark

/**
 * Objašnjenje dozvola za Health Connect: otvara ga Health Connect (poveznica "pravila privatnosti" kod dozvola),
 * a traže ga Play pravila za zdravstvene podatke. Kaže što se upisuje i vodi na pravila privatnosti.
 */
class HealthPermissionsActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val store = (application as ApolonApplication).services.store
        setContent {
            rememberStoreRevision(store)
            val settings = store.settings()
            ApolonTheme(accentRaw = settings.accentColorRaw, darkTheme = settings.theme.isDark()) {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(stringResource(R.string.health_connect)) },
                            navigationIcon = {
                                IconButton(onClick = { finish() }) {
                                    Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
                                }
                            },
                        )
                    },
                ) { padding ->
                    Column(
                        Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Text(stringResource(R.string.health_rationale_title), style = MaterialTheme.typography.headlineSmall)
                        Text(stringResource(R.string.health_rationale_text), style = MaterialTheme.typography.bodyLarge)
                        Text(stringResource(R.string.health_rationale_privacy), style = MaterialTheme.typography.bodyLarge)
                        OutlinedButton(onClick = {
                            runCatching { startActivity(Intent(Intent.ACTION_VIEW, HealthConnect.privacyPolicyUri())) }
                        }) { Text(stringResource(R.string.privacy_policy)) }
                    }
                }
            }
        }
    }
}
