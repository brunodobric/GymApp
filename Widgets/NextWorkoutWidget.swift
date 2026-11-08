import SwiftUI
import WidgetData
import WidgetKit

/// Sljedeći trening iz rasporeda (prijedlog 1, 6 i 8): mali i srednji widget na početnom zaslonu,
/// pravokutnik i redak iznad sata na zaključanom zaslonu. Dok trening traje, nudi njegov nastavak.
struct NextWorkoutWidget: Widget {
    static let kind = "NextWorkout"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            NextWorkoutView(entry: entry)
                .tint(entry.snapshot.accentColor)
                .containerBackground(for: .widget) { CardBackground() }
        }
        .configurationDisplayName("Sljedeći trening")
        .description("Trening koji je na redu u rasporedu, s gumbom za početak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct NextWorkoutView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
        .widgetURL(snapshot.activeWorkout != nil ? WidgetLink.activeWorkout.url : WidgetLink.home.url)
    }

    // MARK: Početni zaslon

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let active = snapshot.activeWorkout {
                WidgetHeading("Trening u tijeku", symbol: "dumbbell.fill")
                Text(active.name).font(.cardTitle).lineLimit(2)
                Spacer(minLength: 0)
                Text(active.startedAt, style: .timer)
                    .font(.metricSmall)
                    .foregroundStyle(.secondary)
            } else if let next = snapshot.nextWorkout {
                WidgetHeading("Sljedeći", symbol: "dumbbell.fill")
                Text(next.name).font(.cardTitle).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(next.exerciseCount) vježbi").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    if let schedule = next.scheduleName {
                        Text(schedule).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    StartButton()
                }
            } else {
                WidgetHeading("Apolon", symbol: "dumbbell.fill")
                Text("Nema zakazanog treninga").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    StartButton()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let active = snapshot.activeWorkout {
                WidgetHeading("Trening u tijeku", symbol: "dumbbell.fill")
                Text(active.name).font(.cardTitle).lineLimit(1)
                Text(active.startedAt, style: .timer).font(.metric).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if let next = snapshot.nextWorkout {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        WidgetHeading("Sljedeći trening", symbol: "dumbbell.fill")
                        Text(next.name).font(.cardTitle).lineLimit(1)
                        if let schedule = next.scheduleName {
                            Text(schedule).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    StartButton(size: 40)
                }
                Divider()
                exercises(next)
                Spacer(minLength: 0)
            } else {
                WidgetHeading("Apolon", symbol: "dumbbell.fill")
                Text("Nema zakazanog treninga").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    StartButton(size: 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func exercises(_ next: WidgetSnapshot.NextWorkout) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(next.exercises.enumerated()), id: \.offset) { index, exercise in
                HStack(spacing: 6) {
                    Text(exercise.name).font(.footnote).lineLimit(1)
                    let summary = exercise.summary(unit: snapshot.weightUnit)
                    if !summary.isEmpty {
                        Text(summary).font(.footnote.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if index == next.exercises.count - 1, next.remainingExercises > 0 {
                        Text(verbatim: "+\(next.remainingExercises)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Zaključani zaslon

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let active = snapshot.activeWorkout {
                Label("Trening u tijeku", systemImage: "dumbbell.fill").font(.caption.bold()).widgetAccentable()
                Text(active.name).font(.headline).lineLimit(1)
                Text(active.startedAt, style: .timer).font(.caption.monospacedDigit())
            } else if let next = snapshot.nextWorkout {
                Label("Sljedeći trening", systemImage: "dumbbell.fill").font(.caption.bold()).widgetAccentable()
                Text(next.name).font(.headline).lineLimit(1)
                Text("\(next.exerciseCount) vježbi").font(.caption)
            } else {
                Label("Apolon", systemImage: "dumbbell.fill").font(.caption.bold()).widgetAccentable()
                Text("Nema zakazanog treninga").font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Jedan redak uz datum: sljedeći trening i tjedni cilj, npr. "Push · 2/3".
    private var inline: some View {
        var parts: [String] = []
        if let name = snapshot.activeWorkout?.name ?? snapshot.nextWorkout?.name { parts.append(name) }
        if let week = entry.week {
            parts.append(week.goal.map { "\(week.sessions)/\($0)" } ?? "\(week.sessions)")
        }
        return Label {
            if parts.isEmpty { Text("Apolon") } else { Text(verbatim: parts.joined(separator: " · ")) }
        } icon: {
            Image(systemName: "dumbbell.fill")
        }
    }
}
