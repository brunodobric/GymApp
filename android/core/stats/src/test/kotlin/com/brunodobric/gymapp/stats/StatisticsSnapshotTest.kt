package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.model.StatsDetail
import com.brunodobric.gymapp.training.PRKind
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Isto kao `StatisticsSnapshotTests` u GymKitu. */
class StatisticsSnapshotTest {
    @Test
    fun `snimka daje iste brojeve kao pojedinačni izračuni`() {
        val store = newStore()
        store.settings().statsDetail = StatsDetail.PRO
        store.addSession(base.plusDays(-2.0), lifts = listOf(Lift(bench, listOf(Work(80.0, 5), Work(85.0, 3)))))
        store.addSession(base.plusDays(-1.0), lifts = listOf(Lift(squat, listOf(Work(100.0, 5)))))

        val snapshot = StatisticsSnapshotBuilder.make(
            store, catalog = null, settings = StatisticsSettings.of(store.settings()), muscleDays = 28, now = base,
        )
        val engine = StatisticsEngine(store)
        assertTrue(snapshot.isPro)
        assertEquals(28, snapshot.muscleDays)
        assertEquals(engine.personalRecords(PRKind.tracked(store.settings())), snapshot.records)
        assertEquals(StatisticsSnapshotBuilder.heatmap(store, null, 28, base), snapshot.heatmap)
    }

    @Test
    fun `osnovni prikaz ne računa kartice detaljnog prikaza`() {
        val store = newStore()
        store.settings().statsDetail = StatsDetail.BASIC
        store.addSession(base.plusDays(-1.0), lifts = listOf(Lift(bench, listOf(Work(80.0, 5, rpe = 8.0)))))

        val snapshot = StatisticsSnapshotBuilder.make(
            store, catalog = null, settings = StatisticsSettings.of(store.settings()), muscleDays = 28, now = base,
        )
        assertFalse(snapshot.isPro)
        assertNull(snapshot.weekly)
        assertNull(snapshot.effort)
    }
}
