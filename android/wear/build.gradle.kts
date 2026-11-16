// Aplikacija Apolon za Wear OS sat (faza 9, docs/android.md). Isti applicationId kao mobitel, jer Data Layer
// povezuje samo aplikacije istog paketa i potpisa. Logika je u čistom Kotlin modulu :domain:wear (s testovima),
// ovdje su samo ekrani, Data Layer, Health Services i spremanje stanja.
plugins {
    id("com.android.application")
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.brunodobric.gymapp.watch"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.brunodobric.gymapp"
        // Wear OS 3 (API 30) je najstariji s Health Services.
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        localeFilters += listOf("hr", "en")
    }
}

dependencies {
    implementation(project(":domain:wear"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.wear.compose.material3)
    implementation(libs.androidx.wear.compose.foundation)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.core.ktx)
    // Puls i kalorije tijekom treninga (Jetpack Health Services, Apache 2.0).
    implementation(libs.androidx.health.services)
    implementation(libs.androidx.concurrent.futures)
    // Wearable Data Layer: veza s mobitelom (Google Play usluge).
    implementation(libs.play.services.wearable)
    implementation(libs.kotlinx.coroutines.play.services)
}
