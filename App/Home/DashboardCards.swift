import Models
import Planning
import Stats
import SwiftData
import SwiftUI
import Training
import Units

extension DashboardCardKind {
    var title: LocalizedStringKey {
        switch self {
        case .lastWorkout: "Zadnji trening"
        case .plateCalculator: "Kalkulator ploča"
        case .nextWorkout: "Sljedeći trening"
        case .weeklyVolume: "Tjedni volumen"
        }
    }

    var symbol: String {
        switch self {
        case .lastWorkout: "clock.arrow.circlepath"
        case .plateCalculator: "scalemass"
        case .nextWorkout: "calendar.badge.clock"
        case .weeklyVolume: "chart.bar.fill"
        }
    }
}

/// Okvir kartice na Početnoj, istog izgleda kao kartice u statistici.
struct HomeCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    /// Vrsta treninga: naslov tada ima ikonu vrste (`WorkoutKindIcon`) umjesto `symbol`.
    var mix: SessionMix?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Naslov kartice je u boji svoje ikone (akcent iz Postavki).
            Group {
                if let mix {
                    Label { Text(title) } icon: { WorkoutKindIcon(mix: mix) }
                } else {
                    Label(title, systemImage: symbol)
                }
            }
                .font(.cardHeading)
                .textCase(.uppercase)
                .foregroundStyle(.tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.card))
    }
}

/// Zadnji odrađeni trening: datum, trajanje i tip. Dodir otvara detalje.
struct LastWorkoutCard: View {
    let session: Session
    let unit: WeightUnit

    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]

    private var duration: String? {
        guard let end = session.endedAt else { return nil }
        return Duration.seconds(max(0, end.timeIntervalSince(session.startedAt)))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        NavigationLink {
            SessionDetailScreen(session: session, unit: unit)
        } label: {
            let mix = SessionCardio.mix(of: session, isCardio: catalogStore.isCardio(custom: customExercises))
            HomeCard(title: "Zadnji trening", symbol: session.kind.symbol, mix: mix) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.cardTitle).foregroundStyle(.primary)
                    Text(session.startedAt.formatted(date: .complete, time: .shortened))
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text(mix.title)
                        if let duration { Text("·"); Text(duration) }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Kalkulator ploča: dodir na cijelu karticu otvara kalkulator preko cijelog ekrana.
struct PlateCalculatorCard: View {
    let unit: WeightUnit

    var body: some View {
        NavigationLink {
            PlateCalculatorScreen(unit: unit)
        } label: {
            HomeCard(title: DashboardCardKind.plateCalculator.title, symbol: DashboardCardKind.plateCalculator.symbol) {
                Text("Koje ploče staviti na svaku stranu šipke.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Sljedeći trening svakog aktivnog rasporeda. Dodir na trening otvara njegov pregled.
struct NextWorkoutCard: View {
    let planned: [PlannedWorkout]

    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]

    var body: some View {
        HomeCard(title: DashboardCardKind.nextWorkout.title, symbol: DashboardCardKind.nextWorkout.symbol) {
            if planned.isEmpty {
                Text("Nema aktivnog rasporeda. Raspored složiš u tabu Rasporedi.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            // Dodir otvara pregled sljedećeg treninga, isto kao u tabu Rasporedi.
            ForEach(planned, id: \.item.id) { workout in
                NavigationLink {
                    UpcomingWorkoutScreen(schedule: workout.schedule)
                } label: {
                    HStack {
                        WorkoutKindIcon(
                            mix: SessionCardio.mix(of: workout.template, isCardio: catalogStore.isCardio(custom: customExercises)),
                            cardioSymbol: workout.template.cardioPlanSymbol
                        )
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.template.name).font(.cardTitle).foregroundStyle(.primary)
                            Text(workout.schedule.name).font(.subheadline).foregroundStyle(.secondary)
                            Text(exercisesText(workout))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func exercisesText(_ workout: PlannedWorkout) -> String {
        if workout.template.kind == .cardio {
            return workout.template.cardioPlan.map(CardioText.summary) ?? ""
        }
        let names = workout.exercises.map(\.ref.name)
        let shown = names.prefix(4).joined(separator: ", ")
        return names.count > 4 ? "\(shown) +\(names.count - 4)" : shown
    }
}

/// Volumen ovog tjedna u usporedbi s prošlim.
struct WeeklyVolumeCard: View {
    let unit: WeightUnit
    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }) private var sessions: [Session]
    @Query private var customExercises: [CustomExercise]
    @State private var thisWeekKg: Double = 0
    @State private var lastWeekKg: Double = 0

    private func text(_ kg: Double) -> String {
        let value = WeightConversion.displayValue(fromKilograms: kg, in: unit, step: 1)
        return "\(value.formatted(.number.precision(.fractionLength(0)))) \(unit.symbol)"
    }

    var body: some View {
        HomeCard(title: DashboardCardKind.weeklyVolume.title, symbol: DashboardCardKind.weeklyVolume.symbol) {
            Text(text(thisWeekKg)).font(.metric)
            Text("Prošli tjedan: \(text(lastWeekKg))")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .task(id: sessions.count) { load() }
    }

    private func load() {
        let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
        let buckets = (try? StatisticsEngine(context: context).volumeBuckets(size: .week, count: 2, info: info)) ?? []
        thisWeekKg = buckets.last?.totalVolumeKg ?? 0
        lastWeekKg = buckets.dropLast().last?.totalVolumeKg ?? 0
    }
}

/// Dodavanje, uklanjanje i premještanje kartica.
struct DashboardEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DashboardCard.orderIndex) private var stored: [DashboardCard]
    @State private var errorText: String?

    private var layout: DashboardLayout { DashboardLayout(context: context) }
    private var shown: [DashboardCard] {
        _ = stored.map(\.orderIndex)
        return (try? layout.cards()) ?? []
    }
    private var available: [DashboardCardKind] {
        _ = stored.count
        return (try? layout.availableKinds()) ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown) { card in
                        if let kind = card.kind {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                    .onMove { offsets, destination in
                        perform { try layout.move(fromOffsets: offsets, toOffset: destination) }
                    }
                    .onDelete { offsets in
                        let cards = shown
                        perform { for index in offsets { try layout.remove(cards[index]) } }
                    }
                } header: {
                    Text("Na Početnoj")
                } footer: {
                    if shown.isEmpty { Text("Nema kartica. Dodaj ih ispod.") }
                }
                if !available.isEmpty {
                    Section("Dodaj") {
                        ForEach(available, id: \.self) { kind in
                            Button {
                                perform { try layout.add(kind) }
                            } label: {
                                Label(kind.title, systemImage: "plus.circle.fill")
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Kartice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
            .errorAlert($errorText)
        }
    }

    private func perform<T>(_ change: () throws -> T) {
        do { _ = try change() } catch { errorText = String(localized: "Promjena se nije mogla spremiti.") }
    }
}
