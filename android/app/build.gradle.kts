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
        versionCode = 1
        versionName = "1.0.0"
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
}

// Javni katalog vježbi dijele iOS i Android: catalog.json se čita iz Resources/Catalog.
androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addStaticSourceDirectory(rootDir.resolve("../Resources/Catalog").canonicalPath)
        // Crteži tijela za heatmap (MuscleMap, MIT) i tekst licence, isti kao na iOS-u.
        variant.sources.assets?.addStaticSourceDirectory(rootDir.resolve("../Resources/BodyMap").canonicalPath)
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
    debugImplementation(libs.androidx.compose.ui.tooling)
}
