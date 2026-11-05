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
        } dynamicIsland: { context in
            let state = context.state
            let rest = RestState(state: state, isStale: context.isStale)
            return DynamicIsland {
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

private struct LockScreenView: View {
    let state: RestTimerActivityAttributes.ContentState
    let workoutName: String
    let isStale: Bool

    var body: some View {
        let rest = RestState(state: state, isStale: isStale)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ExerciseLabel(state: state, showsNextExercise: true)
                Spacer(minLength: 12)
                RestCountdown(rest: rest)
                    .font(.title.bold().monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            RestProgress(rest: rest)
            NextSetRow(state: state)
        }
        .padding()
    }
}

// MARK: Dijelovi

private struct ExerciseLabel: View {
    let state: RestTimerActivityAttributes.ContentState
    /// Na zaključanom zaslonu sljedeća vježba ide uz broj serije, jer donji red zauzimaju vrijednosti serije.
    var showsNextExercise = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name = state.exerciseName {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Group {
                    if showsNextExercise, !state.setValues.isEmpty, let next = state.nextExerciseName {
                        Text("\(Text("Serija \(state.setNumber) od \(state.setCount)")) · \(Text("Sljedeće: \(next)"))")
                    } else {
                        Text("Serija \(state.setNumber) od \(state.setCount)")
                    }
                }
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
                    .accessibilityLabel(decreaseLabel)
            }
            .disabled(!value.canDecrease)

            valueText
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Button(intent: AdjustSetValueIntent(setID: setID, field: value.field, steps: 1)) {
                Image(systemName: "plus")
                    .accessibilityLabel(increaseLabel)
            }
            .disabled(!value.canIncrease)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .tint(.accentColor)
    }

    @ViewBuilder
    private var valueText: some View {
        if value.field == "reps" {
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
        case "reps": Text("Smanji ponavljanja")
        case "duration": Text("Skrati trajanje")
        case "distance": Text("Smanji udaljenost")
        default: Text("Smanji težinu")
        }
    }

    private var increaseLabel: Text {
        switch value.field {
        case "reps": Text("Povećaj ponavljanja")
        case "duration": Text("Produlji trajanje")
        case "distance": Text("Povećaj udaljenost")
        default: Text("Povećaj težinu")
        }
    }
}

/// Kvačica za sljedeću seriju. Bez upisanih vrijednosti nema gumba: vrijednosti se upisuju s + ili u aplikaciji.
/// Uz vrijednosti serije gumb je samo kvačica u krugu, da sve stane u jedan red.
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
                    Label("Potvrdi seriju", systemImage: "checkmark")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
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
