import AppIntents
import Foundation
import Planning

/// Spremljeni trening kao parametar akcije "Započni trening". Nude se isti treninzi kao u izboru na Početnoj
/// (`TemplateStarter.startable`): treninzi snage s barem jednom vježbom.
struct WorkoutTemplateEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trening")
    static let defaultQuery = WorkoutTemplateQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WorkoutTemplateQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [WorkoutTemplateEntity] {
        let wanted = Set(identifiers)
        return await ShortcutActions.templates().filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [WorkoutTemplateEntity] {
        await ShortcutActions.templates().filter {
            $0.name.range(of: string, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    func suggestedEntities() async throws -> [WorkoutTemplateEntity] {
        await ShortcutActions.templates()
    }
}
