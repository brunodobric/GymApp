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
        public var distanceMeters: Double?
        public var averageHeartRate: Double?
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
        /// Izbačena vježba ostaje do kraja treninga kako bi se mogla vratiti.
        public var isRemoved: Bool = false
        public var session: Session?
        @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise)
        public var sets: [SetLog]? = []

        public init(orderIndex: Int, exercise: ExerciseRef) {
            self.orderIndex = orderIndex
            self.exercise = exercise
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
