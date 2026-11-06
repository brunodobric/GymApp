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
            LockScreenView(state: context.state, isStale: context.isStale)
                .lockScreenAppearance(context.state)
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
                        .font(.metric)
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
                    .environment(\.activityAccent, state.accentColor)
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
                    .tint(state.accentColor)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .accessibilityLabel(Text("Trening"))
                }
            }
            .widgetURL(LiveActivityLink.activeWorkout)
            .keylineTint(state.accentColor)
        }
    }
}

// MARK: Tema

private extension View {
    /// Na zaključanom zaslonu: vlastita pozadina i shema boja kad tema nije "Sustav".
    /// Dynamic Island je uvijek crn, pa se ondje primjenjuje samo naglasna boja.
    @ViewBuilder
    func lockScreenAppearance(_ state: RestTimerActivityAttributes.ContentState) -> some View {
        let accented = environment(\.activityAccent, state.accentColor)
        switch state.colorScheme {
        case .some(.light):
            accented
                .environment(\.colorScheme, .light)
                .activityBackgroundTint(Color.white.opacity(0.9))
                .activitySystemActionForegroundColor(.black)
        case .some(.dark):
            accented
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        default:
            accented
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

/// Raspored na zaključanom zaslonu (visina je ograničena na 160 pt):
/// * gore lijevo trajanje treninga, u sredini naziv vježbe, desno broj serije;
/// * ispod lijevo ista serija u prethodnom treningu, u sredini težina i ponavljanja s − i +,
///   desno zelena kvačica, a za vrijeme odmora umjesto nje odbrojavanje.
///
/// Cijela pozadina je traka odmora: obojeni dio se smanjuje kako odmor teče i nestane kad završi.
private struct LockScreenView: View {
    let state: RestTimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let rest = RestState(state: state, isStale: isStale)
        // Fiksna visina (ispod granice od 160 pt) da dva jednaka razmaka smjeste donji dio točno između
        // naslova i donjeg ruba.
        VStack(spacing: 0) {
            LockScreenHeader(state: state)
            Spacer(minLength: 8)
            if let setID = state.nextSetID, !state.setValues.isEmpty {
                HStack(spacing: 8) {
                    PreviousSetLabel(text: state.previousText)
                        .frame(width: 66, alignment: .leading)
                    VStack(spacing: 6) {
                        ForEach(state.setValues, id: \.field) { value in
                            LargeSetValueStepper(setID: setID, value: value)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    ConfirmOrRest(state: state, rest: rest)
                        .frame(width: 64)
                }
                .frame(height: 78)
            } else {
                HStack {
                    NextExerciseLabel(state: state)
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(height: 156)
        .background {
            RestBackground(rest: rest)
        }
        .clipped()
    }
}

/// Gornji red: trajanje treninga lijevo, naziv vježbe u sredini (do dva reda), broj serije desno.
private struct LockScreenHeader: View {
    let state: RestTimerActivityAttributes.ContentState

    private static let sideWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let startedAt = state.workoutStartedAt {
                    Text(startedAt, style: .timer)
                        .monospacedDigit()
                        .accessibilityLabel(Text("Trajanje treninga"))
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.sideWidth, alignment: .leading)

            Group {
                if let name = state.exerciseName {
                    Text(name)
                } else {
                    Text("Sve serije su gotove")
                }
            }
            .font(.itemTitle)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)

            Group {
                if state.exerciseName != nil {
                    Text("\(state.setNumber)/\(state.setCount)")
                        .accessibilityLabel(Text("Serija \(state.setNumber) od \(state.setCount)"))
                } else {
                    Text("\(state.completedSets)/\(state.totalSets)")
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: Self.sideWidth, alignment: .trailing)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Ista serija u prethodnom treningu, kao na ekranu treninga.
private struct PreviousSetLabel: View {
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let text {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                Text(verbatim: text)
                    .font(.rowValueSmall)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.map { Text("Prošli put \($0)") } ?? Text(verbatim: ""))
    }
}

/// Desno: velika zelena kvačica (kao na ekranu treninga), a za vrijeme odmora iznad nje odbrojavanje.
///
/// Kvačica je tu i za vrijeme odmora jer Live Activity ne može sama sebe promijeniti točno kad odmor istekne:
/// bez aplikacije u prvom planu (ili poslužitelja za push) sustav je iscrta ponovno tek kad mu odgovara, pa bi
/// do tada stajalo "0:00" bez gumba. Kad je iscrta ponovno (`staleDate`), ostaje samo velika kvačica.
private struct ConfirmOrRest: View {
    let state: RestTimerActivityAttributes.ContentState
    let rest: RestState

    var body: some View {
        VStack(spacing: 4) {
            if case let .running(start, end) = rest {
                Text(timerInterval: start...end, countsDown: true)
                    .font(.itemTitle.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("Preostali odmor"))
            }
            if let setID = state.nextSetID, state.canConfirm {
                Button(intent: CompleteSetIntent(setID: setID)) {
                    GreenCheckmark()
                }
                .buttonStyle(.plain)
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

private struct GreenCheckmark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.title.weight(.bold))
            .foregroundStyle(Color.green)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(Text("Potvrdi seriju"))
    }
}

/// Pozadina kao traka odmora: obojeni dio se prazni s desna na lijevo dok odmor teče.
/// Sustavska traka s vremenskim intervalom teče sama, bez ažuriranja Live Activityja; razvučena je preko
/// cijele visine, a Live Activity je obrezuje na svoj oblik.
private struct RestBackground: View {
    let rest: RestState

    @Environment(\.activityAccent) private var accent

    var body: some View {
        if case let .running(start, end) = rest {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(accent.opacity(0.35))
            .scaleEffect(x: 1, y: 60, anchor: .center)
            .accessibilityHidden(true)
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
                .font(.metricSmall)
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

    @Environment(\.activityAccent) private var accent

    var body: some View {
        Image(systemName: systemName)
            .font(.body.bold())
            .foregroundStyle(accent)
            .frame(width: 38, height: 30)
            .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                .fontDesign(.rounded)
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
                    .font(.itemTitle)
                    .lineLimit(1)
                Text("Serija \(state.setNumber) od \(state.setCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("Sve serije su gotove")
                    .font(.itemTitle)
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
                .font(.itemTitle)
        case .none:
            EmptyView()
        }
    }
}

private struct RestProgress: View {
    let rest: RestState

    @Environment(\.activityAccent) private var accent

    var body: some View {
        if case let .running(start, end) = rest {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(accent)
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

    @Environment(\.activityAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            Button(intent: AdjustSetValueIntent(setID: setID, field: value.field, steps: -1)) {
                Image(systemName: "minus")
                    .accessibilityLabel(value.decreaseLabel)
            }
            .disabled(!value.canDecrease)

            value.valueText
                .font(.itemTitle.monospacedDigit())
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
        .tint(accent)
    }
}

/// Kvačica za sljedeću seriju. Bez upisanih vrijednosti nema gumba: vrijednosti se upisuju s + ili u aplikaciji.
/// U Dynamic Islandu je uz vrijednosti serije samo kvačica u krugu, da sve stane u jedan red.
/// Inače je široki gumb sa zaobljenim kutovima.
private struct ConfirmSetButton: View {
    let state: RestTimerActivityAttributes.ContentState
    let isCompact: Bool

    @Environment(\.activityAccent) private var accent

    var body: some View {
        if let setID = state.nextSetID, state.canConfirm {
            if isCompact {
                Button(intent: CompleteSetIntent(setID: setID)) {
                    Label("Potvrdi seriju", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.headline.bold())
                        .foregroundStyle(Color.green)
                        .frame(width: 44, height: 36)
                        .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: CompleteSetIntent(setID: setID)) {
                    // Vlastita pozadina umjesto `.borderedProminent`: točna visina, da sve stane u 160 pt.
                    Label("Potvrdi seriju", systemImage: "checkmark")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .fontDesign(.rounded)
                .frame(maxWidth: 44)
        default:
            if state.exerciseName != nil {
                Text("\(state.setNumber)/\(state.setCount)")
                    .monospacedDigit()
                    .fontDesign(.rounded)
                    .accessibilityLabel(Text("Serija \(state.setNumber) od \(state.setCount)"))
            } else {
                Image(systemName: "checkmark")
                    .accessibilityLabel(Text("Sve serije su gotove"))
            }
        }
    }
}
