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
                    VStack(spacing: 8) {
                        RestProgress(rest: rest)
                        HStack {
                            NextExerciseLabel(state: state)
                            Spacer()
                            ConfirmSetButton(state: state)
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
                ExerciseLabel(state: state)
                Spacer(minLength: 12)
                RestCountdown(rest: rest)
                    .font(.title.bold().monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            RestProgress(rest: rest)
            HStack(alignment: .center) {
                NextExerciseLabel(state: state)
                Spacer(minLength: 12)
                ConfirmSetButton(state: state)
            }
        }
        .padding()
    }
}

// MARK: Dijelovi

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

/// Kvačica za sljedeću seriju. Bez upisanih vrijednosti nema gumba: dodir na Live Activity otvara aplikaciju.
private struct ConfirmSetButton: View {
    let state: RestTimerActivityAttributes.ContentState

    var body: some View {
        if let setID = state.nextSetID, state.canConfirm {
            Button(intent: CompleteSetIntent(setID: setID)) {
                Label("Potvrdi seriju", systemImage: "checkmark")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
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
