// Predlošci, rasporedi, programi i podsjetnici (port GymKit/Planning).
plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    api(project(":core:training"))
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlin.test)
    testRuntimeOnly(libs.junit.launcher)
}
