import SwiftUI
import Units
import WidgetData
import WidgetKit

/// Vremenska crta za komplikacije tjednog cilja i težine: podatke s iPhonea sprema aplikacija na satu
/// (`ComplicationState`), a zapis za svaku iduću ponoć prazni tjedan kad počne novi.
struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        let sample = WidgetSnapshot.sample()
        return ComplicationEntry(date: Date(), state: ComplicationState(
            nextWorkoutName: "Push", week: sample.week, bodyWeightKg: sample.bodyWeight?.latestKg, weightUnit: .kilograms
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ComplicationEntry(date: Date(), state: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        let state = ComplicationState.load()
        let dates = [now] + WidgetDates.nextMidnights(after: now, count: 7)
        completion(Timeline(entries: dates.map { ComplicationEntry(date: $0, state: state) }, policy: .atEnd))
    }
}

/// Tjedni cilj: krug "2/3" (prijedlog za sat, modularni i jednostavni brojčanik).
struct WeekGoalComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekGoal", provider: SummaryProvider()) { entry in
            WeekGoalView(entry: entry)
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Ovaj tjedan")
        .description("Treninzi ovog tjedna prema tvom cilju.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

private struct WeekGoalView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var week: WidgetSnapshot.Week? { entry.state.week?.current(at: entry.date) }
    private var sessions: Int { week?.sessions ?? 0 }

    /// "2/3", a bez cilja samo broj treninga.
    private var countText: String {
        guard let goal = week?.goal else { return "\(sessions)" }
        return "\(sessions)/\(goal)"
    }

    var body: some View {
        switch family {
        case .accessoryCorner:
            Text(verbatim: countText)
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: week?.goalFraction ?? 0) { Text("Ovaj tjedan") }
                }
        case .accessoryInline:
            Label {
                Text(verbatim: countText)
            } icon: {
                Image(systemName: "target")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Ovaj tjedan", systemImage: "target").font(.headline).widgetAccentable()
                Text(verbatim: countText).font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                if let weeks = week?.streakWeeks, weeks >= 2 {
                    Text("\(weeks) tjedana zaredom").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            if let fraction = week?.goalFraction {
                Gauge(value: fraction) {
                    Image(systemName: "target")
                } currentValueLabel: {
                    Text(verbatim: countText)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text(verbatim: countText).font(.title3.bold())
                        Image(systemName: "dumbbell.fill").font(.caption2)
                    }
                }
            }
        }
    }
}

/// Brzi početak: ▶ koji otvara aplikaciju na satu, spremnu za početak treninga.
struct QuickStartComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickStart", provider: SummaryProvider()) { entry in
            QuickStartView(nextWorkout: entry.state.nextWorkoutName)
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Započni trening")
        .description("Otvara Apolon za početak treninga.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

private struct QuickStartView: View {
    let nextWorkout: String?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCorner {
            Image(systemName: "play.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel {
                    Text(nextWorkout ?? String(localized: "Započni"))
                }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "play.fill")
                    .font(.title2)
                    .widgetAccentable()
            }
            .accessibilityLabel(Text("Započni trening"))
        }
    }
}

/// Tjelesna težina s iPhonea.
struct BodyWeightComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWeight", provider: SummaryProvider()) { entry in
            BodyWeightComplicationView(state: entry.state)
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Težina")
        .description("Zadnja izmjerena težina.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

private struct BodyWeightComplicationView: View {
    let state: ComplicationState
    @Environment(\.widgetFamily) private var family

    private var unit: WeightUnit { state.weightUnit ?? .kilograms }
    private var number: String? {
        state.bodyWeightKg.map { WeightFormatter(unit: unit).number(fromKilograms: $0) }
    }

    var body: some View {
        if family == .accessoryInline {
            Label {
                Text(verbatim: number.map { "\($0) \(unit.symbol)" } ?? "–")
            } icon: {
                Image(systemName: "figure.stand")
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                if let number {
                    VStack(spacing: -2) {
                        Text(verbatim: unit.symbol).font(.caption2)
                        Text(verbatim: number)
                            .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                    }
                    .padding(4)
                } else {
                    Image(systemName: "figure.stand").font(.title3)
                }
            }
        }
    }
}
