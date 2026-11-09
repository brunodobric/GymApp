// Službeni katalog vježbi i pretraga (port GymKit/Catalog).
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(libs.kotlinx.serialization.json)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlin.test)
    testRuntimeOnly(libs.junit.launcher)
}

tasks.test {
    // Testovi čitaju stvarni katalog iz repozitorija, da se pokvaren build kataloga uhvati u CI-ju.
    systemProperty("catalog.dir", rootDir.resolve("../Resources/Catalog").canonicalPath)
}
