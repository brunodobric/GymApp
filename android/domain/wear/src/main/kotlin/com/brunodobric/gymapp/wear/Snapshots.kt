package com.brunodobric.gymapp.wear

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.RawValued
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.InstantSerializer
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.UUIDSerializer
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.training.SetValues
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

// Snimka treninga koja putuje između mobitela i sata (`SessionSnapshot` na iOS-u, specifikacija, odjeljak 6).
// Uređaj koji vodi trening šalje cijelu snimku nakon svake promjene, a drugi je primjenjuje ako je novija od onoga
// što već ima (zadnja promjena pobjeđuje). Sve vrijednosti su obične strukture bez veze s bazom, pa sat ne treba
// bazu mobitela.

/** Enum kao njegov `raw` tekst, isti kao na iOS-u. Nepoznata vrijednost (novija verzija) daje [fallback]. */
open class RawEnumSerializer<T>(name: String, private val values: List<T>, private val fallback: T) : KSerializer<T>
    where T : Enum<T>, T : RawValued {
    override val descriptor = PrimitiveSerialDescriptor("wear.$name", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: T) = encoder.encodeString(value.raw)
    override fun deserialize(decoder: Decoder): T {
        val raw = decoder.decodeString()
        return values.firstOrNull { it.raw == raw } ?: fallback
    }
}

object SetKindSerializer : RawEnumSerializer<SetKind>("SetKind", SetKind.entries, SetKind.WORKING)
object WorkoutKindSerializer : RawEnumSerializer<WorkoutKind>("WorkoutKind", WorkoutKind.entries, WorkoutKind.STRENGTH)
object SessionStateSerializer : RawEnumSerializer<SessionState>("SessionState", SessionState.entries, SessionState.FINISHED)
object DeviceRoleSerializer : RawEnumSerializer<DeviceRole>("DeviceRole", DeviceRole.entries, DeviceRole.PHONE)
object InputTypeSerializer :
    RawEnumSerializer<ExerciseInputType>("ExerciseInputType", ExerciseInputType.entries, ExerciseInputType.WEIGHT_REPS)

/** Referenca na vježbu u protokolu: katalog ili vlastita vježba i naziv za prikaz. */
@Serializable
private data class ExerciseRefSurrogate(
    val catalogId: String? = null,
    @Serializable(UUIDSerializer::class) val customExerciseId: UUID? = null,
    val name: String = "",
)

object ExerciseRefSerializer : KSerializer<ExerciseRef> {
    override val descriptor = ExerciseRefSurrogate.serializer().descriptor
    override fun serialize(encoder: Encoder, value: ExerciseRef) =
        encoder.encodeSerializableValue(ExerciseRefSurrogate.serializer(), ExerciseRefSurrogate(value.catalogId, value.customExerciseId, value.name))
    override fun deserialize(decoder: Decoder): ExerciseRef {
        val surrogate = decoder.decodeSerializableValue(ExerciseRefSurrogate.serializer())
        return ExerciseRef(surrogate.catalogId, surrogate.customExerciseId, surrogate.name)
    }
}

@Serializable
data class SetSnapshot(
    @Serializable(UUIDSerializer::class) val id: UUID = UUID.randomUUID(),
    val orderIndex: Int,
    @Serializable(SetKindSerializer::class) val kind: SetKind = SetKind.WORKING,
    /** Težina uvijek u kilogramima. */
    val weightKg: Double? = null,
    val reps: Int? = null,
    val extraWeightKg: Double? = null,
    val durationSeconds: Int? = null,
    val distanceMeters: Double? = null,
    val rpe: Double? = null,
    @Serializable(InstantSerializer::class) val completedAt: Instant? = null,
) {
    val isCompleted: Boolean get() = completedAt != null

    /** Vrijednosti za pravila iz `training` (potpunost serije, volumen). */
    val values: SetValues get() = SetValues(kind, weightKg, reps, extraWeightKg, durationSeconds, distanceMeters, rpe)
}

@Serializable
data class ExerciseSnapshot(
    @Serializable(UUIDSerializer::class) val id: UUID = UUID.randomUUID(),
    val orderIndex: Int,
    @Serializable(ExerciseRefSerializer::class) val exercise: ExerciseRef,
    @Serializable(InputTypeSerializer::class) val inputType: ExerciseInputType,
    @Serializable(UUIDSerializer::class) val supersetGroupId: UUID? = null,
    val restSeconds: Int? = null,
    val isRemoved: Boolean = false,
    val sets: List<SetSnapshot> = emptyList(),
    /**
     * Korak težine vježbe u jedinici prikaza, za okretni okvir i gumbe na satu. Ne sprema se u bazu: mobitel ga
     * računa iz postavki pri svakoj snimci. null je korak jedinice.
     */
    val weightStep: Double? = null,
    /** Raspon ponavljanja radnih serija iz predloška (npr. 8–12). null bez cilja. */
    val targetRepsMin: Int? = null,
    val targetRepsMax: Int? = null,
    /** Prijedlog veće težine u kg (dvostruka progresija, `SetPlanner`). null bez prijedloga. */
    val loadChangeKg: Double? = null,
    /** Bilješka uz vježbu iz predloška. null bez bilješke. */
    val notes: String? = null,
) {
    val orderedSets: List<SetSnapshot> get() = sets.sortedBy { it.orderIndex }

    val isFullyCompleted: Boolean get() = sets.all { it.isCompleted }

    val completedSetCount: Int get() = sets.count { it.isCompleted }

    /** Ista vježba bez serija: za usporedbu promjena na razini vježbe. */
    internal val withoutSets: ExerciseSnapshot get() = copy(sets = emptyList())

    /** Redni broj serije među serijama iste vrste (0 za prvu radnu ili prvu seriju zagrijavanja). */
    fun position(setId: UUID): Int? {
        val ordered = orderedSets
        val set = ordered.firstOrNull { it.id == setId } ?: return null
        return ordered.filter { it.kind == set.kind }.indexOfFirst { it.id == setId }
    }

    /** Broj za oznaku serije kao na mobitelu: radne serije su 1, 2, 3…, a zagrijavanje nema broja. */
    fun workingNumber(setId: UUID): Int? {
        val set = sets.firstOrNull { it.id == setId }?.takeIf { it.kind == SetKind.WORKING } ?: return null
        return position(set.id)?.plus(1)
    }
}

@Serializable
data class SessionSnapshot(
    @Serializable(UUIDSerializer::class) val id: UUID = UUID.randomUUID(),
    val name: String,
    @Serializable(WorkoutKindSerializer::class) val kind: WorkoutKind = WorkoutKind.STRENGTH,
    @Serializable(UUIDSerializer::class) val templateId: UUID? = null,
    @Serializable(UUIDSerializer::class) val scheduleId: UUID? = null,
    @Serializable(InstantSerializer::class) val startedAt: Instant,
    @Serializable(InstantSerializer::class) val endedAt: Instant? = null,
    @Serializable(SessionStateSerializer::class) val state: SessionState = SessionState.ACTIVE,
    @Serializable(DeviceRoleSerializer::class) val controllingDevice: DeviceRole,
    val notes: String = "",
    @Serializable(InstantSerializer::class) val restTimerStartedAt: Instant? = null,
    @Serializable(InstantSerializer::class) val restTimerEndsAt: Instant? = null,
    /** Samo iz zdravstvenih podataka (sat je mjerio). */
    val activeEnergyKilocalories: Double? = null,
    val averageHeartRate: Double? = null,
    @Serializable(UUIDSerializer::class) val healthWorkoutId: UUID? = null,
    val distanceMeters: Double? = null,
    /** Trenutak zadnje promjene (`Session.lastActivityAt`). Starija snimka nikad ne prepisuje noviju. */
    @Serializable(InstantSerializer::class) val updatedAt: Instant,
    val exercises: List<ExerciseSnapshot> = emptyList(),
) {
    val orderedExercises: List<ExerciseSnapshot> get() = exercises.sortedBy { it.orderIndex }

    /** Vježbe koje se prikazuju (bez izbačenih), po redoslijedu. */
    val visibleExercises: List<ExerciseSnapshot> get() = orderedExercises.filter { !it.isRemoved }

    val completedSetCount: Int get() = visibleExercises.sumOf { it.completedSetCount }

    /** Vježbe kojima su sve serije završene. */
    val completedExerciseCount: Int get() = visibleExercises.count { it.sets.isNotEmpty() && it.isFullyCompleted }

    fun exercise(id: UUID): ExerciseSnapshot? = exercises.firstOrNull { it.id == id }

    /** Vježba kojoj serija pripada. */
    fun exerciseContaining(setId: UUID): ExerciseSnapshot? = exercises.firstOrNull { exercise -> exercise.sets.any { it.id == setId } }

    fun set(id: UUID): SetSnapshot? = exercises.firstNotNullOfOrNull { exercise -> exercise.sets.firstOrNull { it.id == id } }

    /**
     * Je li ova snimka novija od zadanog trenutka (zadnja promjena pobjeđuje). Jednako vrijeme se prihvaća, jer isti
     * uređaj može poslati dvije promjene u istoj milisekundi.
     */
    fun isNewer(than: Instant): Boolean = !updatedAt.isBefore(than)
}
