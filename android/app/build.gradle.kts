// Android aplikacija Apolon (mobitel). Plan: docs/android.md.
plugins {
    id("com.android.application")
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.brunodobric.gymapp"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.brunodobric.gymapp"
        minSdk = 31
        targetSdk = 36
        // Broj verzije je u gradle.properties. Mobitel i sat dijele applicationId, pa na Google Playu trebaju
        // različit versionCode: mobitel je apolon.versionCode × 10, a sat × 10 + 1.
        versionCode = providers.gradleProperty("apolon.versionCode").get().toInt() * 10
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
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        localeFilters += listOf("hr", "en")
    }

    // MoveKit klipovi u AAB-u za Google Play idu u zaseban paket (movekit/build.gradle.kts).
    if (rootProject.findProject(":movekit") != null) assetPacks += ":movekit"
}

// Javni katalog vježbi dijele iOS i Android: catalog.json se čita iz Resources/Catalog.
androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addStaticSourceDirectory(rootDir.resolve("../Resources/Catalog").canonicalPath)
        // Crteži tijela za heatmap (MuscleMap, MIT) i tekst licence, isti kao na iOS-u.
        variant.sources.assets?.addStaticSourceDirectory(rootDir.resolve("../Resources/BodyMap").canonicalPath)
        // APK (debug, izravno testiranje) nema pakete, pa MoveKit sadržaj ulazi u obične assete.
        val moveKitAssets = rootDir.resolve("movekit/src/main/assets")
        if (variant.buildType == "debug" && moveKitAssets.isDirectory) {
            variant.sources.assets?.addStaticSourceDirectory(moveKitAssets.canonicalPath)
        }
    }
}

dependencies {
    implementation(project(":core:units"))
    implementation(project(":core:catalog"))
    implementation(project(":core:model"))
    implementation(project(":core:training"))
    implementation(project(":core:planning"))
    implementation(project(":core:stats"))
    implementation(project(":domain:backup"))
    implementation(project(":domain:widgets"))
    implementation(project(":domain:health"))
    implementation(project(":domain:sync"))
    implementation(project(":domain:wear"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.core.ktx)
    // Widgeti na početnom zaslonu (Jetpack Glance, Apache 2.0).
    implementation(libs.androidx.glance.appwidget)
    // Upis treninga i težine u Health Connect (Jetpack, Apache 2.0).
    implementation(libs.androidx.health.connect)
    // Wearable Data Layer: veza sa satom (Google Play usluge).
    implementation(libs.play.services.wearable)
    implementation(libs.kotlinx.coroutines.play.services)
    debugImplementation(libs.androidx.compose.ui.tooling)
}
