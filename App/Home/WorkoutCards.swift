import Connectivity
import Models
import Planning
import SwiftUI
import Training
import Units

/// Kartica za početak treninga na vrhu Početne, istog oblika kao kartice ispod nje.
/// Svaki red je jedan način početka: sljedeći trening svakog rasporeda (kardio se otvara kao uputa za sat)
/// i prazan trening. Kad nijedan raspored ne nudi trening snage, a postoje spremljeni treninzi, prvi red
/// otvara njihov popis (`TemplatePickerSheet`).
struct StartWorkoutCard: View {
    let planned: [PlannedWorkout]
    /// Broj spremljenih treninga koji se mogu pokrenuti bez rasporeda (`TemplateStarter.startable`).
    let templateCount: Int
    let onStart: (PlannedWorkout) -> Void
    let onChooseTemplate: () -> Void
    let onStartEmpty: () -> Void

    /// Red za izbor spremljenog treninga, samo kad raspored ne nudi trening snage.
    private var offersTemplates: Bool {
        templateCount > 0 && !planned.contains { $0.template.kind != .cardio }
    }

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
            if offersTemplates {
                Button(action: onChooseTemplate) {
                    StartRow(symbol: "list.bullet", isProminent: true, subtitle: String(localized: "\(templateCount) spremljenih treninga")) {
                        Text("Odaberi trening")
                    }
                }
                .accessibilityIdentifier("home.chooseTemplate")
                Divider().padding(.leading, 68)
            }
            Button(action: onStartEmpty) {
                if planned.isEmpty && !offersTemplates {
                    StartRow(symbol: "play.fill", isProminent: true, subtitle: nil) { Text("Započni trening") }
                } else {
                    StartRow(symbol: "plus", isProminent: false, subtitle: nil) { Text("Prazan trening") }
                }
            }
            .accessibilityIdentifier("home.startEmpty")
        }
        .buttonStyle(CardRowButtonStyle())
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
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
                    .font(isProminent ? .cardTitle : .itemTitle)
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
/// Za vrijeme odmora traka odmora leži odmah na podlozi i sjaju, ispod ruba i svih elemenata kartice.
private struct WorkoutCardBackground: ViewModifier {
    var rest: RestTimer?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.card)
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
                        if let rest {
                            RestDrainBackground(rest: rest)
                                .clipShape(shape)
                        }
                    }
                    .overlay {
                        shape.strokeBorder(.tint.opacity(0.3), lineWidth: 1)
                    }
            }
    }
}

private extension View {
    func workoutCardBackground(rest: RestTimer? = nil) -> some View {
        modifier(WorkoutCardBackground(rest: rest))
    }
}

/// Red kartice koji se pri dodiru zatamni, kao red u popisu.
private struct CardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemFill) : .clear)
    }
}

/// Trening u tijeku sažet u karticu na Početnoj, s istim rasporedom kao Live Activity:
/// * gore lijevo trajanje treninga, u sredini naziv vježbe, desno broj serije (npr. "2/3");
/// * ispod lijevo ista serija u prethodnom treningu, u sredini težina i ponavljanja s − i +,
///   desno velika zelena kvačica, a za vrijeme odmora umjesto nje odbrojavanje;
/// * cijela pozadina je traka odmora koja se prazni kako odmor teče.
///
/// Za razliku od Live Activityja, aplikacija zna točan trenutak kraja odmora, pa kvačica iskoči odmah na 0:00.
/// Gumbi rade isto što i gumbi u Live Activityju (`LiveActivityActions`), pa se promjena sprema, šalje satu
/// i prikazuje na zaključanom zaslonu. Dodir izvan gumba otvara cijeli ekran treninga, a povlačenje tog ekrana
/// prema dolje sažima ga natrag u karticu (zoom prijelaz u `HomeScreen`).
struct ActiveWorkoutCard: View {
    let session: Session
    let unit: WeightUnit
    let onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var restFinished = false
    @State private var confirmedCount = 0
    /// Završene serije prošlog izvođenja vježbe sljedeće serije. Učitavaju se jednom po vježbi,
    /// a ne pri svakom iscrtavanju kartice (iscrtava se pri svakoj izmjeni treninga).
    @State private var previous: (exerciseID: UUID, values: [SetValues])?

    var body: some View {
        let engine = WorkoutEngine(context: context)
        let status = liveStatus(engine)
        let next = engine.nextSet(in: session)
        let values = next.flatMap { set in
            set.exercise.map { LiveSetEditor.values(of: set, inputType: $0.inputType, unit: unit).map(\.activityValue) }
        } ?? []
        let rest = restFinished ? nil : status.rest
        let nextExercise = next?.exercise

        VStack(spacing: 12) {
            header(status)
            if let setID = status.nextSetID, !values.isEmpty {
                setRow(setID: setID, values: values, previous: next.flatMap(previousText), canConfirm: status.canConfirmNextSet, rest: rest)
            } else {
                Group {
                    if status.totalSets > 0 {
                        Text("\(status.completedSets) od \(status.totalSets) serija")
                    } else {
                        Text("Dodaj vježbu")
                    }
                }
                .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .workoutCardBackground(rest: rest)
        .contentShape(.rect(cornerRadius: CornerRadius.card))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Nastavi trening"), onOpen)
        .accessibilityIdentifier("home.activeWorkout")
        .sensoryFeedback(.success, trigger: confirmedCount)
        .animation(.default, value: restFinished)
        .task(id: status.rest?.endsAt) { await watchRestEnd(status.rest) }
        .task(id: nextExercise?.id) { loadPrevious(of: nextExercise) }
    }

    /// Promjena bilo gdje (ekran treninga, sat, Live Activity) dira `lastActivityAt`, pa se kartica osvježi.
    private func liveStatus(_ engine: WorkoutEngine) -> LiveWorkoutStatus {
        _ = session.lastActivityAt
        return engine.liveStatus(of: session)
    }

    /// Ista serija u prethodnom treningu, u dva reda ("30 kg" / "12 ×").
    private func previousText(_ set: SetLog) -> String? {
        guard let exercise = set.exercise, let previous, previous.exerciseID == exercise.id else { return nil }
        return LiveSetEditor.previousText(of: set, inputType: exercise.inputType, previous: previous.values, unit: unit)
    }

    private func loadPrevious(of exercise: SessionExercise?) {
        guard let exercise else {
            previous = nil
            return
        }
        let values = (try? GymQueries(context: context).previousSetValues(of: exercise.exercise)) ?? []
        previous = (exercise.id, values)
    }

    /// Trajanje lijevo, naziv vježbe u sredini, broj serije desno. Trening koji vodi sat ima ikonu sata.
    private func header(_ status: LiveWorkoutStatus) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {
                if session.controllingDevice == .watch {
                    Image(systemName: "applewatch")
                        .accessibilityLabel(Text("Trening vodi sat"))
                }
                Text(session.startedAt, style: .timer)
                    .monospacedDigit()
                    .accessibilityLabel(Text("Trajanje treninga"))
            }
            .frame(minWidth: 64, alignment: .leading)

            Group {
                if let name = status.currentExerciseName {
                    Text(name)
                } else if status.totalSets > 0 {
                    Text("Sve serije su gotove")
                } else {
                    Text(session.name)
                }
            }
            .font(.itemTitle)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)

            Group {
                if status.currentExerciseName != nil {
                    Text("\(status.setNumber)/\(status.setCount)")
                        .accessibilityLabel(Text("Serija \(status.setNumber) od \(status.setCount)"))
                } else {
                    Text(verbatim: "")
                }
            }
            .frame(minWidth: 64, alignment: .trailing)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// Prošli trening, vrijednosti i kvačica u jednom redu, a uz veliki tekst jedno ispod drugoga.
    private func setRow(setID: UUID, values: [RestTimerActivityAttributes.SetValue], previous: String?, canConfirm: Bool, rest: RestTimer?) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    steppers(setID: setID, values: values)
                    HStack {
                        previousLabel(previous)
                        Spacer(minLength: 8)
                        confirmOrRest(setID: setID, canConfirm: canConfirm, rest: rest)
                            .frame(width: 88, height: 64)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    previousLabel(previous)
                        .frame(width: 70, alignment: .leading)
                    VStack(spacing: 6) {
                        steppers(setID: setID, values: values)
                    }
                    .frame(maxWidth: .infinity)
                    confirmOrRest(setID: setID, canConfirm: canConfirm, rest: rest)
                        .frame(width: 68)
                        .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func previousLabel(_ text: String?) -> some View {
        if let text {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                Text(verbatim: text)
                    .font(.rowValueSmall)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Prošli put \(text)"))
        } else {
            Color.clear
        }
    }

    private func steppers(setID: UUID, values: [RestTimerActivityAttributes.SetValue]) -> some View {
        ForEach(values, id: \.field) { value in
            SetValueStepper(value: value) { steps in
                Task { await LiveActivityActions.adjustSet(id: setID.uuidString, field: value.field, steps: steps) }
            }
        }
    }

    /// Za vrijeme odmora odbrojavanje, a čim istekne velika zelena kvačica (kao na ekranu treninga).
    /// Bez upisanih vrijednosti nema kvačice: vrijednosti se upisuju s + ili na ekranu treninga.
    @ViewBuilder
    private func confirmOrRest(setID: UUID, canConfirm: Bool, rest: RestTimer?) -> some View {
        if let rest {
            Text(timerInterval: rest.startedAt...rest.endsAt, countsDown: true)
                .font(.metric)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Preostali odmor"))
                .transition(.opacity)
        } else if canConfirm {
            Button {
                confirmedCount += 1
                Task { await LiveActivityActions.completeSet(id: setID.uuidString) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 52)
                    .background(Color.green.opacity(0.14), in: .rect(cornerRadius: CornerRadius.inner))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Potvrdi seriju"))
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Kad odmor istekne, odbrojavanje i obojena pozadina nestaju, a pojavi se kvačica.
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

/// Pozadina kartice kao traka odmora: obojeni dio se s desna na lijevo smanjuje kako odmor teče.
/// Iscrtava se jednom u sekundi, a između dva iscrtavanja traka klizi linearnom animacijom.
private struct RestDrainBackground: View {
    let rest: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(rest.endsAt.timeIntervalSince(rest.startedAt), 1)
            let fraction = min(max(rest.endsAt.timeIntervalSince(context.date) / total, 0), 1)
            GeometryReader { proxy in
                Rectangle()
                    .fill(.tint.opacity(0.25))
                    .frame(width: proxy.size.width * fraction)
                    .animation(.linear(duration: 1), value: fraction)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Vrijednost serije između gumba − i +. Jedan dodir je jedan korak, isti kao u Live Activityju.
private struct SetValueStepper: View {
    let value: RestTimerActivityAttributes.SetValue
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { onStep(-1) } label: {
                StepSymbol(systemName: "minus")
                    .accessibilityLabel(value.decreaseLabel)
            }
            .disabled(!value.canDecrease)

            value.valueText
                .font(.metricSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            Button { onStep(1) } label: {
                StepSymbol(systemName: "plus")
                    .accessibilityLabel(value.increaseLabel)
            }
            .disabled(!value.canIncrease)
        }
        .buttonStyle(.plain)
        .padding(3)
        .background {
            // Neprozirna podloga da traka odmora ne prosijava; boja je ista kao dosad na podlozi kartice bez trake.
            let shape = RoundedRectangle(cornerRadius: CornerRadius.inner)
            shape
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay { shape.fill(Color.primary.opacity(0.08)) }
        }
    }
}

/// Gumb − ili + u zaobljenom kvadratu, isti kao u Live Activityju.
private struct StepSymbol: View {
    let systemName: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: systemName)
            .font(.body.bold())
            .foregroundStyle(.tint)
            .frame(width: 42, height: 34)
            .background(.tint.opacity(0.18), in: .rect(cornerRadius: CornerRadius.small))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect)
    }
}
