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

tasks.test {
    // Testovi programa provjeravaju izvedbe i volumen na stvarnom katalogu iz repozitorija.
    systemProperty("catalog.dir", rootDir.resolve("../Resources/Catalog").canonicalPath)
}
