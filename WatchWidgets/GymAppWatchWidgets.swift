import SwiftUI
import WidgetKit

@main
struct GymAppWatchWidgets: WidgetBundle {
    var body: some Widget {
        GymComplication()
    }
}

/// Complication: aktivni odmor s odbrojavanjem, trening u tijeku ili sljedeći trening.
struct GymComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Apollo")
        .description("Sljedeći trening i odmor između serija.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let state: ComplicationState
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), state: ComplicationState(nextWorkoutName: "Push", nextScheduleName: "PPL"))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ComplicationEntry(date: Date(), state: .load()))
    }

    /// Odbrojavanje radi sustav (`Text(timerInterval:)`). Novi zapis treba samo za kraj odmora;
    /// ostalo osvježava aplikacija kad se stanje promijeni.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        let state = ComplicationState.load()
        var entries = [ComplicationEntry(date: now, state: state)]
        if let end = state.restEndsAt, end > now {
            var after = state
            after.restStartedAt = nil
            after.restEndsAt = nil
            entries.append(ComplicationEntry(date: end, state: after))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct ComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var state: ComplicationState { entry.state }
    private var rest: ClosedRange<Date>? {
        guard state.isResting(at: entry.date), let end = state.restEndsAt else { return nil }
        return min(state.restStartedAt ?? entry.date, end)...end
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: corner
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let rest {
            ProgressView(timerInterval: rest, countsDown: true) {
                Image(systemName: "timer")
            } currentValueLabel: {
                Text(timerInterval: rest, countsDown: true).monospacedDigit()
            }
            .progressViewStyle(.circular)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "dumbbell.fill").font(.title3)
            }
            .accessibilityLabel(Text(state.activeWorkoutName ?? state.nextWorkoutName ?? "Apollo"))
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let rest {
                Label("Odmor", systemImage: "timer").font(.headline).widgetAccentable()
                Text(timerInterval: rest, countsDown: true)
                    .font(.title2.monospacedDigit())
            } else if let active = state.activeWorkoutName {
                Label("Trening u tijeku", systemImage: "dumbbell.fill").font(.headline).widgetAccentable()
                Text(active).lineLimit(1)
            } else if let next = state.nextWorkoutName {
                Label("Sljedeći trening", systemImage: "dumbbell.fill").font(.headline).widgetAccentable()
                Text(next).lineLimit(1)
                if let schedule = state.nextScheduleName {
                    Text(schedule).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Label("Apollo", systemImage: "dumbbell.fill").font(.headline).widgetAccentable()
                Text("Nema zakazanog treninga").foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inline: some View {
        if let rest {
            Label {
                Text(timerInterval: rest, countsDown: true)
            } icon: {
                Image(systemName: "timer")
            }
        } else if let name = state.activeWorkoutName ?? state.nextWorkoutName {
            Label(name, systemImage: "dumbbell.fill")
        } else {
            Label("Apollo", systemImage: "dumbbell.fill")
        }
    }

    @ViewBuilder
    private var corner: some View {
        if let rest {
            Image(systemName: "timer")
                .font(.title3)
                .widgetLabel {
                    Text(timerInterval: rest, countsDown: true)
                }
        } else {
            Image(systemName: "dumbbell.fill")
                .font(.title3)
                .widgetLabel {
                    Text(state.activeWorkoutName ?? state.nextWorkoutName ?? "Apollo")
                }
        }
    }
}
