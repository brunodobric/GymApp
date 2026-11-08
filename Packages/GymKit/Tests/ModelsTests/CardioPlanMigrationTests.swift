import Foundation
import SwiftData
import Testing
@testable import Models

private func makeContext() throws -> ModelContext {
    ModelContext(try GymPersistence.makeUserContainer(storage: .inMemory))
}

@Suite("Migracija kardio planova za sat")
struct CardioPlanMigrationTests {

    @Test("Kardio plan postaje trening istog naziva i id-ja, bez plana")
    func convertsPlan() throws {
        let context = try makeContext()
        let plan = WorkoutTemplate(name: "Trčanje 5 km", kind: .cardio)
        plan.cardioPlanRaw = #"{"activity":"running","intervals":[],"location":"outdoor"}"#
        let strength = WorkoutTemplate(name: "Push")
        context.insert(plan)
        context.insert(strength)
        try context.save()
        let id = plan.id

        #expect(try CardioPlanMigration.migrate(in: context) == 1)

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(templates.count == 2)
        #expect(templates.allSatisfy { $0.kind == .strength && $0.cardioPlanRaw == nil })
        #expect(templates.first { $0.id == id }?.name == "Trčanje 5 km")
    }

    @Test("Bez kardio planova ništa se ne mijenja, a drugi poziv ne radi ništa")
    func idempotent() throws {
        let context = try makeContext()
        context.insert(WorkoutTemplate(name: "Push"))
        context.insert(WorkoutTemplate(name: "Bicikl", kind: .cardio))
        try context.save()

        #expect(try CardioPlanMigration.migrate(in: context) == 1)
        #expect(try CardioPlanMigration.migrate(in: context) == 0)
    }
}
