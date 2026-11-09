import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Android Gradle Plugin mora biti u istom classloaderu kao Kotlin plugin, inače Kotlin ne vidi AGP-ove
// klase. Učitava se samo kad postoji modul :app (uz Android SDK, vidi settings.gradle.kts).
buildscript {
    val hasAndroidSdk = System.getenv("ANDROID_HOME") != null || System.getenv("ANDROID_SDK_ROOT") != null ||
        file("local.properties").let { it.exists() && it.readText().contains("sdk.dir") }
    if (hasAndroidSdk) {
        repositories {
            google()
            mavenCentral()
        }
        dependencies { classpath("com.android.tools.build:gradle:9.3.2") }
    }
}

plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

// Čisti Kotlin moduli: bytecode za Javu 17 (isto kao Android), testovi na JUnit platformi.
subprojects {
    plugins.withId("org.jetbrains.kotlin.jvm") {
        extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension> {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
                allWarningsAsErrors.set(true)
            }
        }
        extensions.configure<JavaPluginExtension> {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        tasks.withType<Test>().configureEach {
            useJUnitPlatform()
        }
    }
}
