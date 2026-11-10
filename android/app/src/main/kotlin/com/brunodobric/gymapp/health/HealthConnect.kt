package com.brunodobric.gymapp.health

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.WeightRecord
import java.util.Locale

/**
 * Health Connect (umjesto HealthKita, docs/android.md, odjeljak 7.8): dostupnost, dozvole i poveznice.
 * Apolon upisuje treninge i težinu, a čita kardio treninge drugih aplikacija, težinu i visinu.
 */
object HealthConnect {
    private const val PROVIDER = "com.google.android.apps.healthdata"

    /** Samo dozvole za tipove koji se upisuju (Play pravila: ništa više od potrebnog). */
    val WRITE_PERMISSIONS: Set<String> = setOf(
        HealthPermission.getWritePermission(ExerciseSessionRecord::class),
        HealthPermission.getWritePermission(WeightRecord::class),
    )

    /** Čitanje kardio treninga (s udaljenošću, kalorijama i pulsom), težine i visine. */
    val READ_PERMISSIONS: Set<String> = setOf(
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(WeightRecord::class),
        HealthPermission.getReadPermission(HeightRecord::class),
    )

    /** Sve što se traži jednim listom dozvola. Upis je nužan; čitanje radi samo za dane dozvole. */
    val PERMISSIONS: Set<String> = WRITE_PERMISSIONS + READ_PERMISSIONS

    fun status(context: Context): Int = HealthConnectClient.getSdkStatus(context)

    fun isAvailable(context: Context): Boolean = status(context) == HealthConnectClient.SDK_AVAILABLE

    /** Je li dan barem upis (prekidač u Postavkama); čitanje se provjerava po vrsti pri uvozu. */
    suspend fun hasPermissions(context: Context): Boolean = runCatching {
        HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions().containsAll(WRITE_PERMISSIONS)
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
