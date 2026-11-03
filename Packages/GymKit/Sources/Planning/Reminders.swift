import Foundation
import Models
import SwiftData

/// Podsjetnik koji treba zakazati.
public struct PlannedReminder: Equatable, Sendable {
    public let scheduleId: UUID
    public let scheduleName: String
    public let workoutName: String?
    public let fireDate: Date
    /// Sljedeći trening rasporeda na koji podsjetnik upućuje.
    public var scheduleItemId: UUID?
    public var templateId: UUID?
    public var cycle: Int = 1
    /// Kardio trening se pokreće na satu u aplikaciji Workout (faza 10).
    public var isCardio = false

    public init(
        scheduleId: UUID, scheduleName: String, workoutName: String?, fireDate: Date,
        scheduleItemId: UUID? = nil, templateId: UUID? = nil, cycle: Int = 1, isCardio: Bool = false
    ) {
        self.scheduleId = scheduleId
        self.scheduleName = scheduleName
        self.workoutName = workoutName
        self.fireDate = fireDate
        self.scheduleItemId = scheduleItemId
        self.templateId = templateId
        self.cycle = cycle
        self.isCardio = isCardio
    }

    init(_ planned: PlannedWorkout, fireDate: Date) {
        self.init(
            scheduleId: planned.schedule.id, scheduleName: planned.schedule.name, workoutName: planned.template.name,
            fireDate: fireDate, scheduleItemId: planned.item.id, templateId: planned.template.id, cycle: planned.cycle,
            isCardio: planned.template.kind == .cardio
        )
    }

    /// Stabilan identifikator za zakazivanje i otkazivanje.
    public var identifier: String { "schedule-\(scheduleId.uuidString)-\(Int(fireDate.timeIntervalSince1970))" }
}

/// Računanje termina podsjetnika. Čista logika, bez baze i obavijesti.
public enum ReminderPlanner {
    /// Koliko dana unaprijed se zakazuju fiksni podsjetnici.
    public static let horizonDays = 14

    /// Fiksni dani: svaki odabrani dan u tjednu u zadano vrijeme, osim dana kad je trening već odrađen.
    /// `weekdays` su `Calendar.weekday` vrijednosti (1 = nedjelja).
    public static func fixedDates(
        weekdays: [Int], minutesOfDay: Int, now: Date, completedDays: Set<Date>,
        calendar: Calendar = .current, horizonDays: Int = ReminderPlanner.horizonDays
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var result: [Date] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  !completedDays.contains(day),
                  let fire = calendar.date(byAdding: .minute, value: minutesOfDay, to: day),
                  fire > now else { continue }
            result.append(fire)
        }
        return result
    }

    /// Fleksibilno: `gapDays` dana nakon zadnjeg odrađenog treninga, a svaki rest dan u nizu prije sljedećeg
    /// treninga dodaje još jedan dan. Bez ijednog treninga ili kad je termin prošao, sljedeće zadano vrijeme.
    public static func flexibleDate(
        lastWorkoutAt: Date?, gapDays: Int, restDaysBeforeNext: Int, minutesOfDay: Int, now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        if let lastWorkoutAt {
            let base = calendar.startOfDay(for: lastWorkoutAt)
            let days = max(gapDays, 0) + max(restDaysBeforeNext, 0)
            if let day = calendar.date(byAdding: .day, value: days, to: base),
               let fire = calendar.date(byAdding: .minute, value: minutesOfDay, to: day), fire > now {
                return fire
            }
        }
        guard let todayFire = calendar.date(byAdding: .minute, value: minutesOfDay, to: today) else { return nil }
        if todayFire > now { return todayFire }
        return calendar.date(byAdding: .day, value: 1, to: todayFire)
    }
}

/// Podsjetnici svih aktivnih rasporeda, spremni za zakazivanje.
public struct ReminderBuilder {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Tijekom aktivnog treninga nema podsjetnika (već zakazani se otkazuju); isto vrijedi
    /// za raspored bez vremena podsjetnika, neaktivan raspored i raspored bez sljedećeg treninga.
    public func reminders(now: Date = Date(), calendar: Calendar = .current) throws -> [PlannedReminder] {
        if try GymQueries(context: context).activeSession() != nil { return [] }
        return try plannedReminders(now: now, calendar: calendar)
    }

    /// Termini podsjetnika bez obzira na aktivni trening. Kardio planovi na satu se prema njima zakazuju
    /// i tijekom treninga snage, jer plan na satu ne smeta kao obavijest.
    public func plannedReminders(now: Date = Date(), calendar: Calendar = .current) throws -> [PlannedReminder] {
        let engine = ScheduleEngine(context: context)
        let finished = try context.fetch(FetchDescriptor<Session>()).filter { $0.state == .finished }
        var result: [PlannedReminder] = []

        for schedule in try context.fetch(FetchDescriptor<Schedule>(sortBy: [SortDescriptor(\.createdAt)])) {
            guard schedule.isActive, let minutes = schedule.reminderMinutes,
                  let next = try engine.nextWorkout(of: schedule) else { continue }
            let own = finished.filter { $0.scheduleId == schedule.id }

            switch schedule.reminderMode {
            case .fixedDays:
                let completed = Set(own.map { calendar.startOfDay(for: $0.startedAt) })
                let dates = ReminderPlanner.fixedDates(
                    weekdays: schedule.weekdays, minutesOfDay: minutes, now: now,
                    completedDays: completed, calendar: calendar
                )
                result += dates.map { PlannedReminder(next, fireDate: $0) }
            case .flexible:
                let last = own.map { $0.endedAt ?? $0.startedAt }.max()
                let items = schedule.orderedItems
                let nextIndex = items.firstIndex { $0.id == next.item.id } ?? schedule.currentPosition
                let rests = items.indices.contains(schedule.currentPosition) && nextIndex >= schedule.currentPosition
                    ? items[schedule.currentPosition..<nextIndex].filter { $0.kind == .restDay }.count : 0
                if let date = ReminderPlanner.flexibleDate(
                    lastWorkoutAt: last, gapDays: schedule.reminderGapDays, restDaysBeforeNext: rests,
                    minutesOfDay: minutes, now: now, calendar: calendar
                ) {
                    result.append(PlannedReminder(next, fireDate: date))
                }
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }
}
