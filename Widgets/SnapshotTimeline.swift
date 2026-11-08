import SwiftUI
import Units
import WidgetData
import WidgetKit

/// Zapis na vremenskoj crti widgeta: snimka iz aplikacije i trenutak za koji se crta.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    /// Tjedan kakav je u trenutku zapisa (snimka može biti iz prošlog tjedna).
    var week: WidgetSnapshot.Week? { snapshot.week?.current(at: date) }
}

/// Čita snimku koju je spremila aplikacija (`WidgetRefresher`). Aplikacija osvježava widgete kad se podaci
/// promijene, a vremenska crta ima zapis za svaku iduću ponoć, jer se tada mijenjaju "danas", tjedan i
/// "prije N dana".
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let stored = WidgetSnapshotStore.shared.load()
        // U galeriji widgeta bez podataka primjer pokazuje kako widget izgleda.
        let snapshot: WidgetSnapshot = context.isPreview && (stored?.generatedAt ?? .distantPast) == .distantPast ? .sample() : (stored ?? .empty)
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.shared.load() ?? .empty
        let dates = [now] + WidgetDates.nextMidnights(after: now, count: 7)
        completion(Timeline(entries: dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }, policy: .atEnd))
    }
}

// MARK: - Izgled

extension WidgetSnapshot {
    /// Naglasna boja iz Postavki (kao `AccentChoice.color` u aplikaciji).
    var accentColor: Color {
        switch accent {
        case "green": .green
        case "orange": .orange
        case "red": .red
        case "purple": .purple
        case "pink": .pink
        case "teal": .teal
        default: .blue
        }
    }

    var weightFormatter: WeightFormatter { WeightFormatter(unit: weightUnit) }
}

extension WidgetSnapshot.Mix {
    var symbol: String {
        switch self {
        case .strength, .mixed: "dumbbell.fill"
        case .cardio: "figure.run"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .strength: "Snaga"
        case .cardio: "Kardio"
        case .mixed: "Snaga + kardio"
        }
    }
}

/// Pozadina widgeta na početnom zaslonu: ista ploha kao kartice na Početnoj.
struct CardBackground: View {
    var body: some View {
        Color(.secondarySystemGroupedBackground)
    }
}

/// Naslov widgeta verzalom uz ikonu, u naglasnoj boji (kao naslov kartice na Početnoj).
struct WidgetHeading: View {
    let title: Text
    let symbol: String

    init(_ title: LocalizedStringKey, symbol: String) {
        self.title = Text(title)
        self.symbol = symbol
    }

    init(text: Text, symbol: String) {
        self.title = text
        self.symbol = symbol
    }

    var body: some View {
        Label { title } icon: { Image(systemName: symbol) }
            .font(.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(.tint)
            .lineLimit(1)
            .widgetAccentable()
    }
}

/// Okrugli gumb ▶ koji otvara aplikaciju i pokreće sljedeći trening.
struct StartButton: View {
    var size: CGFloat = 44

    var body: some View {
        Button(intent: StartWorkoutFromWidgetIntent()) {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.tint))
                .widgetAccentable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Započni trening"))
    }
}

enum WidgetText {
    /// "Danas", "jučer", "prije 3 dana" po kalendarskim danima (kao kartica Zadnji trening).
    static func relativeDay(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(from: DateComponents(day: -WidgetDates.daysAgo(date, now: now)))
    }

    /// Trajanje u satima i minutama, npr. "1 h 4 min".
    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
