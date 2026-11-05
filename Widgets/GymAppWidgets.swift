import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct GymAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

/// Live Activity aktivnog treninga na zaključanom zaslonu i u Dynamic Islandu (specifikacija, odjeljak 6).
///
/// Tiha je: aplikacija je ažurira bez `AlertConfiguration`, pa nema zvuka ni bannera. Odbrojavanje radi sustav
/// (`Text(timerInterval:)` i `ProgressView(timerInterval:)`), pa ne treba ažuriranje svake sekunde. Kad odmor istekne,
/// sadržaj zastari (`staleDate` je kraj odmora) i umjesto odbrojavanja piše da je odmor gotov.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerActivityAttributes.self) { context in
            LockScreenView(state: context.state, workoutName: context.attributes.workoutName, isStale: context.isStale)
                .widgetURL(LiveActivityLink.activeWorkout)
        } dynamicIsland: { context in
            let state = context.state
            let rest = RestState(state: state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    WorkoutHeader(workoutName: context.attributes.workoutName, startedAt: state.workoutStartedAt)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.leading) {
                    ExerciseLabel(state: state)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(rest: rest)
                        .font(.title2.bold().monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        RestProgress(rest: rest)
                        NextSetRow(state: state)
                        if !state.setValues.isEmpty, let next = state.nextExerciseName {
                            Text("Sljedeće: \(next)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .accessibilityLabel(Text("Trening"))
            } compactTrailing: {
                CompactTrailing(state: state, rest: rest)
            } minimal: {
                if case let .running(start, end) = rest {
                    ProgressView(timerInterval: start...end, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: "timer")
                    }
                    .progressViewStyle(.circular)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .accessibilityLabel(Text("Trening"))
                }
            }
            .widgetURL(LiveActivityLink.activeWorkout)
            .keylineTint(.accentColor)
        }
    }
}

// MARK: Stanje odmora

private enum RestState {
    case none
    case running(start: Date, end: Date)
    case finished

    init(state: RestTimerActivityAttributes.ContentState, isStale: Bool) {
        guard let end = state.restEndsAt else {
            self = .none
            return
        }
        let start = min(state.restStartedAt ?? end, end)
        self = (isStale || end <= Date()) ? .finished : .running(start: start, end: end)
    }
}

// MARK: Zaključani zaslon

/// Raspored na zaključanom zaslonu. Visina je ograničena na 160 pt, pa je sve u četiri dijela:
/// trajanje treninga, traka odmora preko cijele širine, puni naziv vježbe s kvačicom te težina i ponavljanja
/// jedno ispod drugog. Sljedeća vježba ovdje ne stane; vidi se u proširenom Dynamic Islandu.
private struct LockScreenView: View {
    let state: RestTimerActivityAttributes.ContentState
    let workoutName: String
    let isStale: Bool

    var body: some View {
        let rest = RestState(state: state, isStale: isStale)
        // 20 (gornji red) + 28 (odmor) + 78 (vrijednosti) + razmaci i rubovi = oko 154 pt.
        VStack(alignment: .leading, spacing: 6) {
            LockScreenHeader(state: state, workoutName: workoutName)
            RestBar(rest: rest)
            if let setID = state.nextSetID, let name = state.exerciseName, !state.setValues.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        ConfirmSetButton(state: state, isCompact: false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    VStack(spacing: 6) {
                        ForEach(state.setValues, id: \.field) { value in
                            LargeSetValueStepper(setID: setID, value: value)
                        }
                    }
                    .frame(width: 178)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ExerciseLabel(state: state)
                NextExerciseLabel(state: state)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Gornji red: trajanje treninga (sustav ga sam odbrojava prema gore), naziv treninga i broj serije.
private struct LockScreenHeader: View {
    let state: RestTimerActivityAttributes.ContentState
    let workoutName: String

    var body: some View {
        HStack(spacing: 6) {
            if let startedAt = state.workoutStartedAt {
                Image(systemName: "stopwatch")
                    .foregroundStyle(.secondary)
                Text(startedAt, style: .timer)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    // Tekst koji odbrojava inače zauzme svu širinu.
                    .frame(maxWidth: 64, alignment: .leading)
                    .accessibilityLabel(Text("Trajanje treninga"))
            }
            Text(verbatim: workoutName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if state.exerciseName != nil {
                Text("Serija \(state.setNumber) od \(state.setCount)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.subheadline)
    }
}

/// Odmor u jednoj traci preko cijele širine: traka se prazni kako vrijeme teče (kao na ekranu treninga),
/// a preostalo vrijeme piše u njoj. Bez odmora trake nema.
private struct RestBar: View {
    let rest: RestState

    private static let height: CGFloat = 28

    var body: some View {
        switch rest {
        case let .running(start, end):
            ZStack {
                // Sustavska traka s vremenskim intervalom teče sama, bez ažuriranja Live Activityja.
                ProgressView(timerInterval: start...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(Color.accentColor.opacity(0.7))
                .scaleEffect(x: 1, y: Self.height / 4, anchor: .center)
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text("Odmor")
                    Spacer(minLength: 6)
                    Text(timerInterval: start...end, countsDown: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70, alignment: .trailing)
                        .accessibilityLabel(Text("Preostali odmor"))
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 10)
            }
            .frame(height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        case .finished:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Odmor gotov")
                Spacer(minLength: 0)
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 10)
            .frame(height: Self.height)
            .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        case .none:
            EmptyView()
        }
    }
}

/// Težina ili ponavljanja u zaobljenom kvadratu, s velikim gumbima − i + sa strane.
private struct LargeSetValueStepper: View {
    let setID: String
    let value: RestTimerActivityAttributes.SetValue

    var body: some View {
        HStack(spacing: 4) {
            Button(intent: AdjustSetValueIntent(setID: setID, field: value.field, steps: -1)) {
                StepperSymbol(systemName: "minus")
                    .accessibilityLabel(value.decreaseLabel)
            }
            .buttonStyle(.plain)
            .disabled(!value.canDecrease)
            .opacity(value.canDecrease ? 1 : 0.4)

            value.valueText
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            Button(intent: AdjustSetValueIntent(setID: setID, field: value.field, steps: 1)) {
                StepperSymbol(systemName: "plus")
                    .accessibilityLabel(value.increaseLabel)
            }
            .buttonStyle(.plain)
            .disabled(!value.canIncrease)
            .opacity(value.canIncrease ? 1 : 0.4)
        }
        .padding(3)
        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StepperSymbol: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.body.bold())
            .foregroundStyle(Color.accentColor)
            .frame(width: 40, height: 30)
            .background(Color.accentColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: Dijelovi

/// Naziv treninga i trajanje od početka (sustav ga sam odbrojava prema gore).
private struct WorkoutHeader: View {
    let workoutName: String
    let startedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            Label(workoutName, systemImage: "dumbbell.fill")
                .fontWeight(.semibold)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let startedAt {
                Text(startedAt, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    // Tekst s odbrojavanjem inače zauzme svu širinu i potisne naziv.
                    .frame(maxWidth: 72, alignment: .trailing)
                    .accessibilityLabel(Text("Trajanje treninga"))
            }
        }
    }
}

private struct ExerciseLabel: View {
    let state: RestTimerActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name = state.exerciseName {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Text("Serija \(state.setNumber) od \(state.setCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("Sve serije su gotove")
                    .font(.headline)
                Text("\(state.completedSets) od \(state.totalSets) serija")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NextExerciseLabel: View {
    let state: RestTimerActivityAttributes.ContentState

    var body: some View {
        Group {
            if let next = state.nextExerciseName {
                Text("Sljedeće: \(next)")
            } else if state.exerciseName != nil {
                Text("\(state.completedSets) od \(state.totalSets) serija")
            } else {
                Text("Završi trening u aplikaciji")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct RestCountdown: View {
    let rest: RestState

    var body: some View {
        switch rest {
        case let .running(start, end):
            Text(timerInterval: start...end, countsDown: true)
                .accessibilityLabel(Text("Preostali odmor"))
        case .finished:
            Text("Odmor gotov")
                .font(.headline)
        case .none:
            EmptyView()
        }
    }
}

private struct RestProgress: View {
    let rest: RestState

    var body: some View {
        if case let .running(start, end) = rest {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.accentColor)
        }
    }
}

/// Donji red: vrijednosti sljedeće serije s gumbima − i + te kvačica koja je potvrđuje.
/// Kad serije nema (sve je gotovo), umjesto vrijednosti piše stanje treninga.
private struct NextSetRow: View {
    let state: RestTimerActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let setID = state.nextSetID, !state.setValues.isEmpty {
                ForEach(state.setValues, id: \.field) { value in
                    SetValueStepper(setID: setID, value: value)
                }
                Spacer(minLength: 0)
                ConfirmSetButton(state: state, isCompact: true)
            } else {
                NextExerciseLabel(state: state)
                Spacer(minLength: 12)
                ConfirmSetButton(state: state, isCompact: false)
            }
        }
    }
}

/// Vrijednost serije između gumba − i +. Jedan dodir je jedan korak (kao klik Digital Crowna na satu).
private struct SetValueStepper: View {
    let setID: String
    let value: RestTimerActivityAttributes.SetValue

    var body: some View {
        HStack(spacing: 6) {
            Button(intent: AdjustSetValueIntent(setID: setID, field: value.field, steps: -1)) {
                Image(systemName: "minus")
                    .accessibilityLabel(value.decreaseLabel)
            }
            .disabled(!value.canDecrease)

            value.valueText
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Button(intent: AdjustSetValueIntent(setID: setID, field: value.field, steps: 1)) {
                Image(systemName: "plus")
                    .accessibilityLabel(value.increaseLabel)
            }
            .disabled(!value.canIncrease)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .tint(.accentColor)
    }
}

/// Tekst vrijednosti i opisi gumba za VoiceOver, zajednički za Dynamic Island i zaključani zaslon.
private extension RestTimerActivityAttributes.SetValue {
    @ViewBuilder
    var valueText: some View {
        if field == "reps" {
            if let reps = Int(text) {
                Text("\(reps) pon.")
            } else {
                Text("– pon.")
            }
        } else if unitSymbol.isEmpty {
            Text(verbatim: text)
        } else {
            Text(verbatim: "\(text) \(unitSymbol)")
        }
    }

    var decreaseLabel: Text {
        switch field {
        case "reps": Text("Smanji ponavljanja")
        case "duration": Text("Skrati trajanje")
        case "distance": Text("Smanji udaljenost")
        default: Text("Smanji težinu")
        }
    }

    var increaseLabel: Text {
        switch field {
        case "reps": Text("Povećaj ponavljanja")
        case "duration": Text("Produlji trajanje")
        case "distance": Text("Povećaj udaljenost")
        default: Text("Povećaj težinu")
        }
    }
}

/// Kvačica za sljedeću seriju. Bez upisanih vrijednosti nema gumba: vrijednosti se upisuju s + ili u aplikaciji.
/// U Dynamic Islandu je uz vrijednosti serije samo kvačica u krugu, da sve stane u jedan red.
/// Inače je široki gumb sa zaobljenim kutovima.
private struct ConfirmSetButton: View {
    let state: RestTimerActivityAttributes.ContentState
    let isCompact: Bool

    var body: some View {
        if let setID = state.nextSetID, state.canConfirm {
            if isCompact {
                Button(intent: CompleteSetIntent(setID: setID)) {
                    Label("Potvrdi seriju", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.headline.bold())
                        .padding(4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(.accentColor)
            } else {
                Button(intent: CompleteSetIntent(setID: setID)) {
                    // Vlastita pozadina umjesto `.borderedProminent`: točna visina, da sve stane u 160 pt.
                    Label("Potvrdi seriju", systemImage: "checkmark")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CompactTrailing: View {
    let state: RestTimerActivityAttributes.ContentState
    let rest: RestState

    var body: some View {
        switch rest {
        case let .running(start, end):
            Text(timerInterval: start...end, countsDown: true)
                .monospacedDigit()
                .frame(maxWidth: 44)
        default:
            if state.exerciseName != nil {
                Text("\(state.setNumber)/\(state.setCount)")
                    .monospacedDigit()
                    .accessibilityLabel(Text("Serija \(state.setNumber) od \(state.setCount)"))
            } else {
                Image(systemName: "checkmark")
                    .accessibilityLabel(Text("Sve serije su gotove"))
            }
        }
    }
}
