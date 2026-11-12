package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.model.DashboardCardKind.BODY_WEIGHT
import com.brunodobric.gymapp.model.DashboardCardKind.LAST_WORKOUT
import com.brunodobric.gymapp.model.DashboardCardKind.PLATE_CALCULATOR
import com.brunodobric.gymapp.model.DashboardCardKind.THIS_MONTH
import com.brunodobric.gymapp.model.DashboardCardKind.THIS_WEEK
import com.brunodobric.gymapp.model.DashboardCardKind.THIS_YEAR
import com.brunodobric.gymapp.units.WeightUnit
import org.junit.jupiter.api.Test
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DashboardLayoutTest {
    private fun DashboardLayout.kinds() = cards().mapNotNull { it.kind }
    private fun DashboardLayout.raw() = allCards().map { it.kindRaw }

    private fun layoutWith(vararg raw: String): DashboardLayout {
        val store = GymStore()
        raw.forEachIndexed { index, kind -> store.insert(DashboardCard(kind, index)) }
        return DashboardLayout(store)
    }

    @Test
    fun `dodavanje ide na kraj i svaka vrsta samo jednom`() {
        val layout = DashboardLayout(GymStore())
        assertEquals(DashboardCardKind.entries, layout.availableKinds())
        layout.add(BODY_WEIGHT)
        layout.add(PLATE_CALCULATOR)
        assertNull(layout.add(BODY_WEIGHT))
        assertEquals(listOf(BODY_WEIGHT, PLATE_CALCULATOR), layout.kinds())
        assertEquals(listOf(THIS_WEEK, THIS_MONTH, THIS_YEAR, LAST_WORKOUT), layout.availableKinds())
    }

    @Test
    fun `uklanjanje zatvara rupu u redoslijedu`() {
        val layout = DashboardLayout(GymStore())
        listOf(PLATE_CALCULATOR, THIS_WEEK, BODY_WEIGHT).forEach { layout.add(it) }
        layout.remove(layout.cards()[1])
        assertEquals(listOf(0, 1), layout.cards().map { it.orderIndex })
        assertEquals(listOf(PLATE_CALCULATOR, BODY_WEIGHT), layout.kinds())
        layout.add(THIS_WEEK)
        assertEquals(listOf(PLATE_CALCULATOR, BODY_WEIGHT, THIS_WEEK), layout.kinds())
    }

    @Test
    fun `premještanje slijedi pravila onMove`() {
        val layout = DashboardLayout(GymStore())
        listOf(PLATE_CALCULATOR, THIS_WEEK, BODY_WEIGHT).forEach { layout.add(it) }
        layout.move(listOf(0), 3)
        assertEquals(listOf(THIS_WEEK, BODY_WEIGHT, PLATE_CALCULATOR), layout.kinds())
        layout.move(listOf(2), 0)
        assertEquals(listOf(PLATE_CALCULATOR, THIS_WEEK, BODY_WEIGHT), layout.kinds())
        layout.move(listOf(0), 1)
        assertEquals(listOf(PLATE_CALCULATOR, THIS_WEEK, BODY_WEIGHT), layout.kinds())
    }

    @Test
    fun `uklonjena zadana kartica se ne vraća kad Početna već ima kartice`() {
        val layout = DashboardLayout(GymStore())
        layout.add(BODY_WEIGHT)
        assertTrue(layout.seedDefaults().isEmpty())
        assertEquals(listOf(BODY_WEIGHT), layout.kinds())
    }

    @Test
    fun `prazna Početna dobiva Ovaj tjedan i Zadnji trening`() {
        val layout = DashboardLayout(GymStore())
        assertEquals(2, layout.seedDefaults().size)
        assertEquals(listOf(THIS_WEEK, LAST_WORKOUT), layout.kinds())
        assertTrue(layout.seedDefaults().isEmpty())
        assertEquals(listOf(0, 1), layout.allCards().map { it.orderIndex })
    }

    @Test
    fun `prijelaz - tjedni volumen postaje Ovaj tjedan na istom mjestu, sljedeći trening nestaje`() {
        val layout = layoutWith("lastWorkout", "nextWorkout", "weeklyVolume", "plateCalculator")
        layout.upgradeToWeekCard()
        assertEquals(listOf("lastWorkout", "thisWeek", "plateCalculator"), layout.raw())
        assertEquals(listOf(0, 1, 2), layout.allCards().map { it.orderIndex })
    }

    @Test
    fun `prijelaz bez tjednog volumena dodaje Ovaj tjedan na vrh`() {
        val layout = layoutWith("lastWorkout", "nextWorkout")
        layout.upgradeToWeekCard()
        assertEquals(listOf("thisWeek", "lastWorkout"), layout.raw())
        layout.upgradeToWeekCard()
        assertEquals(listOf("thisWeek", "lastWorkout"), layout.raw())
    }

    @Test
    fun `prijelaz ne dira Početnu koja već ima Ovaj tjedan ni praznu Početnu`() {
        val empty = DashboardLayout(GymStore())
        empty.upgradeToWeekCard()
        assertTrue(empty.allCards().isEmpty())

        val layout = layoutWith("bodyWeight", "thisWeek", "weeklyVolume")
        layout.upgradeToWeekCard()
        assertEquals(listOf("bodyWeight", "thisWeek"), layout.raw())
    }

    @Test
    fun `dvije uzastopne male kartice dijele red`() {
        assertEquals(
            listOf(listOf(THIS_WEEK), listOf(BODY_WEIGHT, PLATE_CALCULATOR), listOf(LAST_WORKOUT)),
            DashboardLayout.rows(listOf(THIS_WEEK, BODY_WEIGHT, PLATE_CALCULATOR, LAST_WORKOUT)),
        )
        assertEquals(
            listOf(listOf(BODY_WEIGHT), listOf(LAST_WORKOUT), listOf(PLATE_CALCULATOR)),
            DashboardLayout.rows(listOf(BODY_WEIGHT, LAST_WORKOUT, PLATE_CALCULATOR)),
        )
        assertTrue(DashboardLayout.rows(emptyList()).isEmpty())
    }

    @Test
    fun `nepoznata vrsta se ne prikazuje, ali ostaje u bazi`() {
        val layout = layoutWith("buducaVrsta")
        layout.add(THIS_WEEK)
        layout.move(listOf(0), 1)
        assertEquals(listOf(THIS_WEEK), layout.kinds())
        assertEquals(2, layout.allCards().size)
    }
}

class OnboardingTest {

    @Test
    fun `odgovori ulaze u postavke i mjerenja`() {
        val store = GymStore()
        val answers = OnboardingAnswers(
            goal = TrainingGoal.STRENGTH,
            unit = WeightUnit.POUNDS,
            weight = 200.0,
            heightCm = 180.0,
            wantsHealthKit = true,
            experience = ExperienceLevel.INTERMEDIATE,
            equipment = listOf(Equipment.BARBELL, Equipment.DUMBBELL),
            daysPerWeek = 4,
            sex = Sex.FEMALE,
        )
        OnboardingApplier(store).apply(answers)

        val reloaded = GymStore(store.persistence)
        val settings = reloaded.settings()
        assertEquals(TrainingGoal.STRENGTH, settings.goal)
        assertEquals(WeightUnit.POUNDS, settings.weightUnit)
        assertEquals(Sex.FEMALE, settings.sex)
        assertTrue(settings.bodyMapFemale)
        assertEquals(ExperienceLevel.INTERMEDIATE, settings.experience)
        assertEquals(listOf(Equipment.BARBELL, Equipment.DUMBBELL), settings.equipment)
        assertEquals(4, settings.trainingDaysPerWeek)
        assertTrue(settings.wantsHealthKit && settings.onboardingCompleted)

        val weight = reloaded.bodyMeasurements.first { it.kindRaw == "weight" }
        assertTrue(abs(weight.value - 90.718474) < 0.0001)
        assertEquals(180.0, reloaded.bodyMeasurements.first { it.kindRaw == "height" }.value)
    }

    @Test
    fun `prazni i nerazumni odgovori se ne spremaju`() {
        val store = GymStore()
        OnboardingApplier(store).apply(OnboardingAnswers(weight = 5.0, heightCm = 20.0, daysPerWeek = 9))
        val settings = store.settings()
        assertNull(settings.goal)
        assertNull(settings.experience)
        assertTrue(settings.equipment.isEmpty())
        assertNull(settings.sex)
        assertFalse(settings.bodyMapFemale)
        assertNull(settings.trainingDaysPerWeek)
        assertTrue(settings.onboardingCompleted)
        assertTrue(store.bodyMeasurements.isEmpty())
    }

    @Test
    fun `preskakanje samo označava da je onboarding obavljen`() {
        val store = GymStore()
        OnboardingApplier(store).skip()
        val settings = store.settings()
        assertTrue(settings.onboardingCompleted)
        assertNull(settings.goal)
        assertEquals(WeightUnit.KILOGRAMS, settings.weightUnit)
        assertFalse(settings.wantsHealthKit)
    }

    @Test
    fun `odgovor o zdravstvenim podacima sprema se i nakon preskakanja`() {
        val store = GymStore()
        OnboardingApplier(store).skip(wantsHealthKit = true)
        val settings = store.settings()
        assertTrue(settings.onboardingCompleted && settings.wantsHealthKit)
        assertNull(settings.goal)
    }

    @Test
    fun `naknadno ispunjavanje kreće od spremljenih odgovora, bez težine i visine`() {
        val store = GymStore()
        val settings = store.settings()
        settings.goal = TrainingGoal.HYPERTROPHY
        settings.trainingDaysPerWeek = 3
        settings.weightUnit = WeightUnit.POUNDS
        settings.sex = Sex.MALE
        settings.wantsHealthKit = true
        settings.equipment = EquipmentPreset.DUMBBELLS.equipment
        val answers = OnboardingAnswers.from(settings)
        assertEquals(TrainingGoal.HYPERTROPHY, answers.goal)
        assertEquals(3, answers.daysPerWeek)
        assertEquals(WeightUnit.POUNDS, answers.unit)
        assertEquals(Sex.MALE, answers.sex)
        assertTrue(answers.wantsHealthKit)
        assertNull(answers.experience)
        assertEquals(EquipmentPreset.DUMBBELLS, EquipmentPreset.matching(answers.equipment))
        assertNull(answers.weight)
        assertNull(answers.heightCm)

        // Ponovno spremanje istih odgovora ne dodaje mjerenja.
        OnboardingApplier(store).apply(answers)
        assertTrue(store.bodyMeasurements.isEmpty())
    }

    @Test
    fun `preset opreme odgovara točno svojoj opremi`() {
        assertEquals(EquipmentPreset.GYM, EquipmentPreset.matching(Equipment.entries.reversed()))
        assertEquals(EquipmentPreset.BODYWEIGHT_ONLY, EquipmentPreset.matching(listOf(Equipment.BODYWEIGHT)))
        assertNull(EquipmentPreset.matching(listOf(Equipment.BARBELL)))
    }
}
