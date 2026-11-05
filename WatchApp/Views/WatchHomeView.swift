import Connectivity
import SwiftUI
import Units

/// Početni ekran: sljedeći trening svakog rasporeda i ostali treninzi. Podaci stižu s iPhonea
/// i ostaju spremljeni, pa trening može započeti i bez iPhonea u blizini.
struct WatchHomeView: View {
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if store.context.upcoming.isEmpty && store.context.templates.isEmpty {
                    Text("Napravi trening ili raspored u aplikaciji na iPhoneu i otvori je jednom dok je sat u blizini.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !store.context.upcoming.isEmpty {
                    Section("Sljedeći") {
                        ForEach(store.context.upcoming) { plan in
                            planLink(plan, subtitle: plan.scheduleName)
                        }
                    }
                }
                if !store.context.templates.isEmpty {
                    Section("Treninzi") {
                        ForEach(store.context.templates) { plan in
                            planLink(plan, subtitle: nil)
                        }
                    }
                }
            }
            .navigationTitle("Trening")
            .navigationDestination(for: PlannedWorkoutPayload.self) { plan in
                WatchPlanView(plan: plan)
            }
        }
    }

    private func planLink(_ plan: PlannedWorkoutPayload, subtitle: String?) -> some View {
        NavigationLink(value: plan) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name).font(.itemTitle)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Vježbe: \(plan.exercises.count)").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Pregled treninga prije početka: vježbe i serije, uz veliki gumb Započni.
struct WatchPlanView: View {
    let plan: PlannedWorkoutPayload
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        List {
            Button {
                store.begin(plan)
            } label: {
                Label("Započni", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .listRowBackground(Color.clear)

            ForEach(Array(plan.exercises.enumerated()), id: \.offset) { _, exercise in
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.exercise.name).font(.itemTitle)
                    Text("Serije: \(exercise.sets.count)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(plan.name)
    }
}
