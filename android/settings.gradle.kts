// Android verzija aplikacije Apolon (plan: docs/android.md).
// Čisti Kotlin moduli (logika bez sučelja) grade se svugdje, a modul aplikacije samo kad postoji Android SDK.
pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Apolon"

include(":core:units")
include(":core:catalog")
include(":core:model")
include(":core:training")
include(":core:planning")

// Modul aplikacije treba Android SDK (ANDROID_HOME ili sdk.dir u local.properties). Bez njega se grade i
// testiraju samo čisti Kotlin moduli, npr. u okruženju gdje se SDK ne može preuzeti.
val hasAndroidSdk = System.getenv("ANDROID_HOME") != null || System.getenv("ANDROID_SDK_ROOT") != null ||
    file("local.properties").takeIf { it.exists() }?.readText()?.contains("sdk.dir") == true
if (hasAndroidSdk) {
    include(":app")
}
