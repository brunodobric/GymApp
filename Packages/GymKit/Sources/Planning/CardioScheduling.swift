import Foundation
import Models
import SwiftData

// Kardio iz rasporeda (faza 10): plan se preko WorkoutKita zakazuje u aplikaciju Workout na satu
// za termin podsjetnika, korisnik ga pokreće na satu, a odrađeni trening se uvozi iz Zdravlja i
// povezuje s rasporedom. Ovdje je logika bez WorkoutKita; aplikacija samo prevodi u njegove tipove.

/// Id plana u WorkoutKitu za jedan trening rasporeda u jednom ciklusu.
///
/// Id se izvodi iz rasporeda, stavke, ciklusa i sadržaja plana, pa ga svaki uređaj izračuna jednako
/// i ne treba ga spremati. Kad se plan u predlošku promijeni, mijenja se i id, pa se stari plan
/// na satu zamjenjuje novim.
public enum CardioPlanID {
    public static func make(scheduleId: UUID, scheduleItemId: UUID, cycle: Int, planRaw: String) -> UUID {
        let text = "\(scheduleId.uuidString)|\(scheduleItemId.uuidString)|\(cycle)|\(planRaw)"
        let bytes = Array(text.utf8)
        var high = fnv1a(bytes, seed: 0xCBF2_9CE4_8422_2325)
        var low = fnv1a(bytes, seed: 0x8422_2325_CBF2_9CE4)
        var result = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            result[index] = UInt8(truncatingIfNeeded: high)
            result[index + 8] = UInt8(truncatingIfNeeded: low)
            high >>= 8
            low >>= 8
        }
        // Oznake verzije (5, izveden iz imena) i varijante (RFC 4122).
        result[6] = (result[6] & 0x0F) | 0x50
        result[8] = (result[8] & 0x3F) | 0x80
        return UUID(uuid: (
            result[0], result[1], result[2], result[3], result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11], result[12], result[13], result[14], result[15]
        ))
    }

    /// Id plana za sljedeći trening rasporeda, ili nil ako to nije kardio s ispravnim planom.
    public static func make(for planned: PlannedWorkout) -> UUID? {
        guard planned.template.kind == .cardio, let raw = planned.template.cardioPlanRaw,
              planned.template.cardioPlan?.isValid == true else { return nil }
        return make(scheduleId: planned.schedule.id, scheduleItemId: planned.item.id, cycle: planned.cycle, planRaw: raw)
    }

    private static func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// Kardio plan koji treba biti na satu: sljedeći trening rasporeda.
public struct CardioScheduleRequest: Equatable, Sendable {
    public let planId: UUID
    public let scheduleId: UUID
    public let templateId: UUID
    /// Naziv treninga, prikazuje se u aplikaciji Workout.
    public let name: String
    public let plan: CardioPlan
    /// Termin prvog sljedećeg podsjetnika. nil kad raspored nema podsjetnike: plan se tada zakazuje samo ručno.
    public let date: Date?

    public init(planId: UUID, scheduleId: UUID, templateId: UUID, name: String, plan: CardioPlan, date: Date?) {
        self.planId = planId
        self.scheduleId = scheduleId
        self.templateId = templateId
        self.name = name
        self.plan = plan
        self.date = date
    }
}

/// Plan koji je već zakazan u WorkoutKitu (`ScheduledWorkoutPlan`).
public struct ScheduledCardioPlan: Equatable, Hashable, Sendable {
    public let planId: UUID
    public let date: Date
    /// Sat je plan označio odrađenim.
    public let isComplete: Bool

    public init(planId: UUID, date: Date, isComplete: Bool) {
        self.planId = planId
        self.date = date
        self.isComplete = isComplete
    }
}

/// Što treba maknuti sa sata i što zakazati.
public struct CardioScheduleChanges: Equatable, Sendable {
    public var remove: [ScheduledCardioPlan] = []
    public var add: [CardioScheduleRequest] = []

    public init(remove: [ScheduledCardioPlan] = [], add: [CardioScheduleRequest] = []) {
        self.remove = remove
        self.add = add
    }

    public var isEmpty: Bool { remove.isEmpty && add.isEmpty }
}

public enum CardioScheduleSync {
    /// Usporedba zakazanog i željenog stanja.
    ///
    /// * Plan kojeg više nema u rasporedu (raspored je napredovao, trening je promijenjen ili raspored ugašen) se miče.
    /// * Neodrađeni plan iz prošlog dana se miče, a plan se zakazuje za novi termin.
    /// * Plan koji je već zakazan danas ili ranije od termina podsjetnika (npr. ručno) ostaje.
    /// * Odrađeni plan ostaje dok se trening ne uveze iz Zdravlja i raspored ne napreduje.
    /// * Ukupno na satu nikad nije više od `limit` planova; prednost imaju raniji termini.
    public static func changes(
        requests: [CardioScheduleRequest], scheduled: [ScheduledCardioPlan], now: Date,
        calendar: Calendar = .current, limit: Int
    ) -> CardioScheduleChanges {
        let today = calendar.startOfDay(for: now)
        let wanted = Set(requests.map(\.planId))
        var remove = scheduled.filter { !wanted.contains($0.planId) || (!$0.isComplete && $0.date < today) }
        var kept = scheduled.filter { !remove.contains($0) }
        var add: [CardioScheduleRequest] = []

        let ordered = requests.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        for request in ordered {
            let existing = kept.filter { $0.planId == request.planId }
            guard let date = request.date, !existing.contains(where: \.isComplete) else { continue }
            if existing.contains(where: { $0.date < date.addingTimeInterval(60) }) { continue }
            // Plan je zakazan kasnije od novog termina: premješta se.
            remove += existing
            kept.removeAll { $0.planId == request.planId }
            add.append(request)
        }

        let room = max(limit - kept.count, 0)
        return CardioScheduleChanges(remove: remove, add: Array(add.prefix(room)))
    }
}

public struct CardioScheduleBuilder {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Kardio planovi koji trebaju biti na satu: sljedeći trening svakog aktivnog rasporeda, ako je kardio,
    /// s prvim sljedećim terminom podsjetnika.
    public func requests(now: Date = Date(), calendar: Calendar = .current) throws -> [CardioScheduleRequest] {
        let reminders = try ReminderBuilder(context: context).plannedReminders(now: now, calendar: calendar)
        return try ScheduleEngine(context: context).upcomingWorkouts().compactMap { planned in
            guard let planId = CardioPlanID.make(for: planned), let plan = planned.template.cardioPlan else { return nil }
            let date = reminders.filter { $0.scheduleId == planned.schedule.id }.map(\.fireDate).min()
            return CardioScheduleRequest(
                planId: planId, scheduleId: planned.schedule.id, templateId: planned.template.id,
                name: planned.template.name, plan: plan, date: date
            )
        }
    }
}

/// Povezuje kardio treninge uvezene iz Zdravlja sa sljedećim treningom rasporeda, pa raspored napreduje.
public struct CardioPlanLinker {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Uvezeni trening pripada planu ako ga je sat zapisao uz taj plan (`Session.workoutPlanId`).
    /// Kad Zdravlje ne zna plan, a WorkoutKit javlja da je plan odrađen, povezuje se prvi nepovezani
    /// uvezeni kardio trening istog dana kao termin plana.
    /// Vraća broj povezanih treninga.
    @discardableResult
    public func linkImportedSessions(completedPlans: [ScheduledCardioPlan] = [], calendar: Calendar = .current) throws -> Int {
        let engine = ScheduleEngine(context: context)
        var candidates = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)]))
            .filter { $0.isImportedFromWorkoutsApp && $0.state == .finished && $0.kind == .cardio && $0.scheduleId == nil }
        var linked = 0

        var progressed = true
        while progressed, !candidates.isEmpty {
            progressed = false
            for planned in try engine.upcomingWorkouts() {
                guard let planId = CardioPlanID.make(for: planned) else { continue }
                var match = candidates.first { $0.workoutPlanId == planId }
                if match == nil, let done = completedPlans.first(where: { $0.planId == planId && $0.isComplete }) {
                    match = candidates.first {
                        $0.workoutPlanId == nil && calendar.isDate($0.startedAt, inSameDayAs: done.date)
                    }
                }
                guard let session = match else { continue }
                session.scheduleId = planned.schedule.id
                session.templateId = planned.template.id
                session.name = planned.template.name
                try context.save()
                try engine.sessionFinished(session)
                candidates.removeAll { $0.id == session.id }
                linked += 1
                progressed = true
                // Raspored je napredovao: sljedeći treninzi se računaju iznova.
                break
            }
        }
        return linked
    }
}
