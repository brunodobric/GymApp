import SwiftUI
import WidgetData
import WidgetKit

/// Zadnji trening (prijedlog 5): kada, vrsta, trajanje, serije i do dva rekorda, kao kartica na Početnoj.
struct LastWorkoutWidget: Widget {
    static let kind = "LastWorkout"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            LastWorkoutView(entry: entry)
                .tint(entry.snapshot.accentColor)
                .containerBackground(for: .widget) { CardBackground() }
                .widgetURL(WidgetLink.lastWorkout.url)
        }
        .configurationDisplayName("Zadnji trening")
        .description("Zadnji odrađeni trening i rekordi iz njega.")
        .supportedFamilies([.systemMedium])
    }
}

private struct LastWorkoutView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let last = entry.snapshot.lastWorkout {
                WidgetHeading(
                    text: Text("Zadnji trening") + Text(verbatim: " · ") + Text(WidgetText.relativeDay(last.startedAt, now: entry.date)),
                    symbol: last.mix.symbol
                )
                Text(last.name).font(.cardTitle).lineLimit(1)
                detail(last).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if !last.highlights.isEmpty {
                    Divider().padding(.vertical, 2)
                    ForEach(last.highlights, id: \.exercise) { highlight in
                        HStack {
                            Label(highlight.exercise, systemImage: "trophy.fill")
                                .font(.footnote)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(highlight.value).font(.rowValueSmall).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                WidgetHeading("Zadnji trening", symbol: "clock.arrow.circlepath")
                Spacer(minLength: 0)
                Text("Još nema odrađenih treninga.").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "Snaga + kardio · 1 h 4 min · 18 serija".
    private func detail(_ last: WidgetSnapshot.LastWorkout) -> Text {
        var text = Text(last.mix.title)
        if let seconds = last.durationSeconds, seconds >= 60 {
            text = text + Text(verbatim: " · \(WidgetText.duration(seconds))")
        }
        if last.hardSets > 0 {
            text = text + Text(verbatim: " · ") + Text("\(last.hardSets) serija")
        }
        return text
    }
}

/// Najnoviji osobni rekord (prijedlog 4).
struct RecordWidget: Widget {
    static let kind = "LatestRecord"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            RecordView(entry: entry)
                .tint(entry.snapshot.accentColor)
                .containerBackground(for: .widget) { CardBackground() }
                .widgetURL(WidgetLink.lastWorkout.url)
        }
        .configurationDisplayName("Zadnji rekord")
        .description("Najnoviji osobni rekord.")
        .supportedFamilies([.systemSmall])
    }
}

private struct RecordView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeading("Rekordi", symbol: "trophy.fill")
            if let record = entry.snapshot.latestRecord {
                Text(WidgetText.relativeDay(record.date, now: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Text(record.exercise).font(.itemTitle).lineLimit(2)
                Spacer(minLength: 0)
                Text(record.value)
                    .font(.metric)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Spacer(minLength: 0)
                Text("Još nema rekorda.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
