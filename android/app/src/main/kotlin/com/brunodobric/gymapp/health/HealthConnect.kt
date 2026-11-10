package com.brunodobric.gymapp.health

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.WeightRecord
import java.util.Locale

/**
 * Health Connect (umjesto HealthKita, docs/android.md, odjeljak 7.8): dostupnost, dozvole i poveznice.
 * Apolon zasad samo upisuje treninge i težinu; čitanje iz drugih aplikacija dolazi poslije.
 */
object HealthConnect {
    private const val PROVIDER = "com.google.android.apps.healthdata"

    /** Samo dozvole za tipove koji se upisuju (Play pravila: ništa više od potrebnog). */
    val PERMISSIONS: Set<String> = setOf(
        HealthPermission.getWritePermission(ExerciseSessionRecord::class),
        HealthPermission.getWritePermission(WeightRecord::class),
    )

    fun status(context: Context): Int = HealthConnectClient.getSdkStatus(context)

    fun isAvailable(context: Context): Boolean = status(context) == HealthConnectClient.SDK_AVAILABLE

    suspend fun hasPermissions(context: Context): Boolean = runCatching {
        HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions().containsAll(PERMISSIONS)
    }.getOrDefault(false)

    /** Na Androidu 13 i starijem Health Connect je aplikacija iz Trgovine Play. */
    fun installIntent(): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PROVIDER&url=healthconnect%3A%2F%2Fonboarding"))

    /** Postavke Health Connecta, gdje korisnik mijenja dozvole. */
    fun settingsIntent(): Intent = Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)

    /** Pravila privatnosti na jeziku sučelja (ista stranica kao na iOS-u). */
    fun privacyPolicyUri(): Uri = Uri.parse(
        if (Locale.getDefault().language == "hr") {
            "https://brunodobric.github.io/GymApp/privacy/"
        } else {
            "https://brunodobric.github.io/GymApp/privacy/en/"
        },
    )
}
