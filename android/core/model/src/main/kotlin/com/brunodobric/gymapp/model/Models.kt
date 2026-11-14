@file:UseSerializers(UUIDSerializer::class, InstantSerializer::class)

package com.brunodobric.gymapp.model

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCategory
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.catalog.rawValueOf
import com.brunodobric.gymapp.units.WeightUnit
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import kotlinx.serialization.UseSerializers
import java.time.Instant
import java.util.UUID

// Model korisničke baze, isti kao GymSchemaV1 na iOS-u (GymKit/Sources/Models): ista polja, isti nazivi
// i iste zadane vrijednosti, pa se kopija (JSON, CSV) prenosi između platformi bez gubitka.
//
// Pravila koja vrijede od prvog dana (i za kasniju sinkronizaciju):
// * svako svojstvo ima zadanu vrijednost ili je opcionalno,
// * UUID je id, jedinstvenost se osigurava u kodu,
// * redoslijed se čuva u `orderIndex`,
// * težina je uvijek u kilogramima.
//
// Roditelj drži popis djece, a dijete id roditelja (sprema se) i pokazivač na njega (ne sprema se).
// Spremište (`GymStore`) slaže graf pri učitavanju i sprema samo zapise koji su se promijenili.

/** Zajedničko svim zapisima: stabilan id. */
sealed interface GymRecord {
    val id: UUID
}

// MARK: Katalog i planiranje

@Serializable
class CustomExercise(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var name: String = ""
    var details: String = ""
    var categoryRaw: String = ""

    /** Mišići odvojeni zarezom. */
    var musclesRaw: String = ""
    var equipmentRaw: String = ""
    var inputTypeRaw: String = ExerciseInputType.WEIGHT_REPS.raw

    /** Vrsta vježbe (`ExerciseKind`). Prazno za vježbe spremljene prije nego što je vrsta postojala. */
    var kindRaw: String = ""

    /** Slika vježbe je zasebna datoteka (ime datoteke), ne bajtovi u zapisu. */
    var imageFile: String? = null
    var isArchived: Boolean = false
    var createdAt: Instant = Instant.now()

    constructor(name: String, inputType: ExerciseInputType = ExerciseInputType.WEIGHT_REPS) : this() {
        this.name = name
        this.inputTypeRaw = inputType.raw
    }

    var inputType: ExerciseInputType
        get() = rawValueOf<ExerciseInputType>(inputTypeRaw) ?: ExerciseInputType.WEIGHT_REPS
        set(value) { inputTypeRaw = value.raw }

    var category: ExerciseCategory?
        get() = rawValueOf<ExerciseCategory>(categoryRaw)
        set(value) { categoryRaw = value?.raw ?: "" }

    /** Vrsta koju je korisnik odabrao. Starija vježba bez vrste dobiva je po kategoriji. */
    var kind: ExerciseKind
        get() = rawValueOf<ExerciseKind>(kindRaw) ?: ExerciseKind.fallback(category)
        set(value) { kindRaw = value.raw }

    var equipment: Equipment?
        get() = rawValueOf<Equipment>(equipmentRaw)
        set(value) { equipmentRaw = value?.raw ?: "" }

    var muscles: List<Muscle>
        get() = musclesRaw.split(",").mapNotNull { rawValueOf<Muscle>(it) }
        set(value) { musclesRaw = value.joinToString(",") { it.raw } }

    val ref: ExerciseRef get() = ExerciseRef.custom(id, name)

    /** Sažetak za popis i pretragu, zajednički sa službenim vježbama. */
    val summary: ExerciseSummary
        get() = ExerciseSummary(
            source = ExerciseSummary.Source.Custom(id),
            name = name,
            category = category,
            kind = kind,
            muscles = muscles,
            equipment = equipment,
            isArchived = isArchived,
        )
}

@Serializable
class WorkoutTemplate(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var name: String = ""
    var details: String = ""
    var kindRaw: String = WorkoutKind.STRENGTH.raw
    var createdAt: Instant = Instant.now()

    @Transient val exercises: MutableList<TemplateExercise> = mutableListOf()

    constructor(name: String, kind: WorkoutKind = WorkoutKind.STRENGTH) : this() {
        this.name = name
        this.kindRaw = kind.raw
    }

    var kind: WorkoutKind
        get() = rawValueOf<WorkoutKind>(kindRaw) ?: WorkoutKind.STRENGTH
        set(value) { kindRaw = value.raw }

    val orderedExercises: List<TemplateExercise> get() = exercises.sortedBy { it.orderIndex }

    fun add(exercise: TemplateExercise): TemplateExercise {
        exercise.template = this
        exercises += exercise
        return exercise
    }
}

@Serializable
class TemplateExercise(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var templateId: UUID? = null
    var orderIndex: Int = 0
    var exerciseCatalogId: String? = null
    var exerciseCustomId: UUID? = null
    var exerciseName: String = ""
    var inputTypeRaw: String = ExerciseInputType.WEIGHT_REPS.raw

    /** Vježbe s istom vrijednošću čine superset. */
    var supersetGroupId: UUID? = null

    /** Pauza u sekundama; null znači zadana pauza iz Postavki. */
    var restSeconds: Int? = null
    var notes: String = ""

    @Transient var template: WorkoutTemplate? = null
        set(value) { field = value; templateId = value?.id }

    @Transient val sets: MutableList<TemplateSet> = mutableListOf()

    constructor(orderIndex: Int, exercise: ExerciseRef, inputType: ExerciseInputType = ExerciseInputType.WEIGHT_REPS) : this() {
        this.orderIndex = orderIndex
        this.exercise = exercise
        this.inputTypeRaw = inputType.raw
    }

    var inputType: ExerciseInputType
        get() = rawValueOf<ExerciseInputType>(inputTypeRaw) ?: ExerciseInputType.WEIGHT_REPS
        set(value) { inputTypeRaw = value.raw }

    var exercise: ExerciseRef
        get() = ExerciseRef(exerciseCatalogId, exerciseCustomId, exerciseName)
        set(value) {
            exerciseCatalogId = value.catalogId
            exerciseCustomId = value.customExerciseId
            exerciseName = value.name
        }

    val orderedSets: List<TemplateSet> get() = sets.sortedBy { it.orderIndex }

    fun add(set: TemplateSet): TemplateSet {
        set.exercise = this
        sets += set
        return set
    }
}

@Serializable
class TemplateSet(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var exerciseId: UUID? = null
    var orderIndex: Int = 0
    var kindRaw: String = SetKind.WORKING.raw

    /** Ciljana težina uvijek u kilogramima. */
    var targetWeightKg: Double? = null
    var targetReps: Int? = null

    /** Gornja granica raspona ponavljanja (npr. 8–12). null znači jedan cilj, [targetReps]. */
    var targetRepsMax: Int? = null

    @Transient var exercise: TemplateExercise? = null
        set(value) { field = value; exerciseId = value?.id }

    constructor(
        orderIndex: Int,
        kind: SetKind = SetKind.WORKING,
        targetWeightKg: Double? = null,
        targetReps: Int? = null,
    ) : this() {
        this.orderIndex = orderIndex
        this.kindRaw = kind.raw
        this.targetWeightKg = targetWeightKg
        this.targetReps = targetReps
    }

    var kind: SetKind
        get() = rawValueOf<SetKind>(kindRaw) ?: SetKind.WORKING
        set(value) { kindRaw = value.raw }
}

@Serializable
class Schedule(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var name: String = ""
    var details: String = ""

    /** null znači neograničen broj ciklusa. */
    var cycleCount: Int? = null
    var reminderModeRaw: String = ReminderMode.FLEXIBLE.raw

    /** Dani u tjednu (1 = nedjelja, kao Calendar.weekday na iOS-u) odvojeni zarezom, za način "fiksni dani". */
    var weekdaysRaw: String = ""

    /** Vrijeme podsjetnika u minutama od ponoći; null znači bez podsjetnika. */
    var reminderMinutes: Int? = null

    /** Fleksibilni podsjetnik: toliko dana nakon zadnjeg odrađenog treninga. */
    var reminderGapDays: Int = 1
    var isActive: Boolean = false
    var currentCycle: Int = 1

    /** Pozicija u nizu (indeks u [orderedItems]). */
    var currentPosition: Int = 0
    var createdAt: Instant = Instant.now()

    @Transient val items: MutableList<ScheduleItem> = mutableListOf()

    constructor(name: String) : this() {
        this.name = name
    }

    var reminderMode: ReminderMode
        get() = rawValueOf<ReminderMode>(reminderModeRaw) ?: ReminderMode.FLEXIBLE
        set(value) { reminderModeRaw = value.raw }

    var weekdays: List<Int>
        get() = weekdaysRaw.split(",").mapNotNull { it.toIntOrNull() }
        set(value) { weekdaysRaw = value.joinToString(",") }

    val orderedItems: List<ScheduleItem> get() = items.sortedBy { it.orderIndex }

    fun add(item: ScheduleItem): ScheduleItem {
        item.schedule = this
        items += item
        return item
    }
}

@Serializable
class ScheduleItem(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var scheduleId: UUID? = null
    var orderIndex: Int = 0
    var kindRaw: String = ScheduleItemKind.WORKOUT.raw

    /** Samo UUID, ne relacija: brisanje predloška ne smije dirati raspored ni povijest. */
    var workoutTemplateId: UUID? = null

    @Transient var schedule: Schedule? = null
        set(value) { field = value; scheduleId = value?.id }

    constructor(orderIndex: Int, kind: ScheduleItemKind, workoutTemplateId: UUID? = null) : this() {
        this.orderIndex = orderIndex
        this.kindRaw = kind.raw
        this.workoutTemplateId = workoutTemplateId
    }

    var kind: ScheduleItemKind
        get() = rawValueOf<ScheduleItemKind>(kindRaw) ?: ScheduleItemKind.WORKOUT
        set(value) { kindRaw = value.raw }
}

/** Privremena izmjena samo za jedan ciklus rasporeda. */
@Serializable
class CycleOverride(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var scheduleId: UUID? = null
    var cycleNumber: Int = 1
    var scheduleItemId: UUID? = null
    var kindRaw: String = CycleOverrideKind.SKIP_WORKOUT.raw

    /** `ExerciseRef.key` vježbe iz predloška na koju se izmjena odnosi. */
    var targetExerciseKey: String? = null
    var replacementCatalogId: String? = null
    var replacementCustomId: UUID? = null
    var replacementName: String? = null
    var replacementInputTypeRaw: String? = null

    constructor(scheduleId: UUID, cycleNumber: Int, scheduleItemId: UUID, kind: CycleOverrideKind) : this() {
        this.scheduleId = scheduleId
        this.cycleNumber = cycleNumber
        this.scheduleItemId = scheduleItemId
        this.kindRaw = kind.raw
    }

    var kind: CycleOverrideKind
        get() = rawValueOf<CycleOverrideKind>(kindRaw) ?: CycleOverrideKind.SKIP_WORKOUT
        set(value) { kindRaw = value.raw }

    var replacement: ExerciseRef?
        get() = if (replacementCatalogId == null && replacementCustomId == null) null
        else ExerciseRef(replacementCatalogId, replacementCustomId, replacementName ?: "")
        set(value) {
            replacementCatalogId = value?.catalogId
            replacementCustomId = value?.customExerciseId
            replacementName = value?.name
        }

    var replacementInputType: ExerciseInputType?
        get() = rawValueOf<ExerciseInputType>(replacementInputTypeRaw)
        set(value) { replacementInputTypeRaw = value?.raw }
}

// MARK: Izvedba

/** Odrađeni trening. Pri pokretanju kopira podatke iz predloška i nakon toga je neovisan o njemu. */
@Serializable
class Session(override var id: UUID = UUID.randomUUID()) : GymRecord {
    /** Samo za praćenje odakle je pokrenut. Ne smije biti relacija: brisanje predloška ne briše povijest. */
    var templateId: UUID? = null
    var scheduleId: UUID? = null

    /** Naziv u trenutku pokretanja. */
    var name: String = ""
    var kindRaw: String = WorkoutKind.STRENGTH.raw
    var startedAt: Instant = Instant.now()
    var endedAt: Instant? = null
    var stateRaw: String = SessionState.ACTIVE.raw
    var controllingDeviceRaw: String = DeviceRole.PHONE.raw
    var notes: String = ""

    /** Samo iz Health Connecta (ili Zdravlja u kopiji s iOS-a), nikad ručni unos. */
    var activeEnergyKilocalories: Double? = null
    var healthKitWorkoutId: UUID? = null
    var isImportedFromWorkoutsApp: Boolean = false
    var distanceMeters: Double? = null
    var averageHeartRate: Double? = null

    /** Napor cijelog treninga od 1 do 10 (session RPE, Foster i sur. 2001), neobavezno nakon treninga. */
    var sessionRPE: Double? = null

    /** Trening u zdravstvene podatke sprema sat (na Androidu zasad uvijek false). */
    var healthRecordedByWatch: Boolean = false

    /**
     * Rest timer se sprema kao trenutak početka i završetka (ne kao preostale sekunde), pa se nakon
     * oporavka ispravno nastavlja ili je već istekao. null znači da timer nije aktivan.
     */
    var restTimerStartedAt: Instant? = null
    var restTimerEndsAt: Instant? = null

    /** Zadnja promjena u treningu (za prepoznavanje zaboravljenog treninga i oporavak). */
    var lastActivityAt: Instant = Instant.now()

    @Transient val exercises: MutableList<SessionExercise> = mutableListOf()

    constructor(name: String, kind: WorkoutKind = WorkoutKind.STRENGTH, startedAt: Instant = Instant.now()) : this() {
        this.name = name
        this.kindRaw = kind.raw
        this.startedAt = startedAt
    }

    var kind: WorkoutKind
        get() = rawValueOf<WorkoutKind>(kindRaw) ?: WorkoutKind.STRENGTH
        set(value) { kindRaw = value.raw }

    var state: SessionState
        get() = rawValueOf<SessionState>(stateRaw) ?: SessionState.FINISHED
        set(value) { stateRaw = value.raw }

    var controllingDevice: DeviceRole
        get() = rawValueOf<DeviceRole>(controllingDeviceRaw) ?: DeviceRole.PHONE
        set(value) { controllingDeviceRaw = value.raw }

    val orderedExercises: List<SessionExercise> get() = exercises.sortedBy { it.orderIndex }

    fun add(exercise: SessionExercise): SessionExercise {
        exercise.session = this
        exercises += exercise
        return exercise
    }
}

@Serializable
class SessionExercise(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var sessionId: UUID? = null
    var orderIndex: Int = 0
    var exerciseCatalogId: String? = null
    var exerciseCustomId: UUID? = null
    var exerciseName: String = ""

    /** Ključ za upite (`ExerciseRef.key`), održava se pri svakoj promjeni vježbe. */
    var exerciseKey: String = ""
    var supersetGroupId: UUID? = null

    /** Vrsta unosa u trenutku dodavanja: povijest ostaje ispravna i ako se vlastita vježba kasnije promijeni. */
    var inputTypeRaw: String = ExerciseInputType.WEIGHT_REPS.raw

    /** Pauza u sekundama za ovu vježbu (ili superset); null znači zadana pauza. */
    var restSeconds: Int? = null

    /** Izbačena vježba ostaje do kraja treninga kako bi se mogla vratiti. */
    var isRemoved: Boolean = false

    /** Raspon ponavljanja radnih serija iz predloška (npr. 8–12), za prikaz cilja u treningu. */
    var targetRepsMin: Int? = null
    var targetRepsMax: Int? = null

    /** Promjena tereta koju je plan predložio pri pokretanju (dvostruka progresija, `SetPlanner`), u kg. */
    var loadChangeKg: Double? = null

    /** Bilješka uz vježbu iz predloška. */
    var notes: String = ""

    @Transient var session: Session? = null
        set(value) { field = value; sessionId = value?.id }

    @Transient val sets: MutableList<SetLog> = mutableListOf()

    constructor(orderIndex: Int, exercise: ExerciseRef, inputType: ExerciseInputType = ExerciseInputType.WEIGHT_REPS) : this() {
        this.orderIndex = orderIndex
        this.exercise = exercise
        this.inputTypeRaw = inputType.raw
    }

    var exercise: ExerciseRef
        get() = ExerciseRef(exerciseCatalogId, exerciseCustomId, exerciseName)
        set(value) {
            exerciseCatalogId = value.catalogId
            exerciseCustomId = value.customExerciseId
            exerciseName = value.name
            exerciseKey = value.key
        }

    var inputType: ExerciseInputType
        get() = rawValueOf<ExerciseInputType>(inputTypeRaw) ?: ExerciseInputType.WEIGHT_REPS
        set(value) { inputTypeRaw = value.raw }

    val orderedSets: List<SetLog> get() = sets.sortedBy { it.orderIndex }

    fun add(set: SetLog): SetLog {
        set.exercise = this
        sets += set
        return set
    }
}

@Serializable
class SetLog(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var exerciseId: UUID? = null
    var orderIndex: Int = 0
    var kindRaw: String = SetKind.WORKING.raw

    /** Težina uvijek u kilogramima. */
    var weightKg: Double? = null
    var reps: Int? = null

    /** Dodatna težina (vlastita težina + teret) ili pomoć (potpomognuta vježba), u kilogramima. */
    var extraWeightKg: Double? = null
    var durationSeconds: Int? = null
    var distanceMeters: Double? = null

    /** RPE od 1 do 10 u koracima od 0,5 (vidi [RPE.isValid]). RIR se računa za prikaz. */
    var rpe: Double? = null
    var completedAt: Instant? = null

    @Transient var exercise: SessionExercise? = null
        set(value) { field = value; exerciseId = value?.id }

    constructor(orderIndex: Int, kind: SetKind = SetKind.WORKING) : this() {
        this.orderIndex = orderIndex
        this.kindRaw = kind.raw
    }

    var kind: SetKind
        get() = rawValueOf<SetKind>(kindRaw) ?: SetKind.WORKING
        set(value) { kindRaw = value.raw }

    val isCompleted: Boolean get() = completedAt != null
}

// MARK: Ostalo

@Serializable
class BodyMeasurement(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var kindRaw: String = BodyMeasurementKind.WEIGHT.raw
    var customName: String? = null

    /** Metričke jedinice: kg za težinu, cm za ostalo. */
    var value: Double = 0.0
    var date: Instant = Instant.now()
    var sourceRaw: String = MeasurementSource.MANUAL.raw

    /** Id uzorka u zdravstvenim podacima (sprječava dvostruki uvoz). */
    var healthKitSampleId: UUID? = null

    constructor(
        kind: BodyMeasurementKind,
        value: Double,
        date: Instant = Instant.now(),
        source: MeasurementSource = MeasurementSource.MANUAL,
    ) : this() {
        this.kindRaw = kind.raw
        this.value = value
        this.date = date
        this.sourceRaw = source.raw
    }

    var kind: BodyMeasurementKind
        get() = rawValueOf<BodyMeasurementKind>(kindRaw) ?: BodyMeasurementKind.CUSTOM
        set(value) { kindRaw = value.raw }

    var source: MeasurementSource
        get() = rawValueOf<MeasurementSource>(sourceRaw) ?: MeasurementSource.MANUAL
        set(value) { sourceRaw = value.raw }
}

/** Kartica na Početnoj. To su kartice u aplikaciji, ne widgeti početnog zaslona. */
@Serializable
class DashboardCard(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var kindRaw: String = ""
    var orderIndex: Int = 0

    /** Postavke kartice kao JSON tekst. */
    var settingsJSON: String = ""

    constructor(kindRaw: String, orderIndex: Int) : this() {
        this.kindRaw = kindRaw
        this.orderIndex = orderIndex
    }
}

/** Postavke korisnika: u bazi mora postojati najviše jedan zapis (vidi [GymStore.settings]). */
@Serializable
class UserSettings(override var id: UUID = UUID.randomUUID()) : GymRecord {
    var weightUnitRaw: String = WeightUnit.KILOGRAMS.raw

    /** Zadana pauza za izolacijske i ostale vježbe. */
    var defaultRestSeconds: Int = 90

    /** Zadana pauza za složene vježbe (`RestDefaults`). */
    var compoundRestSeconds: Int = 150
    var themeRaw: String = "system"
    var accentColorRaw: String = "blue"
    var effortScaleRaw: String = EffortScale.RPE.raw
    var prEnabled: Boolean = true

    /** Praćeni tipovi PR-ova odvojeni zarezom. */
    var trackedPRKindsRaw: String = "maxWeight,maxVolume,maxReps"

    /** Vježbe (`ExerciseRef.key`) koje je korisnik isključio iz rekorda, odvojene zarezom. */
    var prExcludedExercisesRaw: String = ""

    /** Razina statistike ([StatsDetail]). */
    var statsDetailRaw: String = StatsDetail.PRO.raw

    /** Spol za DOTS bodove. Prazan tekst znači da korisnik nije odgovorio. */
    var sexRaw: String = ""
    var restEndSoundEnabled: Boolean = true

    /** Dostupne ploče u kilogramima, odvojene zarezom. */
    var availablePlatesRaw: String = "1.25,2.5,5,10,15,20,25"
    var barbellWeightKg: Double = 20.0

    /** Korak težine po opremi (`WeightStepSettings`). Prazno znači zadane korake. */
    var equipmentWeightStepsRaw: String = ""

    /** Vlastiti korak težine pojedinih vježbi (`WeightStepSettings`). */
    var exerciseWeightStepsRaw: String = ""

    /** Trajne bilješke vježbi (postavka sprave, hvat), JSON `{ključ vježbe: tekst}` ([ExerciseNotes]). */
    var exerciseNotesRaw: String = ""

    /** Onboarding. Prazan tekst znači da korisnik nije odgovorio. */
    var goalRaw: String = ""
    var experienceRaw: String = ""

    /** Dostupna oprema (`Equipment.raw`) odvojena zarezom. */
    var equipmentRaw: String = ""
    var trainingDaysPerWeek: Int? = null
    var onboardingCompleted: Boolean = false

    /** Povezivanje sa zdravstvenim podacima: odgovor iz onboardinga, mijenja se u Postavkama. */
    var wantsHealthKit: Boolean = false

    /** Podsjetnici rasporeda. */
    var notificationsEnabled: Boolean = true

    /** Obavijest o kraju odmora kad je mobitel zaključan ili je trening sažet u karticu. */
    var restNotificationEnabled: Boolean = true

    /** Na iOS-u: trening pokrenut na iPhoneu pokreće i sat. Android zasad nema sat. */
    var startsWatchWorkout: Boolean = true

    /**
     * Dvostruka progresija: prijedlog veće težine kad je prošli put dosegnuta gornja granica raspona ponavljanja
     * (`SetPlanner`). Isključeno znači da je težina uvijek kao prošli put.
     */
    var suggestsHeavierWeight: Boolean = true

    /** Tijelo koje se crta na prikazu mišića. */
    var bodyMapFemale: Boolean = false

    /** Obavijest u tijeku prati temu i boju aplikacije (Live Activity na iOS-u). */
    var liveActivityFollowsApp: Boolean = true
    var liveActivityThemeRaw: String = "system"
    var liveActivityAccentRaw: String = "blue"

    var goal: TrainingGoal?
        get() = rawValueOf<TrainingGoal>(goalRaw)
        set(value) { goalRaw = value?.raw ?: "" }

    var experience: ExperienceLevel?
        get() = rawValueOf<ExperienceLevel>(experienceRaw)
        set(value) { experienceRaw = value?.raw ?: "" }

    var equipment: List<Equipment>
        get() = equipmentRaw.split(",").mapNotNull { rawValueOf<Equipment>(it) }
        set(value) { equipmentRaw = value.joinToString(",") { it.raw } }

    var effortScale: EffortScale
        get() = rawValueOf<EffortScale>(effortScaleRaw) ?: EffortScale.RPE
        set(value) { effortScaleRaw = value.raw }

    var weightUnit: WeightUnit
        get() = WeightUnit.fromRaw(weightUnitRaw) ?: WeightUnit.KILOGRAMS
        set(value) { weightUnitRaw = value.raw }

    var theme: AppTheme
        get() = rawValueOf<AppTheme>(themeRaw) ?: AppTheme.SYSTEM
        set(value) { themeRaw = value.raw }

    var accent: AccentChoice
        get() = rawValueOf<AccentChoice>(accentColorRaw) ?: AccentChoice.BLUE
        set(value) { accentColorRaw = value.raw }

    var liveActivityTheme: AppTheme
        get() = rawValueOf<AppTheme>(liveActivityThemeRaw) ?: AppTheme.SYSTEM
        set(value) { liveActivityThemeRaw = value.raw }

    var liveActivityAccent: AccentChoice
        get() = rawValueOf<AccentChoice>(liveActivityAccentRaw) ?: AccentChoice.BLUE
        set(value) { liveActivityAccentRaw = value.raw }

    /** Tema koju obavijest u tijeku stvarno koristi: aplikacijina ili vlastita. */
    val effectiveLiveActivityTheme: AppTheme get() = if (liveActivityFollowsApp) theme else liveActivityTheme

    /** Naglasna boja koju obavijest u tijeku stvarno koristi. */
    val effectiveLiveActivityAccent: AccentChoice get() = if (liveActivityFollowsApp) accent else liveActivityAccent

    /** Kad se praćenje isključi, vlastita tema i boja kreću od trenutnih aplikacijinih. */
    fun changeLiveActivityFollowsApp(follows: Boolean) {
        if (follows == liveActivityFollowsApp) return
        if (!follows) {
            liveActivityTheme = theme
            liveActivityAccent = accent
        }
        liveActivityFollowsApp = follows
    }

    var availablePlatesKg: List<Double>
        get() = availablePlatesRaw.split(",").mapNotNull { it.toDoubleOrNull() }
        set(value) { availablePlatesRaw = value.joinToString(",") { swiftDoubleString(it) } }

    var sex: Sex?
        get() = rawValueOf<Sex>(sexRaw)
        set(value) { sexRaw = value?.raw ?: "" }

    var statsDetail: StatsDetail
        get() = rawValueOf<StatsDetail>(statsDetailRaw) ?: StatsDetail.PRO
        set(value) { statsDetailRaw = value.raw }

    /** Ključevi vježbi isključenih iz rekorda. */
    var prExcludedExerciseKeys: Set<String>
        get() = prExcludedExercisesRaw.split(",").filter { it.isNotEmpty() }.toSet()
        set(value) { prExcludedExercisesRaw = value.sorted().joinToString(",") }

    /** Uključuje ili isključuje vježbu iz rekorda. */
    fun setRecordsEnabled(enabled: Boolean, exerciseKey: String) {
        if (exerciseKey.isEmpty()) return
        prExcludedExerciseKeys = if (enabled) prExcludedExerciseKeys - exerciseKey else prExcludedExerciseKeys + exerciseKey
    }

    var trackedPRKinds: List<String>
        get() = trackedPRKindsRaw.split(",").filter { it.isNotEmpty() }
        set(value) { trackedPRKindsRaw = value.joinToString(",") }
}

/** Broj kao Swiftov `String(Double)`: 2.5 → "2.5", 20.0 → "20.0". Isti zapis postavki na obje platforme. */
internal fun swiftDoubleString(value: Double): String = value.toString()
