import SwiftUI
import WidgetData
import WidgetKit

/// Ovaj tjedan (prijedlog 2 i 7): krug do tjednog cilja i niz tjedana zaredom, dani u tjednu s vrstom treninga
/// i krug na zaključanom zaslonu. Isti podaci kao kartica Ovaj tjedan na Početnoj.
struct WeekWidget: Widget {
    static let kind = "ThisWeek"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WeekView(entry: entry)
                .tint(entry.snapshot.accentColor)
                .containerBackground(for: .widget) { CardBackground() }
                .widgetURL(WidgetLink.week.url)
        }
        .configurationDisplayName("Ovaj tjedan")
        .description("Treninzi ovog tjedna prema tvom cilju i tjedni niz.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

private struct WeekView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let week = entry.week ?? WidgetSnapshot.Week(
            start: Calendar.current.dateInterval(of: .weekOfYear, for: entry.date)?.start ?? entry.date,
            sessions: 0, goal: nil, streakWeeks: 0
        )
        switch family {
        case .systemMedium: medium(week)
        case .accessoryCircular: circular(week)
        default: small(week)
        }
    }

    // MARK: Mali

    private func small(_ week: WidgetSnapshot.Week) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeading("Ovaj tjedan", symbol: "target")
            HStack(spacing: 12) {
                WeekRing(week: week, lineWidth: 8)
                    .frame(width: 62, height: 62)
                if week.sessions > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(WidgetText.duration(week.totalSeconds)).font(.rowValueSmall).lineLimit(1).minimumScaleFactor(0.7)
                        Text("Ukupno").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            StreakLabel(weeks: week.streakWeeks)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Srednji

    private func medium(_ week: WidgetSnapshot.Week) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeading("Ovaj tjedan", symbol: "target")
                Spacer(minLength: 8)
                StreakLabel(weeks: week.streakWeeks)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(week.sessions, format: .number).font(.metric)
                if let goal = week.goal {
                    Text("od \(goal) treninga").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            days(week)
            if week.sessions > 0 {
                figures(week)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func days(_ week: WidgetSnapshot.Week) -> some View {
        HStack(spacing: 0) {
            ForEach(week.days, id: \.date) { day in
                let isToday = Calendar.current.isDate(day.date, inSameDayAs: entry.date)
                VStack(spacing: 2) {
                    ZStack {
                        Circle().fill(day.isTrained ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)))
                        if isToday && !day.isTrained {
                            Circle().strokeBorder(.tint, lineWidth: 2)
                        }
                        if let mix = day.mix {
                            Image(systemName: mix.symbol)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .widgetAccentable()
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Tvrde serije, kardio i ukupno vrijeme u jednom retku; nula se ne prikazuje.
    private func figures(_ week: WidgetSnapshot.Week) -> some View {
        HStack(spacing: 12) {
            if week.hardSets > 0 {
                figure(Text(week.hardSets, format: .number), label: "Tvrde serije")
            }
            if week.cardioSeconds >= 60 {
                figure(Text(WidgetText.duration(week.cardioSeconds)), label: "Kardio")
            }
            figure(Text(WidgetText.duration(week.totalSeconds)), label: "Ukupno")
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private func figure(_ value: Text, label: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            value.font(.rowValueSmall)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Zaključani zaslon

    @ViewBuilder
    private func circular(_ week: WidgetSnapshot.Week) -> some View {
        if let fraction = week.goalFraction, let goal = week.goal {
            Gauge(value: fraction) {
                Image(systemName: "target")
            } currentValueLabel: {
                Text(verbatim: "\(week.sessions)/\(goal)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(week.sessions, format: .number).font(.title2.bold())
                    Image(systemName: "dumbbell.fill").font(.caption2)
                }
            }
        }
    }
}

/// Krug do tjednog cilja s "2/3" u sredini; bez cilja samo broj treninga.
struct WeekRing: View {
    let week: WidgetSnapshot.Week
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: week.goalFraction ?? (week.sessions > 0 ? 1 : 0))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Group {
                if let goal = week.goal {
                    Text(verbatim: "\(week.sessions)/\(goal)")
                } else {
                    Text(week.sessions, format: .number)
                }
            }
            .font(.metricSmall)
            .minimumScaleFactor(0.6)
            .padding(lineWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(week.sessions) treninga"))
    }
}

/// "3 tjedna zaredom" s plamenom; prikazuje se od dva tjedna.
struct StreakLabel: View {
    let weeks: Int

    var body: some View {
        if weeks >= 2 {
            Label {
                Text("\(weeks) tjedana zaredom")
            } icon: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}
