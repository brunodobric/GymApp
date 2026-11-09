import Connectivity
import SwiftUI
import Units

/// Početni ekran: kartica sljedećeg treninga svakog rasporeda (Započni izravno s kartice) i ostali treninzi.
/// Podaci stižu s iPhonea i ostaju spremljeni, pa trening može započeti i bez iPhonea u blizini.
struct WatchHomeView: View {
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.context.upcoming.isEmpty && store.context.templates.isEmpty {
                        Text("Napravi trening ili raspored u aplikaciji na iPhoneu i otvori je jednom dok je sat u blizini.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.context.upcoming) { plan in
                        WatchNextWorkoutCard(plan: plan)
                    }
                    if !store.context.templates.isEmpty {
                        Group {
                            if store.context.upcoming.isEmpty {
                                Text("Treninzi")
                            } else {
                                Text("Ostali treninzi")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.leading, 4)
                        ForEach(store.context.templates) { plan in
                            NavigationLink(value: plan) {
                                WatchPlanRow(plan: plan)
                            }
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
}

/// Broj vježbi i približno trajanje, npr. "6 vježbi · ~55 min".
struct WatchPlanMeta: View {
    let plan: PlannedWorkoutPayload
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            Text("\(plan.exercises.count) vježbi")
            if let minutes = plan.estimatedMinutes(restDefaults: store.context.restDefaults) {
                let approx = "~\(minutes)"
                Text(verbatim: "·")
                Text("\(approx) min")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Kartica sljedećeg treninga rasporeda, kao na Početnoj na iPhoneu. Dodir na naziv otvara pregled vježbi.
private struct WatchNextWorkoutCard: View {
    let plan: PlannedWorkoutPayload
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: plan) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        WatchWorkoutMixIcon(mix: plan.mix)
                        Group {
                            if let schedule = plan.scheduleName {
                                Text("Sljedeći") + Text(verbatim: " · \(schedule)")
                            } else {
                                Text("Sljedeći")
                            }
                        }
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                    }
                    .font(.eyebrow)
                    .textCase(.uppercase)
                    Text(plan.name)
                        .font(.cardTitle)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    WatchPlanMeta(plan: plan)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                store.begin(plan)
            } label: {
                Label("Započni", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.white.opacity(0.1), in: .rect(cornerRadius: 18))
    }
}

/// Redak treninga izvan rasporeda: ikona vrste, naziv, broj vježbi i trajanje.
private struct WatchPlanRow: View {
    let plan: PlannedWorkoutPayload

    var body: some View {
        HStack(spacing: 10) {
            WatchWorkoutMixIcon(mix: plan.mix)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.itemTitle)
                    .lineLimit(2)
                WatchPlanMeta(plan: plan)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Pregled treninga prije početka: vježbe i serije, uz veliki gumb Započni.
struct WatchPlanView: View {
    let plan: PlannedWorkoutPayload
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        List {
            Section {
                Button {
                    store.begin(plan)
                } label: {
                    Label("Započni", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            } footer: {
                WatchPlanMeta(plan: plan)
            }

            ForEach(Array(plan.exercises.enumerated()), id: \.offset) { _, exercise in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.exercise.name).font(.itemTitle)
                        Text("\(exercise.sets.count) serija").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if exercise.isCardio == true {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.tint)
                            .accessibilityLabel(Text("Kardio"))
                    }
                }
            }
        }
        .navigationTitle(plan.name)
    }
}
