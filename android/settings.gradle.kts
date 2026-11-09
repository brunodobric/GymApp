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
