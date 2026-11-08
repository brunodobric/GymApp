import Catalog
import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Učitava povijest vježbe za detalj vježbe. Rekord se ne označava ako su rekordi isključeni u Postavkama,
/// ni za vježbu isključenu iz rekorda.
enum ExerciseHistoryLoader {
    @MainActor
    static func load(_ ref: ExerciseRef, context: ModelContext) -> ExerciseHistory? {
        let settings = UserSettings.preferred(in: (try? context.fetch(FetchDescriptor<UserSettings>())) ?? [])
        var kinds = PRKind.tracked(by: settings)
        if settings?.prExcludedExerciseKeys.contains(ref.key) == true { kinds = [] }
        return PerformanceSignpost.measure("ExerciseHistory") {
            try? StatisticsEngine(context: context).history(of: ref, recordKinds: kinds)
        }
    }
}

/// "Tvoja povijest" na dnu detalja vježbe: broj izvođenja s istaknutim brojkama i zadnja izvođenja.
/// Prikazuje se samo kad je vježba barem jednom odrađena. Iz aktivnog treninga retci ne vode na trening.
struct ExerciseHistorySection: View {
    static let recentCount = 3

    let ref: ExerciseRef
    let history: ExerciseHistory
    let linksToSessions: Bool

    @Query private var settingsList: [UserSettings]
    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }

    var body: some View {
        if !history.isEmpty {
            Section("Tvoja povijest") {
                ExerciseHistoryHighlights(history: history, unit: unit)
            }
            Section {
                ForEach(history.performances.prefix(Self.recentCount)) { performance in
                    ExercisePerformanceLink(performance: performance, unit: unit, linksToSession: linksToSessions)
                }
                if history.count > Self.recentCount {
                    NavigationLink {
                        ExerciseHistoryScreen(history: history, linksToSessions: linksToSessions)
                    } label: {
                        Text("Sva izvođenja (\(history.count))")
                    }
                }
                NavigationLink("Napredak i rekordi") { ExerciseProgressScreen(ref: ref) }
            } footer: {
                Text(ExerciseHistoryFormat.footer(history, unit: unit, linksToSessions: linksToSessions))
            }
        }
    }
}

/// Broj izvođenja i do dvije istaknute brojke. Uz veliki tekst pločice idu jedna ispod druge.
private struct ExerciseHistoryHighlights: View {
    let history: ExerciseHistory
    let unit: WeightUnit

    private var items: [ExerciseHistoryFormat.Item] {
        [ExerciseHistoryFormat.Item(value: history.count.formatted(), label: String(localized: "u treninzima"))]
            + history.highlights.map { ExerciseHistoryFormat.item($0, unit: unit) }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                ForEach(items) { item in
                    VStack(spacing: 2) {
                        Text(item.value).font(.metricSmall)
                        Text(item.label).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    LabeledContent(item.label) { Text(item.value).font(.rowValue) }
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Izvođenje koje vodi na trening, ili samo redak kad poveznica nije dopuštena.
private struct ExercisePerformanceLink: View {
    let performance: ExercisePerformance
    let unit: WeightUnit
    let linksToSession: Bool

    var body: some View {
        if linksToSession {
            NavigationLink {
                SessionByIdScreen(sessionId: performance.sessionId)
            } label: {
                ExercisePerformanceRow(performance: performance, unit: unit)
            }
        } else {
            ExercisePerformanceRow(performance: performance, unit: unit)
        }
    }
}

/// Naziv treninga, datum i sve radne serije, npr. "85 × 5 · 85 × 5 · 80 × 7".
struct ExercisePerformanceRow: View {
    let performance: ExercisePerformance
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(performance.sessionName.isEmpty ? String(localized: "Trening") : performance.sessionName)
                    .font(.itemTitle)
                if performance.hasRecord {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                        .accessibilityLabel(Text("Osobni rekord"))
                }
            }
            Text(ExerciseHistoryFormat.date(performance.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(ExerciseHistoryFormat.sets(performance.sets, inputType: performance.inputType, unit: unit))
                .font(.rowValueSmall)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Sva izvođenja vježbe po mjesecima, od najnovijeg.
struct ExerciseHistoryScreen: View {
    let history: ExerciseHistory
    let linksToSessions: Bool

    @Query private var settingsList: [UserSettings]
    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }

    var body: some View {
        let months = history.byMonth()
        List {
            ForEach(months) { month in
                Section(month.start.formatted(.dateTime.month(.wide).year())) {
                    ForEach(month.performances) { performance in
                        ExercisePerformanceLink(performance: performance, unit: unit, linksToSession: linksToSessions)
                    }
                }
            }
            Section {} footer: {
                Text(ExerciseHistoryFormat.footer(history, unit: unit, linksToSessions: linksToSessions))
            }
        }
        .navigationTitle("Sva izvođenja")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Detalj treninga po id-u. Trening obrisan u međuvremenu pokazuje poruku umjesto praznog ekrana.
private struct SessionByIdScreen: View {
    @Query private var sessions: [Session]
    @Query private var settingsList: [UserSettings]

    init(sessionId: UUID) {
        _sessions = Query(filter: #Predicate<Session> { $0.id == sessionId })
    }

    var body: some View {
        if let session = sessions.first {
            SessionDetailScreen(session: session, unit: UserSettings.weightUnit(in: settingsList))
        } else {
            ContentUnavailableView("Trening nije pronađen", systemImage: "clock")
        }
    }
}

enum ExerciseHistoryFormat {
    struct Item: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }

    static func item(_ highlight: ExerciseHistoryHighlight, unit: WeightUnit) -> Item {
        let weight = WeightFormatter(unit: unit)
        switch highlight {
        case .heaviest(let kilograms):
            return Item(value: weight.string(fromKilograms: kilograms), label: String(localized: "najteža serija"))
        case .oneRepMax(let kilograms):
            return Item(value: "≈ \(weight.string(fromKilograms: kilograms))", label: String(localized: "procjena 1RM"))
        case .mostReps(let reps):
            return Item(value: reps.formatted(), label: String(localized: "najviše ponavljanja"))
        case .longestDuration(let seconds):
            return Item(value: DurationInput.format(seconds), label: String(localized: "najdulje"))
        case .longestDistance(let meters):
            return Item(value: "\(NumberInput.format(meters / 1000)) km", label: String(localized: "najdalje"))
        }
    }

    /// Dan u tjednu i datum; godina samo kad nije tekuća.
    static func date(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        guard calendar.component(.year, from: date) != calendar.component(.year, from: now) else {
            return date.formatted(style)
        }
        return date.formatted(style.year())
    }

    /// Serije u jednom retku. Težina je bez jedinice (jedinica je u podnožju), ostale vrste kao u sažetku.
    static func sets(_ sets: [SetValues], inputType: ExerciseInputType, unit: WeightUnit) -> String {
        let weight = WeightFormatter(unit: unit)
        return sets.map { set -> String in
            switch inputType {
            case .weightReps:
                return "\(weight.number(fromKilograms: set.weightKg ?? 0)) × \(set.reps ?? 0)"
            case .weightedBodyweight:
                return "+\(weight.number(fromKilograms: set.extraWeightKg ?? 0)) × \(set.reps ?? 0)"
            case .assisted:
                return "−\(weight.number(fromKilograms: set.extraWeightKg ?? 0)) × \(set.reps ?? 0)"
            case .bodyweight, .duration, .durationDistance:
                return SetFormat.text(set, inputType: inputType, unit: unit)
            }
        }
        .joined(separator: " · ")
    }

    static func footer(_ history: ExerciseHistory, unit: WeightUnit, linksToSessions: Bool) -> String {
        let usesWeight = history.performances.contains {
            [.weightReps, .weightedBodyweight, .assisted].contains($0.inputType)
        }
        var parts: [String] = []
        if usesWeight { parts.append(String(localized: "Težine su u \(unit.symbol).")) }
        parts.append(String(localized: "Zagrijavanje se ne prikazuje."))
        if linksToSessions { parts.append(String(localized: "Dodir otvara cijeli trening.")) }
        return parts.joined(separator: " ")
    }
}
