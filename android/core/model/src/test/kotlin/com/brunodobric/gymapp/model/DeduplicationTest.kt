package com.brunodobric.gymapp.model

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// Port GymKit/Tests/ModelsTests (Deduplication): postavke i kartice Početne s dva uređaja.
class DeduplicationTest {

    @Test
    fun `ostaju postavke s obavljenim onboardingom`() {
        val store = GymStore()
        store.insert(UserSettings())
        val chosen = store.insert(UserSettings().apply { onboardingCompleted = true })
        store.save()

        assertEquals(1, Deduplication.removeDuplicateSettings(store))
        assertTrue(store.settingsRecords.single() === chosen)
        assertEquals(0, Deduplication.removeDuplicateSettings(store))
    }

    @Test
    fun `ista vrsta kartice ostaje jednom, a redoslijed se numerira iznova`() {
        val store = GymStore()
        store.insert(DashboardCard(DashboardCardKind.THIS_WEEK.raw, 0))
        store.insert(DashboardCard(DashboardCardKind.LAST_WORKOUT.raw, 1))
        store.insert(DashboardCard(DashboardCardKind.THIS_WEEK.raw, 2))
        store.insert(DashboardCard("buducaVrsta", 3))
        store.insert(DashboardCard("buducaVrsta", 4))
        store.save()

        assertEquals(1, Deduplication.removeAll(store))
        val cards = DashboardLayout(store).allCards()
        assertEquals(listOf(DashboardCardKind.THIS_WEEK.raw, DashboardCardKind.LAST_WORKOUT.raw, "buducaVrsta", "buducaVrsta"), cards.map { it.kindRaw })
        assertEquals(listOf(0, 1, 2, 3), cards.map { it.orderIndex })
    }
}
