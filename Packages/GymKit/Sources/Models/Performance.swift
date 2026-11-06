import Catalog
import Foundation
import SwiftData

// Izvedba: odrađeni trening. Pri pokretanju kopira podatke iz predloška i nakon toga je neovisan o njemu.

extension GymSchemaV1 {

    @Model
    public final class Session {
        public var id: UUID = UUID()
        /// Samo za praćenje odakle je pokrenut. Ne smije biti relacija: brisanje predloška ne briše povijest.
        public var templateId: UUID?
        public var scheduleId: UUID?
        /// Naziv u trenutku pokretanja.
        public var name: String = ""
        public var kindRaw: String = WorkoutKind.strength.rawValue
        public var startedAt: Date = Date()
        public var endedAt: Date?
        public var stateRaw: String = SessionState.active.rawValue
        public var controllingDeviceRaw: String = DeviceRole.phone.rawValue
        public var notes: String = ""
        /// Samo iz HealthKita, nikad ručni unos.
        public var activeEnergyKilocalories: Double?
        public var healthKitWorkoutId: UUID?
        public var isImportedFromWorkoutsApp: Bool = false
        /// Plan iz WorkoutKita po kojem je uvezeni trening odrađen na satu (veza s rasporedom, faza 10).
        public var workoutPlanId: UUID?
        public var distanceMeters: Double?
        public var averageHeartRate: Double?
        /// Trening vodi iPhone, a sat je za njega pokrenuo sesiju u Zdravlju (puls, kalorije). Tada trening u
        /// Zdravlje sprema sat, a iPhone ne, da u Zdravlju ne bude dvaput.
        public var healthRecordedByWatch: Bool = false
        /// Rest timer se sprema kao trenutak početka i završetka (ne kao preostale sekunde), pa se nakon
        /// oporavka ispravno nastavlja ili je već istekao. nil znači da timer nije aktivan.
        public var restTimerStartedAt: Date?
        public var restTimerEndsAt: Date?
        /// Zadnja promjena u treningu (za prepoznavanje zaboravljenog treninga i oporavak).
        public var lastActivityAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
        public var exercises: [SessionExercise]? = []

        public init(name: String, kind: WorkoutKind = .strength, startedAt: Date = Date()) {
            self.name = name
            self.kindRaw = kind.rawValue
            self.startedAt = startedAt
        }

        public var kind: WorkoutKind {
            get { WorkoutKind(rawValue: kindRaw) ?? .strength }
            set { kindRaw = newValue.rawValue }
        }

        public var state: SessionState {
            get { SessionState(rawValue: stateRaw) ?? .finished }
            set { stateRaw = newValue.rawValue }
        }

        public var controllingDevice: DeviceRole {
            get { DeviceRole(rawValue: controllingDeviceRaw) ?? .phone }
            set { controllingDeviceRaw = newValue.rawValue }
        }

        public var orderedExercises: [SessionExercise] {
            (exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    @Model
    public final class SessionExercise {
        public var id: UUID = UUID()
        public var orderIndex: Int = 0
        public var exerciseCatalogId: String?
        public var exerciseCustomId: UUID?
        public var exerciseName: String = ""
        /// Ključ za upite (`ExerciseRef.key`), održava se pri svakoj promjeni vježbe.
        public var exerciseKey: String = ""
        public var supersetGroupId: UUID?
        /// Vrsta unosa u trenutku dodavanja: povijest ostaje ispravna i ako se vlastita vježba kasnije promijeni.
        public var inputTypeRaw: String = ExerciseInputType.weightReps.rawValue
        /// Pauza u sekundama za ovu vježbu (ili superset); nil znači zadana pauza iz Postavki.
        public var restSeconds: Int?
        /// Izbačena vježba ostaje do kraja treninga kako bi se mogla vratiti.
        public var isRemoved: Bool = false
        public var session: Session?
        @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise)
        public var sets: [SetLog]? = []

        public init(orderIndex: Int, exercise: ExerciseRef, inputType: ExerciseInputType = .weightReps) {
            self.orderIndex = orderIndex
            self.exercise = exercise
            self.inputTypeRaw = inputType.rawValue
        }

        public var exercise: ExerciseRef {
            get { ExerciseRef(catalogId: exerciseCatalogId, customExerciseId: exerciseCustomId, name: exerciseName) }
            set {
                exerciseCatalogId = newValue.catalogId
                exerciseCustomId = newValue.customExerciseId
                exerciseName = newValue.name
                exerciseKey = newValue.key
            }
        }

        public var inputType: ExerciseInputType {
            get { ExerciseInputType(rawValue: inputTypeRaw) ?? .weightReps }
            set { inputTypeRaw = newValue.rawValue }
        }

        public var orderedSets: [SetLog] {
            (sets ?? []).sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    @Model
    public final class SetLog {
        public var id: UUID = UUID()
        public var orderIndex: Int = 0
        public var kindRaw: String = SetKind.working.rawValue
        /// Težina uvijek u kilogramima.
        public var weightKg: Double?
        public var reps: Int?
        /// Dodatna težina (vlastita težina + teret) ili pomoć (potpomognuta vježba), u kilogramima.
        public var extraWeightKg: Double?
        public var durationSeconds: Int?
        public var distanceMeters: Double?
        /// RPE od 1 do 10 u koracima od 0,5 (vidi `RPE.isValid`). RIR se računa za prikaz.
        public var rpe: Double?
        public var completedAt: Date?
        public var exercise: SessionExercise?

        public init(orderIndex: Int, kind: SetKind = .working) {
            self.orderIndex = orderIndex
            self.kindRaw = kind.rawValue
        }

        public var kind: SetKind {
            get { SetKind(rawValue: kindRaw) ?? .working }
            set { kindRaw = newValue.rawValue }
        }

        public var isCompleted: Bool { completedAt != nil }
    }
}
