// Sinkronizacija između Android uređaja preko datoteke u korisnikovoj pohrani (Google Drive i slično): spajanje
// zapisa bez Android API-ja (docs/android.md, odjeljak 6).
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":core:model"))
    implementation(libs.kotlinx.serialization.json)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlin.test)
    testRuntimeOnly(libs.junit.launcher)
}
