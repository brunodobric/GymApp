// Sigurnosna kopija: JSON i CSV izvoz i uvoz, brisanje svih podataka (port GymKit/Backup).
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

tasks.test {
    // Uvoz iz druge aplikacije provjerava se na stvarnom katalogu i istom izvozu kao testovi na iOS-u.
    systemProperty("catalog.dir", rootDir.resolve("../Resources/Catalog").canonicalPath)
    systemProperty("fixtures.dir", rootDir.resolve("../Packages/GymKit/Tests/BackupTests/Fixtures").canonicalPath)
}
