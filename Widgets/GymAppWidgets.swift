import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GymAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

/// Kostur Live Activityja za fazu 9. Tih je: samo prikaz, bez zvuka i bannera.
/// Odbrojavanje radi sustav (`Text(timerInterval:)`), pa ne treba stalna ažuriranja.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerActivityAttributes.self) { context in
            HStack {
                VStack(alignment: .leading) {
                    Text(context.state.exerciseName).font(.headline)
                    Text(context.state.setDescription).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                RestCountdown(endsAt: context.state.restEndsAt)
                    .font(.title.monospacedDigit())
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.exerciseName).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(endsAt: context.state.restEndsAt)
                        .font(.title2.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.setDescription).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                RestCountdown(endsAt: context.state.restEndsAt)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

private struct RestCountdown: View {
    let endsAt: Date?

    var body: some View {
        if let endsAt, endsAt > Date() {
            Text(timerInterval: Date()...endsAt, countsDown: true)
        } else {
            Text("—")
        }
    }
}
