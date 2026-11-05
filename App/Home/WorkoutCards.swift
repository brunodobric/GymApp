import Connectivity
import Models
import Planning
import SwiftUI
import Training
import Units

/// Kartica za početak treninga na vrhu Početne, istog oblika kao kartice ispod nje.
/// Svaki red je jedan način početka: sljedeći trening svakog rasporeda (kardio se otvara kao uputa za sat)
/// i prazan trening.
struct StartWorkoutCard: View {
    let planned: [PlannedWorkout]
    let onStart: (PlannedWorkout) -> Void
    let onStartEmpty: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(planned, id: \.item.id) { workout in
                Button { onStart(workout) } label: {
                    if workout.template.kind == .cardio {
                        StartRow(symbol: "applewatch", isProminent: true, subtitle: workout.schedule.name) {
                            Text("Na satu: \(workout.template.name)")
                        }
                    } else {
                        StartRow(symbol: "play.fill", isProminent: true, subtitle: workout.schedule.name) {
                            Text("Započni: \(workout.template.name)")
                        }
                    }
                }
                .accessibilityIdentifier("home.startPlanned")
                Divider().padding(.leading, 68)
            }
            Button(action: onStartEmpty) {
                if planned.isEmpty {
                    StartRow(symbol: "play.fill", isProminent: true, subtitle: nil) { Text("Započni trening") }
                } else {
                    StartRow(symbol: "plus", isProminent: false, subtitle: nil) { Text("Prazan trening") }
                }
            }
            .accessibilityIdentifier("home.startEmpty")
        }
        .buttonStyle(CardRowButtonStyle())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .workoutCardBackground()
    }
}

/// Red kartice za početak: ikona u krugu, naslov i (po potrebi) raspored.
private struct StartRow<Title: View>: View {
    let symbol: String
    let isProminent: Bool
    let subtitle: String?
    @ViewBuilder var title: Title

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .frame(width: 40, height: 40)
                .background(isProminent ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.15)), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(isProminent ? .title3.bold() : .headline)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// Pozadina kartice treninga: ista podloga kao ostale kartice, preko nje lagani poluprozirni sjaj u boji akcenta
/// (jači gore lijevo, slabiji dolje desno) i tanki rub, da se kartica istakne među ostalima.
private struct WorkoutCardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        // U tamnom načinu akcent na tamnoj podlozi treba malo više boje da se jednako vidi.
        let strength = colorScheme == .dark ? 1.4 : 1.0
        content
            .background {
                shape
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        // `.tint` je akcent iz postavki (RootView ga postavlja), a ne AccentColor iz asseta.
                        shape
                            .fill(.tint.opacity(0.22 * strength))
                            .mask(LinearGradient(colors: [.white, .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        shape.strokeBorder(.tint.opacity(0.3), lineWidth: 1)
                    }
            }
    }
}

private extension View {
    func workoutCardBackground() -> some View {
        modifier(WorkoutCardBackground())
    }
}

/// Red kartice koji se pri dodiru zatamni, kao red u popisu.
private struct CardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemFill) : .clear)
    }
}

/// Trening u tijeku sažet u karticu na Početnoj, s istim sadržajem kao Live Activity: vježba i serija,
/// odbrojavanje odmora, vrijednosti sljedeće serije s gumbima − i + te kvačica za potvrdu.
///
/// Gumbi rade isto što i gumbi u Live Activityju (`LiveActivityActions`), pa se promjena sprema, šalje satu
/// i prikazuje na zaključanom zaslonu. Dodir izvan gumba otvara cijeli ekran treninga, a povlačenje tog ekrana
/// prema dolje sažima ga natrag u karticu (zoom prijelaz u `HomeScreen`).
struct ActiveWorkoutCard: View {
    let session: Session
    let unit: WeightUnit
    let onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @State private var restFinished = false
    @State private var confirmedCount = 0

    var body: some View {
        let engine = WorkoutEngine(context: context)
        let status = liveStatus(engine)
        let values = engine.nextSet(in: session).flatMap { set in
            set.exercise.map { LiveSetEditor.values(of: set, inputType: $0.inputType, unit: unit) }
        } ?? []

        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top) {
                exerciseLabel(status)
                Spacer(minLength: 12)
                restCountdown(status.rest)
                    .font(.title.bold().monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            if let rest = status.rest, !restFinished {
                ProgressView(timerInterval: rest.startedAt...rest.endsAt, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
            if let setID = status.nextSetID, !values.isEmpty {
                setRow(setID: setID, values: values, canConfirm: status.canConfirmNextSet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .workoutCardBackground()
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Nastavi trening"), onOpen)
        .accessibilityIdentifier("home.activeWorkout")
        .sensoryFeedback(.success, trigger: confirmedCount)
        .task(id: status.rest?.endsAt) { await watchRestEnd(status.rest) }
    }

    /// Promjena bilo gdje (ekran treninga, sat, Live Activity) dira `lastActivityAt`, pa se kartica osvježi.
    private func liveStatus(_ engine: WorkoutEngine) -> LiveWorkoutStatus {
        _ = session.lastActivityAt
        return engine.liveStatus(of: session)
    }

    /// Trening koji vodi sat ima ikonu sata, kao natpis na ekranu treninga.
    private var symbol: String {
        session.controllingDevice == .watch ? "applewatch" : "figure.strengthtraining.traditional"
    }

    private var header: some View {
        HStack {
            Label("Trening je u tijeku", systemImage: symbol)
                .font(.headline)
            Spacer(minLength: 8)
            Text(session.startedAt, style: .timer)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Trajanje treninga"))
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func exerciseLabel(_ status: LiveWorkoutStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name = status.currentExerciseName {
                Text(name)
                    .font(.title3.bold())
                    .lineLimit(2)
                Text("Serija \(status.setNumber) od \(status.setCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let next = status.nextExerciseName {
                    Text("Sljedeće: \(next)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if status.totalSets > 0 {
                Text("Sve serije su gotove")
                    .font(.title3.bold())
                Text("\(status.completedSets) od \(status.totalSets) serija")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(session.name)
                    .font(.title3.bold())
                Text("Dodaj vježbu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func restCountdown(_ rest: RestTimer?) -> some View {
        if let rest {
            if restFinished {
                Text("Odmor gotov").font(.headline)
            } else {
                Text(timerInterval: rest.startedAt...rest.endsAt, countsDown: true)
                    .accessibilityLabel(Text("Preostali odmor"))
            }
        }
    }

    /// Vrijednosti serije i kvačica u jednom redu, a uz veliki tekst jedna ispod druge.
    private func setRow(setID: UUID, values: [LiveSetValue], canConfirm: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                steppers(setID: setID, values: values)
                Spacer(minLength: 0)
                confirmButton(setID: setID, canConfirm: canConfirm)
            }
            VStack(alignment: .leading, spacing: 10) {
                steppers(setID: setID, values: values)
                confirmButton(setID: setID, canConfirm: canConfirm)
            }
        }
    }

    private func steppers(setID: UUID, values: [LiveSetValue]) -> some View {
        ForEach(values, id: \.field) { value in
            SetValueStepper(value: value) { steps in
                Task { await LiveActivityActions.adjustSet(id: setID.uuidString, field: value.field.rawValue, steps: steps) }
            }
        }
    }

    /// Kao u Live Activityju: bez upisanih vrijednosti nema kvačice, vrijednosti se upisuju s + ili na ekranu treninga.
    @ViewBuilder
    private func confirmButton(setID: UUID, canConfirm: Bool) -> some View {
        if canConfirm {
            Button {
                confirmedCount += 1
                Task { await LiveActivityActions.completeSet(id: setID.uuidString) }
            } label: {
                Label("Potvrdi seriju", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .font(.title3.bold())
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
        }
    }

    /// Kad odmor istekne, umjesto odbrojavanja piše "Odmor gotov" (kao u Live Activityju).
    private func watchRestEnd(_ rest: RestTimer?) async {
        guard let rest else {
            restFinished = false
            return
        }
        let remaining = rest.endsAt.timeIntervalSinceNow
        restFinished = remaining <= 0
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
        if !Task.isCancelled { restFinished = true }
    }
}

/// Vrijednost serije između gumba − i +. Jedan dodir je jedan korak, isti kao u Live Activityju.
private struct SetValueStepper: View {
    let value: LiveSetValue
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button { onStep(-1) } label: {
                Image(systemName: "minus")
                    .accessibilityLabel(decreaseLabel)
            }
            .disabled(!value.canDecrease)

            valueText
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .contentTransition(.numericText())

            Button { onStep(1) } label: {
                Image(systemName: "plus")
                    .accessibilityLabel(increaseLabel)
            }
            .disabled(!value.canIncrease)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    @ViewBuilder
    private var valueText: some View {
        if value.field == .reps {
            if let reps = Int(value.text) {
                Text("\(reps) pon.")
            } else {
                Text("– pon.")
            }
        } else if value.unitSymbol.isEmpty {
            Text(verbatim: value.text)
        } else {
            Text(verbatim: "\(value.text) \(value.unitSymbol)")
        }
    }

    private var decreaseLabel: Text {
        switch value.field {
        case .reps: Text("Smanji ponavljanja")
        case .duration: Text("Skrati trajanje")
        case .distance: Text("Smanji udaljenost")
        case .weight, .extraWeight: Text("Smanji težinu")
        }
    }

    private var increaseLabel: Text {
        switch value.field {
        case .reps: Text("Povećaj ponavljanja")
        case .duration: Text("Produlji trajanje")
        case .distance: Text("Povećaj udaljenost")
        case .weight, .extraWeight: Text("Povećaj težinu")
        }
    }
}
