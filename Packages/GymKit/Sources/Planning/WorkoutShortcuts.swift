import Foundation
import Models
import SwiftData
import Training

/// Ishod pokretanja treninga iz Prečaca, Sirija ili Action buttona.
public enum ShortcutStartResult {
    /// Trening je već u tijeku: novi se ne pokreće, nego se otvara taj.
    case alreadyActive(Session)
    case started(Session)
    /// Nema aktivnog rasporeda s treningom koji slijedi.
    case nothingScheduled
}

/// Ishod završavanja treninga iz Prečaca ili Sirija.
public enum ShortcutFinishResult {
    case noActiveWorkout
    /// Trening vodi Apple Watch: završava se na satu, koji ga i sprema u Zdravlje.
    case ledByWatch(Session)
    /// Nijedna serija nije završena, pa se trening ne može spremiti (na ekranu treninga nudi se odbacivanje).
    case nothingCompleted(Session)
    case finished(Session)
}

public enum ShortcutError: Error, Equatable {
    /// Odabrani trening je u međuvremenu obrisan ili više nema vježbi.
    case templateUnavailable
}

/// Radnje za App Intents (Prečaci, Siri, Action button, automatizacije). Pravila su ista kao na Početnoj
/// i ekranu treninga, a aplikacija nakon njih samo javlja promjenu satu, Live Activityju i podsjetnicima.
public struct WorkoutShortcuts {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Spremljeni treninzi koje akcija "Započni trening" nudi (isti kao izbor na Početnoj).
    public func startableTemplates() throws -> [WorkoutTemplate] {
        TemplateStarter.startable(try context.fetch(FetchDescriptor<WorkoutTemplate>()))
    }

    /// Pokreće spremljeni trening, a bez njega prazan trening s nazivom `emptyName`.
    ///
    /// Ako je odabrani trening u aktivnom rasporedu, pokreće se kao trening rasporeda (s izmjenama ciklusa),
    /// pa raspored napreduje kad se završi, isto kao "Odaberi drugi trening" ispod rasporeda na Početnoj.
    public func start(templateId: UUID?, emptyName: String, now: Date = Date()) throws -> ShortcutStartResult {
        if let active = try GymQueries(context: context).activeSession() { return .alreadyActive(active) }
        guard let templateId else {
            return .started(try WorkoutEngine(context: context).startSession(name: emptyName, now: now))
        }
        guard let template = try startableTemplates().first(where: { $0.id == templateId }) else {
            throw ShortcutError.templateUnavailable
        }
        if let planned = try scheduled(templateId: templateId) {
            return .started(try TemplateStarter(context: context).start(planned, now: now))
        }
        return .started(try TemplateStarter(context: context).start(template, now: now))
    }

    /// Pokreće sljedeći trening aktivnog rasporeda (prvog, ako ih je više), kao prvi gumb na Početnoj.
    public func startNextScheduled(now: Date = Date()) throws -> ShortcutStartResult {
        if let active = try GymQueries(context: context).activeSession() { return .alreadyActive(active) }
        guard let planned = try ScheduleEngine(context: context).upcomingWorkouts().first else { return .nothingScheduled }
        return .started(try TemplateStarter(context: context).start(planned, now: now))
    }

    /// Završava trening u tijeku kao gumb "Završi": nezavršene serije se brišu, a raspored napreduje
    /// ako je to bio njegov trening.
    public func finishActive(now: Date = Date()) throws -> ShortcutFinishResult {
        guard let session = try GymQueries(context: context).activeSession() else { return .noActiveWorkout }
        guard session.controllingDevice == .phone else { return .ledByWatch(session) }
        do {
            try WorkoutEngine(context: context).finishSession(session, now: now)
        } catch WorkoutError.nothingCompleted {
            return .nothingCompleted(session)
        }
        try ScheduleEngine(context: context).sessionFinished(session)
        return .finished(session)
    }

    /// Trening iz aktivnog rasporeda s tim predloškom: prvo sljedeći trening, zatim ostali treninzi rasporeda.
    private func scheduled(templateId: UUID) throws -> PlannedWorkout? {
        let engine = ScheduleEngine(context: context)
        let upcoming = try engine.upcomingWorkouts()
        if let next = upcoming.first(where: { $0.template.id == templateId }) { return next }
        for planned in upcoming {
            if let choice = try engine.workoutChoices(of: planned.schedule).first(where: { $0.template.id == templateId }) {
                return choice
            }
        }
        return nil
    }
}
