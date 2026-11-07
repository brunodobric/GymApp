import Catalog
import Foundation
import SwiftData

// Katalog i planiranje: vlastite vježbe, predlošci, rasporedi.
// Predložak je ono što je planirano. Odrađeni trening (Session) je odvojen model i ne ovisi o predlošku.

extension GymSchemaV1 {

    @Model
    public final class CustomExercise {
        public var id: UUID = UUID()
        public var name: String = ""
        public var details: String = ""
        public var categoryRaw: String = ""
        /// Mišići odvojeni zarezom (CloudKit ne voli nizove).
        public var musclesRaw: String = ""
        public var equipmentRaw: String = ""
        public var inputTypeRaw: String = ExerciseInputType.weightReps.rawValue
        @Attribute(.externalStorage) public var imageData: Data?
        public var isArchived: Bool = false
        public var createdAt: Date = Date()

        public init(name: String, inputType: ExerciseInputType = .weightReps) {
            self.name = name
            self.inputTypeRaw = inputType.rawValue
        }

        public var inputType: ExerciseInputType {
            get { ExerciseInputType(rawValue: inputTypeRaw) ?? .weightReps }
            set { inputTypeRaw = newValue.rawValue }
        }

        public var category: ExerciseCategory? {
            get { ExerciseCategory(rawValue: categoryRaw) }
            set { categoryRaw = newValue?.rawValue ?? "" }
        }

        public var equipment: Equipment? {
            get { Equipment(rawValue: equipmentRaw) }
            set { equipmentRaw = newValue?.rawValue ?? "" }
        }

        public var muscles: [Muscle] {
            get { musclesRaw.split(separator: ",").compactMap { Muscle(rawValue: String($0)) } }
            set { musclesRaw = newValue.map(\.rawValue).joined(separator: ",") }
        }

        public var ref: ExerciseRef {
            ExerciseRef(customExerciseId: id, name: name)
        }
    }

    @Model
    public final class WorkoutTemplate {
        public var id: UUID = UUID()
        public var name: String = ""
        public var details: String = ""
        public var kindRaw: String = WorkoutKind.strength.rawValue
        public var createdAt: Date = Date()
        /// Plan kardio treninga (`CardioPlan` kao JSON), samo za vrstu `cardio`. Kardio trening nema vježbe.
        public var cardioPlanRaw: String?
        @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
        public var exercises: [TemplateExercise]? = []

        public init(name: String, kind: WorkoutKind = .strength) {
            self.name = name
            self.kindRaw = kind.rawValue
        }

        public var kind: WorkoutKind {
            get { WorkoutKind(rawValue: kindRaw) ?? .strength }
            set { kindRaw = newValue.rawValue }
        }

        public var orderedExercises: [TemplateExercise] {
            (exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        }

        public var cardioPlan: CardioPlan? {
            get { CardioPlan.decode(cardioPlanRaw) }
            set { cardioPlanRaw = newValue?.encoded }
        }
    }

    @Model
    public final class TemplateExercise {
        public var id: UUID = UUID()
        public var orderIndex: Int = 0
        public var exerciseCatalogId: String?
        public var exerciseCustomId: UUID?
        public var exerciseName: String = ""
        public var inputTypeRaw: String = ExerciseInputType.weightReps.rawValue
        /// Vježbe s istom vrijednošću čine superset.
        public var supersetGroupId: UUID?
        /// Pauza u sekundama; nil znači zadana pauza iz Postavki.
        public var restSeconds: Int?
        public var notes: String = ""
        public var template: WorkoutTemplate?
        @Relationship(deleteRule: .cascade, inverse: \TemplateSet.exercise)
        public var sets: [TemplateSet]? = []

        public init(orderIndex: Int, exercise: ExerciseRef, inputType: ExerciseInputType = .weightReps) {
            self.orderIndex = orderIndex
            self.exercise = exercise
            self.inputTypeRaw = inputType.rawValue
        }

        public var inputType: ExerciseInputType {
            get { ExerciseInputType(rawValue: inputTypeRaw) ?? .weightReps }
            set { inputTypeRaw = newValue.rawValue }
        }

        public var exercise: ExerciseRef {
            get { ExerciseRef(catalogId: exerciseCatalogId, customExerciseId: exerciseCustomId, name: exerciseName) }
            set {
                exerciseCatalogId = newValue.catalogId
                exerciseCustomId = newValue.customExerciseId
                exerciseName = newValue.name
            }
        }

        public var orderedSets: [TemplateSet] {
            (sets ?? []).sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    @Model
    public final class TemplateSet {
        public var id: UUID = UUID()
        public var orderIndex: Int = 0
        public var kindRaw: String = SetKind.working.rawValue
        /// Ciljana težina uvijek u kilogramima.
        public var targetWeightKg: Double?
        public var targetReps: Int?
        /// Gornja granica raspona ponavljanja (npr. 8–12, dvostruka progresija). nil znači jedan cilj, `targetReps`.
        public var targetRepsMax: Int?
        public var exercise: TemplateExercise?

        public init(orderIndex: Int, kind: SetKind = .working, targetWeightKg: Double? = nil, targetReps: Int? = nil) {
            self.orderIndex = orderIndex
            self.kindRaw = kind.rawValue
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
        }

        public var kind: SetKind {
            get { SetKind(rawValue: kindRaw) ?? .working }
            set { kindRaw = newValue.rawValue }
        }
    }

    @Model
    public final class Schedule {
        public var id: UUID = UUID()
        public var name: String = ""
        public var details: String = ""
        /// nil znači neograničen broj ciklusa.
        public var cycleCount: Int?
        public var reminderModeRaw: String = ReminderMode.flexible.rawValue
        /// Dani u tjednu (Calendar.weekday: 1 = nedjelja) odvojeni zarezom, za način "fiksni dani".
        public var weekdaysRaw: String = ""
        /// Vrijeme podsjetnika u minutama od ponoći; nil znači bez podsjetnika.
        public var reminderMinutes: Int?
        /// Fleksibilni podsjetnik: toliko dana nakon zadnjeg odrađenog treninga.
        public var reminderGapDays: Int = 1
        public var isActive: Bool = false
        public var currentCycle: Int = 1
        /// Pozicija u nizu (indeks u `orderedItems`).
        public var currentPosition: Int = 0
        public var createdAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \ScheduleItem.schedule)
        public var items: [ScheduleItem]? = []

        public init(name: String) {
            self.name = name
        }

        public var reminderMode: ReminderMode {
            get { ReminderMode(rawValue: reminderModeRaw) ?? .flexible }
            set { reminderModeRaw = newValue.rawValue }
        }

        public var weekdays: [Int] {
            get { weekdaysRaw.split(separator: ",").compactMap { Int($0) } }
            set { weekdaysRaw = newValue.map(String.init).joined(separator: ",") }
        }

        public var orderedItems: [ScheduleItem] {
            (items ?? []).sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    @Model
    public final class ScheduleItem {
        public var id: UUID = UUID()
        public var orderIndex: Int = 0
        public var kindRaw: String = ScheduleItemKind.workout.rawValue
        /// Samo UUID, ne relacija: brisanje predloška ne smije dirati raspored ni povijest.
        public var workoutTemplateId: UUID?
        public var schedule: Schedule?

        public init(orderIndex: Int, kind: ScheduleItemKind, workoutTemplateId: UUID? = nil) {
            self.orderIndex = orderIndex
            self.kindRaw = kind.rawValue
            self.workoutTemplateId = workoutTemplateId
        }

        public var kind: ScheduleItemKind {
            get { ScheduleItemKind(rawValue: kindRaw) ?? .workout }
            set { kindRaw = newValue.rawValue }
        }
    }

    /// Privremena izmjena samo za jedan ciklus rasporeda.
    @Model
    public final class CycleOverride {
        public var id: UUID = UUID()
        public var scheduleId: UUID?
        public var cycleNumber: Int = 1
        public var scheduleItemId: UUID?
        public var kindRaw: String = CycleOverrideKind.skipWorkout.rawValue
        /// `ExerciseRef.key` vježbe iz predloška na koju se izmjena odnosi.
        public var targetExerciseKey: String?
        public var replacementCatalogId: String?
        public var replacementCustomId: UUID?
        public var replacementName: String?
        public var replacementInputTypeRaw: String?

        public init(scheduleId: UUID, cycleNumber: Int, scheduleItemId: UUID, kind: CycleOverrideKind) {
            self.scheduleId = scheduleId
            self.cycleNumber = cycleNumber
            self.scheduleItemId = scheduleItemId
            self.kindRaw = kind.rawValue
        }

        public var kind: CycleOverrideKind {
            get { CycleOverrideKind(rawValue: kindRaw) ?? .skipWorkout }
            set { kindRaw = newValue.rawValue }
        }

        public var replacement: ExerciseRef? {
            get {
                guard replacementCatalogId != nil || replacementCustomId != nil else { return nil }
                return ExerciseRef(
                    catalogId: replacementCatalogId,
                    customExerciseId: replacementCustomId,
                    name: replacementName ?? ""
                )
            }
            set {
                replacementCatalogId = newValue?.catalogId
                replacementCustomId = newValue?.customExerciseId
                replacementName = newValue?.name
            }
        }

        public var replacementInputType: ExerciseInputType? {
            get { replacementInputTypeRaw.flatMap(ExerciseInputType.init(rawValue:)) }
            set { replacementInputTypeRaw = newValue?.rawValue }
        }
    }
}
