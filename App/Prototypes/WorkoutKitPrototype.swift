#if DEBUG
import SwiftUI
import WorkoutKit

// Prototip 2: zakazivanje plana trčanja u aplikaciju Workout na satu
// preko WorkoutScheduler (specifikacija, odjeljak 6).
// Cilj je provjeriti: dozvole, maksimalan broj zakazanih planova,
// kako plan izgleda na satu i što se dogodi bez uparenog sata.

@MainActor
@Observable
final class WorkoutKitPrototypeModel {
    private(set) var authorization = "nepoznato"
    private(set) var scheduled: [String] = []
    private(set) var log: [String] = []

    var isSupported: Bool { WorkoutScheduler.isSupported }
    var maxCount: Int { WorkoutScheduler.maxAllowedScheduledWorkoutCount }

    func refresh() async {
        authorization = String(describing: await WorkoutScheduler.shared.authorizationState)
        let plans = await WorkoutScheduler.shared.scheduledWorkouts
        scheduled = plans.map { plan in
            let date = Calendar.current.date(from: plan.date)?.formatted(date: .abbreviated, time: .shortened) ?? "?"
            return "\(date) · završen: \(plan.complete ? "da" : "ne")"
        }
    }

    func requestAuthorization() async {
        let state = await WorkoutScheduler.shared.requestAuthorization()
        append("Dozvola: \(state)")
        await refresh()
    }

    /// Zakazuje "5 km" trčanje: zagrijavanje 10 min, 5 km rada, hlađenje 5 min.
    func scheduleRun(minutesFromNow: Int) async {
        let workout = CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: "GymApp prototip 5 km",
            warmup: WorkoutStep(goal: .time(10, .minutes)),
            blocks: [
                IntervalBlock(steps: [IntervalStep(.work, goal: .distance(5, .kilometers))], iterations: 1),
            ],
            cooldown: WorkoutStep(goal: .time(5, .minutes))
        )
        let plan = WorkoutPlan(.custom(workout))
        let start = Date().addingTimeInterval(TimeInterval(minutesFromNow * 60))
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        await WorkoutScheduler.shared.schedule(plan, at: components)
        append("Zakazano za \(start.formatted(date: .omitted, time: .shortened))")
        await refresh()
    }

    func removeAll() async {
        await WorkoutScheduler.shared.removeAllWorkouts()
        append("Svi zakazani planovi uklonjeni")
        await refresh()
    }

    private func append(_ text: String) {
        log.insert("\(Date().formatted(date: .omitted, time: .standard))  \(text)", at: 0)
    }
}

struct WorkoutKitPrototypeView: View {
    @State private var model = WorkoutKitPrototypeModel()

    var body: some View {
        List {
            Section("Stanje") {
                LabeledContent("Podržano", value: model.isSupported ? "da" : "ne")
                LabeledContent("Dozvola", value: model.authorization)
                LabeledContent("Najviše planova", value: "\(model.maxCount)")
            }

            Section {
                Button("Zatraži dozvolu", systemImage: "lock.open") {
                    Task { await model.requestAuthorization() }
                }
                Button("Zakaži trčanje za 5 min", systemImage: "figure.run") {
                    Task { await model.scheduleRun(minutesFromNow: 5) }
                }
                Button("Zakaži trčanje za 24 h", systemImage: "calendar.badge.plus") {
                    Task { await model.scheduleRun(minutesFromNow: 24 * 60) }
                }
                Button("Ukloni sve zakazano", systemImage: "trash", role: .destructive) {
                    Task { await model.removeAll() }
                }
            } footer: {
                Text("Nakon zakazivanja otvori aplikaciju Workout na satu i provjeri pojavljuje li se plan i može li se pokrenuti.")
            }

            Section("Zakazano (\(model.scheduled.count))") {
                ForEach(model.scheduled, id: \.self) { Text($0) }
            }

            Section("Zapis") {
                ForEach(model.log, id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        }
        .navigationTitle("WorkoutKit")
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
    }
}
#endif
