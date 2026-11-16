// Protokol između mobitela i Wear OS sata: snimka treninga, naredbe, događaji, kontekst za sat i engine treninga
// na satu (port GymKit/Connectivity). Čisti Kotlin, dijele ga modul aplikacije i modul sata.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":core:training"))
    api(project(":core:planning"))
    api(project(":domain:widgets"))
    implementation(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.core)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testRuntimeOnly(libs.junit.launcher)
}
