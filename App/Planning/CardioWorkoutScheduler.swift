import Foundation
import HealthKit
import Models
import OSLog
import Planning
import SwiftData
import WorkoutKit

/// Zakazuje kardio planove iz rasporeda u aplikaciju Workout na satu (WorkoutKit `WorkoutScheduler`).
///
/// * Za sljedeći kardio trening svakog aktivnog rasporeda zakazuje se plan za termin prvog podsjetnika.
///   Raspored bez podsjetnika ne zakazuje ništa sam; plan se tada zakazuje ručno s pregleda treninga.
/// * Kad raspored napreduje, trening se promijeni ili raspored ugasi, stari plan se miče sa sata.
/// * Korisnik plan pokreće sam na satu. Odrađeni trening stiže kroz uvoz iz Zdravlja i povezuje se
///   s rasporedom (`CardioPlanLinker`), pa raspored napreduje.
///
/// Što treba promijeniti računa GymKit (`CardioScheduleSync`); ovdje je samo prijevod u WorkoutKit.
/// Poziva se iz `ReminderScheduler.refresh`, dakle nakon svake promjene rasporeda, treninga i uvoza.
@MainActor
@Observable
final class CardioWorkoutScheduler {
    static let shared = CardioWorkoutScheduler()

    /// Planovi koje je ova aplikacija zakazala na sat (zadnje poznato stanje).
    private(set) var scheduled: [ScheduledCardioPlan] = []
    private(set) var authorization: WorkoutScheduler.AuthorizationState = .notDetermined

    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "WorkoutKit")

    /// Zakazivanje radi samo na iPhoneu s uparenim satom.
    var isSupported: Bool { WorkoutScheduler.isSupported }

    /// Usklađuje planove na satu s rasporedima. Pozivi idu redom, pa se dva usklađivanja ne preklapaju.
    func refresh(context: ModelContext) {
        let previous = queue
        queue = Task {
            await previous?.value
            await sync(context: context)
        }
    }

    /// Plan za sljedeći trening rasporeda, ako je zakazan na sat.
    func scheduledPlan(for planned: PlannedWorkout) -> ScheduledCardioPlan? {
        guard let planId = CardioPlanID.make(for: planned) else { return nil }
        return scheduled.filter { $0.planId == planId }.min { $0.date < $1.date }
    }

    /// Ručno zakazivanje s pregleda treninga: plan se zakazuje za sljedeću minutu, pa je odmah na satu.
    /// Vraća false kad zakazivanje nije moguće (nema sata ili korisnik nije dopustio).
    func scheduleNow(_ planned: PlannedWorkout) async -> Bool {
        guard isSupported, let planId = CardioPlanID.make(for: planned), let plan = planned.template.cardioPlan,
              await ensureAuthorization() else { return false }
        let scheduler = WorkoutScheduler.shared
        await scheduler.schedule(Self.workoutPlan(plan, id: planId, name: planned.template.name), at: Self.components(Date().addingTimeInterval(60)))
        scheduled = await Self.currentPlans().map(\.entry)
        return scheduled.contains { $0.planId == planId }
    }

    // MARK: Usklađivanje

    private func sync(context: ModelContext) async {
        guard isSupported else { return }
        let scheduler = WorkoutScheduler.shared
        authorization = await scheduler.authorizationState
        let current = await Self.currentPlans()
        scheduled = current.map(\.entry)

        // Prvo povezivanje odrađenih planova s uvezenim treninzima: raspored može napredovati.
        do {
            if try CardioPlanLinker(context: context).linkImportedSessions(completedPlans: scheduled) > 0 {
                // Novi sljedeći trening: podsjetnici i ovo usklađivanje kreću iznova.
                ReminderScheduler.refresh(context: context)
                return
            }
        } catch {
            logger.error("Povezivanje uvezenog kardija: \(error.localizedDescription)")
        }

        let requests: [CardioScheduleRequest]
        do {
            requests = try CardioScheduleBuilder(context: context).requests()
        } catch {
            logger.error("Kardio planovi iz rasporeda: \(error.localizedDescription)")
            return
        }
        // Dozvola se traži tek kad postoji plan za zakazivanje, dakle nakon što je korisnik složio raspored.
        if !requests.contains(where: { $0.date != nil }) && current.isEmpty { return }
        guard await ensureAuthorization() else { return }

        let changes = CardioScheduleSync.changes(
            requests: requests, scheduled: scheduled, now: Date(),
            limit: WorkoutScheduler.maxAllowedScheduledWorkoutCount
        )
        guard !changes.isEmpty else { return }
        for stale in changes.remove {
            for match in current where match.entry == stale {
                await scheduler.remove(match.plan.plan, at: match.plan.date)
            }
        }
        for request in changes.add {
            guard let date = request.date else { continue }
            let plan = Self.workoutPlan(request.plan, id: request.planId, name: request.name)
            await scheduler.schedule(plan, at: Self.components(date))
        }
        scheduled = await Self.currentPlans().map(\.entry)
    }

    private func ensureAuthorization() async -> Bool {
        let scheduler = WorkoutScheduler.shared
        authorization = await scheduler.authorizationState
        if authorization == .notDetermined {
            authorization = await scheduler.requestAuthorization()
        }
        return authorization == .authorized
    }

    // MARK: Prijevod u WorkoutKit

    private struct Current {
        let plan: ScheduledWorkoutPlan
        let entry: ScheduledCardioPlan
    }

    private static func currentPlans() async -> [Current] {
        await WorkoutScheduler.shared.scheduledWorkouts.compactMap { item in
            guard let date = Calendar.current.date(from: item.date) else { return nil }
            return Current(plan: item, entry: ScheduledCardioPlan(planId: item.plan.id, date: date, isComplete: item.complete))
        }
    }

    private static func components(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    static func workoutPlan(_ plan: CardioPlan, id: UUID, name: String) -> WorkoutPlan {
        let workout = CustomWorkout(
            activity: plan.activity.workoutActivity,
            location: plan.location.sessionLocation,
            displayName: name,
            warmup: plan.warmup.map { WorkoutStep(goal: $0.workoutGoal) },
            blocks: plan.intervals.map { interval in
                var steps = [IntervalStep(.work, goal: interval.work.workoutGoal)]
                if let recovery = interval.recovery {
                    steps.append(IntervalStep(.recovery, goal: recovery.workoutGoal))
                }
                return IntervalBlock(steps: steps, iterations: interval.repeats)
            },
            cooldown: plan.cooldown.map { WorkoutStep(goal: $0.workoutGoal) }
        )
        return WorkoutPlan(.custom(workout), id: id)
    }
}

extension CardioActivity {
    var workoutActivity: HKWorkoutActivityType {
        switch self {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case .hiking: .hiking
        }
    }
}

extension CardioLocation {
    var sessionLocation: HKWorkoutSessionLocationType {
        switch self {
        case .outdoor: .outdoor
        case .indoor: .indoor
        }
    }
}

extension CardioGoal {
    /// Cijele minute i kilometri prikazuju se na satu u tim jedinicama, ostalo u sekundama i metrima.
    var workoutGoal: WorkoutGoal {
        switch self {
        case .open:
            .open
        case .time(let seconds):
            seconds.truncatingRemainder(dividingBy: 60) == 0 ? .time(seconds / 60, .minutes) : .time(seconds, .seconds)
        case .distance(let meters):
            meters.truncatingRemainder(dividingBy: 1_000) == 0 ? .distance(meters / 1_000, .kilometers) : .distance(meters, .meters)
        }
    }
}
