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
        // Broj verzije je u gradle.properties. Mobitel i sat dijele applicationId, pa na Google Playu trebaju
        // različit versionCode: mobitel je apolon.versionCode × 10, a sat × 10 + 1.
        versionCode = providers.gradleProperty("apolon.versionCode").get().toInt() * 10 + 1
        versionName = providers.gradleProperty("apolon.versionName").get()
    }

    // Potpis izdanja (upload ključ za Google Play, docs/android-izdanje.md). Ključ nikad nije u repozitoriju: putanja
    // i lozinke dolaze iz okoline ili iz ~/.gradle/gradle.properties. Bez njih se release gradi nepotpisan (CI).
    val releaseKeystore = providers.gradleProperty("apolon.keystore").orElse(providers.environmentVariable("APOLON_KEYSTORE")).orNull
    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = providers.gradleProperty("apolon.keystorePassword").orElse(providers.environmentVariable("APOLON_KEYSTORE_PASSWORD")).get()
                keyAlias = providers.gradleProperty("apolon.keyAlias").orElse(providers.environmentVariable("APOLON_KEY_ALIAS")).getOrElse("upload")
                keyPassword = providers.gradleProperty("apolon.keyPassword").orElse(providers.environmentVariable("APOLON_KEY_PASSWORD")).get()
            }
        }
    }

    buildTypes {
        release {
            // R8 uklanja nekorišteni kod i resurse, ali ne preimenuje klase (proguard-rules.pro): nazivi enuma i
            // tipova zapisa spremaju se u bazu i kopiju, a stack trace u dijagnostici ostaje čitljiv.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
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
    // Trajna aktivnost na brojčaniku, pločica i komplikacije (Jetpack Wear, Apache 2.0).
    implementation(libs.androidx.wear.ongoing)
    implementation(libs.androidx.wear.tiles)
    implementation(libs.androidx.wear.protolayout)
    implementation(libs.androidx.wear.complications.data.source)
    // Wearable Data Layer: veza s mobitelom (Google Play usluge).
    implementation(libs.play.services.wearable)
    implementation(libs.kotlinx.coroutines.play.services)
}
