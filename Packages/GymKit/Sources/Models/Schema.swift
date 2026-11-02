import SwiftData

/// Verzija 1 sheme korisničke baze (sinkronizira se preko CloudKita).
/// Modeli su ugniježđeni u ovaj prostor imena kako bi se kasnije mogle dodati verzije (V2, ...)
/// uz zadržavanje starih definicija za migraciju. Nakon prvog izdanja shema se samo proširuje.
///
/// Pravila CloudKita koja svi modeli poštuju:
/// * svako svojstvo ima zadanu vrijednost ili je opcionalno,
/// * nema `@Attribute(.unique)`,
/// * sve relacije su opcionalne i imaju obrnutu relaciju,
/// * redoslijed se čuva u `orderIndex`, nikad u poretku polja.
public enum GymSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            CustomExercise.self,
            Schedule.self,
            ScheduleItem.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateSet.self,
            CycleOverride.self,
            Session.self,
            SessionExercise.self,
            SetLog.self,
            BodyMeasurement.self,
            DashboardCard.self,
            UserSettings.self,
        ]
    }
}

// Trenutna verzija: ostatak koda koristi ove nazive.
public typealias CustomExercise = GymSchemaV1.CustomExercise
public typealias Schedule = GymSchemaV1.Schedule
public typealias ScheduleItem = GymSchemaV1.ScheduleItem
public typealias WorkoutTemplate = GymSchemaV1.WorkoutTemplate
public typealias TemplateExercise = GymSchemaV1.TemplateExercise
public typealias TemplateSet = GymSchemaV1.TemplateSet
public typealias CycleOverride = GymSchemaV1.CycleOverride
public typealias Session = GymSchemaV1.Session
public typealias SessionExercise = GymSchemaV1.SessionExercise
public typealias SetLog = GymSchemaV1.SetLog
public typealias BodyMeasurement = GymSchemaV1.BodyMeasurement
public typealias DashboardCard = GymSchemaV1.DashboardCard
public typealias UserSettings = GymSchemaV1.UserSettings

public enum GymMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
