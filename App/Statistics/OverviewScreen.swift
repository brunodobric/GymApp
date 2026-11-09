import Charts
import Models
import Stats
import SwiftData
import SwiftUI
import Training
import Units

/// Pregled tjedna, mjeseca ili godine: sažetak s promjenom prema razdoblju prije, treninzi (po danima,
/// kalendar mjeseca ili mjeseci i aktivnost godine), serije po mišiću s mapom tijela i rekordi razdoblja.
/// Strelice listaju razdoblja unatrag. Otvara se s kartice Ovaj tjedan na Početnoj i iz Statistike.
struct OverviewScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogStore.self) private var catalogStore
    @Query private var customExercises: [CustomExercise]
    @Query private var settingsList: [UserSettings]

    @State private var period: OverviewPeriod
    /// Datum u prikazanom razdoblju; pri promjeni razdoblja ostaje, pa tjedan prelazi u svoj mjesec i godinu.
    @State private var anchor = Date.now
    @State private var data: OverviewData?
    @State private var selectedRegion: String?

    /// Najviše toliko godina unatrag.
    private static let oldestYears = 10

    init(period: OverviewPeriod = .week) {
        _period = State(initialValue: period)
    }

    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }
    private var unit: WeightUnit { UserSettings.weightUnit(in: settingsList) }
    /// Mišići razdoblja (mapa i serije) su dio detaljnog prikaza, kao kartica Mišići u Statistici.
    private var isPro: Bool { settings?.statsDetail == .pro }
    private var interval: DateInterval { period.interval(containing: anchor) }
    private var isCurrent: Bool { interval.contains(.now) }

    private var isOldest: Bool {
        let limit = Calendar.current.date(byAdding: .year, value: -Self.oldestYears, to: .now) ?? .distantPast
        return interval.start <= limit
    }

    private struct LoadKey: Equatable {
        var period: OverviewPeriod
        var start: Date
        /// Izmjena podataka (`DataVersion`).
        var version: Int
        var custom: Int
        var goal: Int?
        var kinds: Set<PRKind>
        var excluded: Set<String>
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Razdoblje", selection: $period) {
                    Text("Tjedan").tag(OverviewPeriod.week)
                    Text("Mjesec").tag(OverviewPeriod.month)
                    Text("Godina").tag(OverviewPeriod.year)
                }
                .pickerStyle(.segmented)
                periodPicker
                if let data, data.summary.period == period {
                    OverviewSummaryCard(current: data.summary, previous: data.previous)
                    switch period {
                    case .week:
                        WeekDaysCard(data: data, unit: unit)
                    case .month:
                        MonthCalendarCard(data: data, unit: unit)
                    case .year:
                        YearCard(summary: data.summary) { month in
                            anchor = month
                            period = .month
                        }
                    }
                    if isPro {
                        OverviewMusclesCard(
                            period: period, comparison: data.comparison, heatmap: data.heatmap, isCurrent: isCurrent,
                            female: settings?.bodyMapFemale ?? false, selected: $selectedRegion
                        )
                    }
                    if !data.records.isEmpty {
                        StatisticsCard(title: recordsTitle) {
                            ForEach(Array(data.records.enumerated()), id: \.offset) { _, entry in
                                RecordHighlightRow(exerciseName: entry.exerciseName, record: entry.record, unit: unit)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pregled")
        .toolbar {
            if !isCurrent {
                ToolbarItem(placement: .primaryAction) {
                    Button("Danas") { anchor = .now }
                }
            }
        }
        .task(id: LoadKey(
            period: period, start: interval.start, version: DataVersion.shared.value,
            custom: customExercises.count, goal: settings?.trainingDaysPerWeek, kinds: PRKind.tracked(by: settings),
            excluded: settings?.prExcludedExerciseKeys ?? []
        )) { load() }
        .onChange(of: interval.start) { selectedRegion = nil }
        .onChange(of: period) { selectedRegion = nil }
    }

    private var recordsTitle: LocalizedStringKey {
        switch period {
        case .week: "Rekordi tjedna"
        case .month: "Rekordi mjeseca"
        case .year: "Rekordi godine"
        }
    }

    /// Strelice za prethodno i sljedeće razdoblje te njegov naziv.
    private var periodPicker: some View {
        HStack {
            Button(previousLabel, systemImage: "chevron.backward") { anchor = period.shift(anchor, by: -1) }
                .disabled(isOldest)
            Spacer(minLength: 8)
            Text(rangeText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            Button(nextLabel, systemImage: "chevron.forward") { anchor = min(period.shift(anchor, by: 1), .now) }
                .disabled(isCurrent)
        }
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
    }

    private var previousLabel: LocalizedStringKey {
        switch period {
        case .week: "Prethodni tjedan"
        case .month: "Prethodni mjesec"
        case .year: "Prethodna godina"
        }
    }

    private var nextLabel: LocalizedStringKey {
        switch period {
        case .week: "Sljedeći tjedan"
        case .month: "Sljedeći mjesec"
        case .year: "Sljedeća godina"
        }
    }

    /// Npr. "2. – 8. studenoga 2026.", "studeni 2026." ili "2026."
    private var rangeText: String {
        let start = interval.start
        switch period {
        case .week:
            let last = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            return (start..<last).formatted(.interval.day().month(.wide).year())
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        case .year:
            return start.formatted(.dateTime.year())
        }
    }

    private func load() {
        PerformanceSignpost.measure("PeriodOverview") {
            let engine = StatisticsEngine(context: context)
            let info = ExerciseInfoBuilder.provider(catalog: catalogStore.catalog, custom: customExercises)
            let isCardio = ExerciseInfoBuilder.isCardio(info)
            let goal = settings?.trainingDaysPerWeek
            let now = Date.now
            let reference = anchor
            guard let current = try? engine.periodSummary(period, containing: reference, now: now, goal: goal, isCardio: isCardio) else {
                data = nil
                return
            }
            let previous = try? engine.periodSummary(
                period, containing: period.shift(current.interval.start, by: -1), now: now, goal: goal, isCardio: isCardio
            )
            let sessions = (try? engine.sessions(in: current.interval)) ?? []
            let records = (try? engine.personalRecords(
                kinds: PRKind.tracked(by: settings), excluding: settings?.prExcludedExerciseKeys ?? []
            )) ?? []
            // Tekuće razdoblje se za prosjek serija tjedno broji do sada, ne do kraja.
            let heatmapEnd = min(current.interval.end, now.addingTimeInterval(1))
            data = OverviewData(
                summary: current,
                previous: previous,
                days: current.sessionsByDay(sessions),
                figures: Dictionary(
                    sessions.map { ($0.id, SessionFigures(session: $0, isCardio: isCardio)) },
                    uniquingKeysWith: { first, _ in first }
                ),
                mixes: Dictionary(
                    sessions.map { ($0.id, SessionCardio.mix(of: $0, isCardio: isCardio)) },
                    uniquingKeysWith: { first, _ in first }
                ),
                comparison: try? engine.periodVolume(period, containing: reference, now: now, info: info),
                heatmap: (try? engine.heatmap(from: current.interval.start, until: heatmapEnd, info: info)) ?? [:],
                records: records.filter { current.interval.contains($0.date) && $0.date < current.interval.end }
            )
        }
    }
}

/// Sve što ekran pregleda prikazuje, učitano odjednom.
struct OverviewData {
    let summary: PeriodSummary
    let previous: PeriodSummary?
    /// Treninzi po danu (ključ je početak dana).
    let days: [Date: [Session]]
    let figures: [UUID: SessionFigures]
    let mixes: [UUID: SessionMix]
    let comparison: VolumeComparison?
    let heatmap: [String: RegionLoad]
    /// Rekordi postavljeni u razdoblju, od najnovijeg.
    let records: [RecordEntry]

    func sessions(on date: Date) -> [Session] {
        days[Calendar.current.startOfDay(for: date)] ?? []
    }

    /// Broj rekorda postavljenih u treningu (rekord nosi početak svog treninga).
    func recordCount(of session: Session) -> Int {
        records.filter { $0.date == session.startedAt }.count
    }
}

// MARK: - Sažetak

/// Treninzi, ukupno vrijeme, tvrde serije i kardio, s promjenom prema razdoblju prije. Za mjesec i godinu
/// i prosjek treninga tjedno.
private struct OverviewSummaryCard: View {
    let current: PeriodSummary
    let previous: PeriodSummary?

    private var showsCardio: Bool {
        current.cardioSeconds >= 60 || (previous?.cardioSeconds ?? 0) >= 60
    }

    var body: some View {
        StatisticsCard(title: "Sažetak") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile(value: sessionsText, label: "Treninga", change: countChange(current.sessions, previous?.sessions))
                if current.period != .week {
                    tile(value: perWeekText, label: "Tjedno u prosjeku", change: nil)
                }
                tile(value: WeekFormat.duration(current.totalSeconds), label: "Ukupno",
                     change: durationChange(current.totalSeconds, previous?.totalSeconds))
                tile(value: current.hardSets.formatted(), label: "Tvrde serije",
                     change: percentChange(current.hardSets, previous?.hardSets))
                if showsCardio {
                    tile(value: cardioText, label: "Kardio",
                         change: durationChange(TimeInterval(current.cardioSeconds), previous.map { TimeInterval($0.cardioSeconds) }))
                }
            }
            if previous != nil {
                Text(footnote).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var footnote: LocalizedStringKey {
        switch current.period {
        case .week: "Promjene su u odnosu na tjedan prije."
        case .month: "Promjene su u odnosu na mjesec prije."
        case .year: "Promjene su u odnosu na godinu prije."
        }
    }

    private var sessionsText: String {
        guard current.period == .week, let goal = current.weeklyGoal else { return current.sessions.formatted() }
        return String(localized: "\(current.sessions) od \(goal)")
    }

    /// Npr. "2,8" ili s ciljem "2,8 od 4".
    private var perWeekText: String {
        let value = current.sessionsPerWeek.formatted(.number.precision(.fractionLength(0...1)))
        guard let goal = current.weeklyGoal else { return value }
        return String(localized: "\(value) od \(goal)")
    }

    private var cardioText: String {
        let time = WeekFormat.duration(TimeInterval(current.cardioSeconds))
        guard current.cardioMeters > 0 else { return time }
        return "\(time) · \(CardioText.distance(current.cardioMeters))"
    }

    private func tile(value: String, label: LocalizedStringKey, change: Change?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.metricSmall)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                Text(label).foregroundStyle(.secondary)
                if let change {
                    Text(verbatim: change.text).foregroundStyle(change.isUp ? Color.green : Color.secondary)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: CornerRadius.inner))
        .accessibilityElement(children: .combine)
    }

    private struct Change {
        let text: String
        let isUp: Bool
    }

    private func countChange(_ now: Int, _ before: Int?) -> Change? {
        guard let before, now != before else { return nil }
        let delta = now - before
        return Change(text: delta.formatted(.number.sign(strategy: .always())), isUp: delta > 0)
    }

    private func durationChange(_ now: TimeInterval, _ before: TimeInterval?) -> Change? {
        guard let before else { return nil }
        let delta = now - before
        guard abs(delta) >= 60 else { return nil }
        let sign = delta > 0 ? "+" : "−"
        return Change(text: sign + WeekFormat.duration(abs(delta)), isUp: delta > 0)
    }

    private func percentChange(_ now: Int, _ before: Int?) -> Change? {
        guard let before, before > 0, now != before else { return nil }
        let change = Double(now - before) / Double(before)
        return Change(text: ChangeFormat.percent(change), isUp: change > 0)
    }
}

enum WeekFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

// MARK: - Trening u popisu

/// Redak treninga s vrstom, trajanjem, serijama, kardiom i rekordima; dodir otvara detalje.
private struct OverviewSessionRow: View {
    let session: Session
    let data: OverviewData
    let unit: WeightUnit

    var body: some View {
        NavigationLink {
            SessionDetailScreen(session: session, unit: unit)
        } label: {
            HStack(spacing: 10) {
                WorkoutKindIcon(mix: data.mixes[session.id] ?? .strength)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.itemTitle)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(minHeight: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Npr. "1 h 5 min · 18 serija · 2 rekorda" ili "45 min · 7,2 km".
    private var detail: String {
        var parts: [String] = []
        if let figures = data.figures[session.id] {
            parts.append(WeekFormat.duration(figures.durationSeconds))
            if figures.hardSets > 0 { parts.append(String(localized: "\(figures.hardSets) serija")) }
            if let meters = figures.cardioMeters { parts.append(CardioText.distance(meters)) }
        }
        let records = data.recordCount(of: session)
        if records > 0 { parts.append(String(localized: "\(records) rekorda")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Tjedan po danima

/// Dani tjedna s treninzima; dan bez treninga je odmor, a dani koji još nisu došli se ne prikazuju.
private struct WeekDaysCard: View {
    let data: OverviewData
    let unit: WeightUnit

    private var shownDays: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return data.summary.days.map(\.date).filter { $0 <= today }
    }

    var body: some View {
        StatisticsCard(title: "Po danima") {
            VStack(spacing: 0) {
                ForEach(shownDays, id: \.self) { date in
                    let sessions = data.sessions(on: date)
                    if date != shownDays.first { Divider() }
                    HStack(alignment: .top, spacing: 12) {
                        dayLabel(date)
                        VStack(spacing: 0) {
                            if sessions.isEmpty {
                                Text("Odmor")
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            }
                            ForEach(sessions, id: \.id) { session in
                                OverviewSessionRow(session: session, data: data, unit: unit)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.weekday(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.day())
                .font(.headline)
        }
        .frame(width: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide)))
    }
}

// MARK: - Mjesec u kalendaru

/// Kalendar mjeseca s označenim danima treninga. Dodir na dan pokazuje njegove treninge ispod kalendara.
private struct MonthCalendarCard: View {
    @Environment(\.appAccent) private var accent
    let data: OverviewData
    let unit: WeightUnit
    @State private var selectedDay: Date?

    private var calendar: Calendar { .current }

    var body: some View {
        StatisticsCard(title: "Kalendar") {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, symbol in
                        Text(verbatim: symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 40)
                            }
                        }
                    }
                }
            }
            if let selectedDay {
                let sessions = data.sessions(on: selectedDay)
                Divider()
                Text(selectedDay, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                if sessions.isEmpty {
                    Text("Odmor").foregroundStyle(.tertiary)
                }
                ForEach(sessions, id: \.id) { session in
                    OverviewSessionRow(session: session, data: data, unit: unit)
                }
            } else if data.summary.sessions > 0 {
                Text("Dodirni dan za njegove treninge.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onChange(of: data.summary.interval.start) { selectedDay = nil }
    }

    private func dayCell(_ day: WeekProgress.Day) -> some View {
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false
        let isFuture = day.date > .now
        return Button {
            selectedDay = isSelected ? nil : day.date
        } label: {
            VStack(spacing: 2) {
                Text(day.date, format: .dateTime.day())
                    .font(.body)
                    .foregroundStyle(isFuture ? .tertiary : .primary)
                Circle()
                    .fill(day.isTrained ? accent : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected ? accent.opacity(0.2) : Color.clear, in: .rect(cornerRadius: CornerRadius.small))
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Text(day.date.formatted(date: .complete, time: .omitted)))
        .accessibilityValue(day.isTrained ? Text("Ima trening") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Dani po tjednima, s praznim mjestima ispred prvog dana i iza zadnjeg, da stupci odgovaraju danima u tjednu.
    private var weeks: [[WeekProgress.Day?]] {
        guard let first = data.summary.days.first else { return [] }
        let weekday = calendar.component(.weekday, from: first.date)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let all = Array(repeating: nil, count: leading) + data.summary.days.map { Optional($0) }
        return stride(from: 0, to: all.count, by: 7).map { start in
            let week = Array(all[start..<min(start + 7, all.count)])
            return week + Array(repeating: nil, count: 7 - week.count)
        }
    }
}

// MARK: - Godina

/// Treninzi po mjesecima (dodir na mjesec otvara njegov pregled) i aktivnost cijele godine po danima.
private struct YearCard: View {
    @Environment(\.appAccent) private var accent
    let summary: PeriodSummary
    let onSelectMonth: (Date) -> Void
    @State private var selectedMonth: Date?

    var body: some View {
        StatisticsCard(title: "Po mjesecima") {
            Chart(summary.months, id: \.start) { month in
                BarMark(
                    x: .value("Mjesec", month.start, unit: .month),
                    y: .value("Treninga", month.sessions)
                )
                .foregroundStyle(accent)
            }
            .chartXAxis {
                AxisMarks(values: summary.months.map(\.start)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartXSelection(value: $selectedMonth)
            .chartHeight(180, regular: 240)
            .accessibilityLabel(Text("Graf treninga po mjesecima"))
            .onChange(of: selectedMonth) {
                guard let selectedMonth, selectedMonth <= .now else { return }
                onSelectMonth(selectedMonth)
            }
            Text("Dodirni mjesec za njegov pregled.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Aktivnost").font(.subheadline.weight(.semibold))
            YearActivityGrid(days: summary.days)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Dana s treningom: \(summary.trainedDays)"))
            Text("Dana s treningom: \(summary.trainedDays)")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// Dani godine u stupcima po tjednima, kao kvadratići: obojen je dan s treningom.
private struct YearActivityGrid: View {
    @Environment(\.appAccent) private var accent
    let days: [WeekProgress.Day]

    private var calendar: Calendar { .current }

    /// Prazna mjesta ispred prvog dana, da redovi odgovaraju danima u tjednu.
    private var leading: Int {
        guard let first = days.first else { return 0 }
        return (calendar.component(.weekday, from: first.date) - calendar.firstWeekday + 7) % 7
    }

    private var columns: Int { (leading + days.count + 6) / 7 }

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 1.5
            let cell = min((size.width + spacing) / CGFloat(max(columns, 1)), (size.height + spacing) / 7) - spacing
            let today = Date.now
            for (index, day) in days.enumerated() {
                let position = index + leading
                let rect = CGRect(
                    x: CGFloat(position / 7) * (cell + spacing),
                    y: CGFloat(position % 7) * (cell + spacing),
                    width: cell, height: cell
                )
                let color: Color = if day.isTrained {
                    accent
                } else if day.date > today {
                    .clear
                } else {
                    Color(.tertiarySystemFill)
                }
                context.fill(Path(roundedRect: rect, cornerRadius: cell / 4), with: .color(color))
            }
        }
        .aspectRatio(CGFloat(max(columns, 1)) / 7, contentMode: .fit)
    }
}

// MARK: - Serije po mišiću

/// Tvrde serije po mišiću uz razdoblje prije, i mapa tijela s opterećenjem razdoblja. Za mjesec i godinu
/// prosjek serija tjedno.
private struct OverviewMusclesCard: View {
    @Environment(\.appAccent) private var accent
    let period: OverviewPeriod
    let comparison: VolumeComparison?
    let heatmap: [String: RegionLoad]
    let isCurrent: Bool
    let female: Bool
    @Binding var selected: String?

    /// Stupac grafa. Id je stabilan (mišić i razdoblje), da graf ne crta sve iznova pri svakom iscrtavanju.
    private struct Entry: Identifiable {
        let muscle: String
        let series: String
        let sets: Double
        var id: String { "\(muscle)|\(series)" }
    }

    private var currentTitle: String {
        switch (period, isCurrent) {
        case (.week, true): String(localized: "Ovaj tjedan")
        case (.week, false): String(localized: "Odabrani tjedan")
        case (.month, true): String(localized: "Ovaj mjesec")
        case (.month, false): String(localized: "Odabrani mjesec")
        case (.year, true): String(localized: "Ova godina")
        case (.year, false): String(localized: "Odabrana godina")
        }
    }

    private var previousTitle: String {
        switch (period, isCurrent) {
        case (.week, true): String(localized: "Prošli tjedan")
        case (.week, false): String(localized: "Tjedan prije")
        case (.month, true): String(localized: "Prošli mjesec")
        case (.month, false): String(localized: "Mjesec prije")
        case (.year, true): String(localized: "Prošla godina")
        case (.year, false): String(localized: "Godina prije")
        }
    }

    private var emptyText: LocalizedStringKey {
        switch period {
        case .week: "U ovom tjednu nema serija snage."
        case .month: "U ovom mjesecu nema serija snage."
        case .year: "U ovoj godini nema serija snage."
        }
    }

    private var title: LocalizedStringKey {
        period == .week ? "Serije po mišiću" : "Serije po mišiću tjedno"
    }

    private var chartLabel: LocalizedStringKey {
        switch period {
        case .week: "Graf serija po mišićima u tjednu i tjednu prije"
        case .month: "Graf serija tjedno po mišićima u mjesecu i mjesecu prije"
        case .year: "Graf serija tjedno po mišićima u godini i godini prije"
        }
    }

    /// Šest mišića s najviše serija, svaki s dva stupca (razdoblje i razdoblje prije).
    private var entries: [Entry] {
        guard let comparison else { return [] }
        return comparison.muscles.prefix(6).flatMap { item in
            let name = BodyRegion.title(item.region)
            return [
                Entry(muscle: name, series: previousTitle, sets: item.previousSets),
                Entry(muscle: name, series: currentTitle, sets: item.currentSets),
            ]
        }
    }

    var body: some View {
        StatisticsCard(title: title) {
            if heatmap.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    BodyFigureView(female: female, back: false, heatmap: heatmap, selected: $selected)
                    BodyFigureView(female: female, back: true, heatmap: heatmap, selected: $selected)
                }
                .accessibilityHidden(true)
                HeatmapLegend()
                if let selected {
                    Text(selectedText(selected)).font(.subheadline)
                }
            }
            if !entries.isEmpty {
                Chart(entries) { entry in
                    BarMark(
                        x: .value("Mišić", entry.muscle),
                        y: .value("Tvrde serije", entry.sets)
                    )
                    .foregroundStyle(by: .value("Razdoblje", entry.series))
                    .position(by: .value("Razdoblje", entry.series))
                }
                .chartForegroundStyleScale([previousTitle: Color.secondary.opacity(0.5), currentTitle: accent])
                .chartHeight(220, regular: 320)
                .accessibilityLabel(Text(chartLabel))
                Text("Serija u kojoj mišić pomaže broji se kao pola, a serija s RPE ispod 6 se ne broji.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Tjedan: serije u tjednu. Mjesec i godina: prosjek serija tjedno.
    private func selectedText(_ region: String) -> String {
        let load = heatmap[region]
        let name = BodyRegion.title(region)
        if period == .week {
            let sets = (load?.sets ?? 0).formatted(.number.precision(.fractionLength(0...1)))
            return String(localized: "\(name): \(sets) tvrdih serija")
        }
        let sets = (load?.weeklySets ?? 0).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(name): \(sets) tvrdih serija tjedno")
    }
}

// MARK: - Kartica u Statistici

/// Kartica Pregled na vrhu Statistike: tekući tjedan (treninzi prema cilju, dani, serije i vrijeme) te
/// mjesec i godina ukratko te graf treninga po tjednu za zadnjih 12 tjedana. Otvara Pregled na tjednu,
/// a retci mjeseca i godine na svom razdoblju.
struct OverviewCard: View {
    let week: WeekProgress
    let month: PeriodSummary?
    let year: PeriodSummary?
    /// Treninzi po tjednu, zadnjih 12 tjedana.
    var frequency: [FrequencyPoint] = []

    var body: some View {
        StatisticsCard(title: "Pregled") {
            NavigationLink {
                OverviewScreen()
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Ovaj tjedan").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    weekCount
                    if let fraction = week.goalFraction {
                        ProgressView(value: fraction).accessibilityHidden(true)
                    }
                    WeekDaysStrip(progress: week)
                    if week.sessions > 0 {
                        PeriodFigures(hardSets: week.hardSets, cardioSeconds: week.cardioSeconds, totalSeconds: week.totalSeconds)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if let month {
                Divider()
                periodRow(title: "Ovaj mjesec", summary: month)
            }
            if let year {
                Divider()
                periodRow(title: "Ova godina", summary: year)
            }
            if !frequency.isEmpty {
                Divider()
                frequencyChart
            }
        }
    }

    private var frequencyAverage: Double {
        Double(frequency.reduce(0) { $0 + $1.sessions }) / Double(max(frequency.count, 1))
    }

    @ViewBuilder
    private var frequencyChart: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Treninga tjedno").font(.subheadline.weight(.semibold))
            Text("Prosjek zadnjih 12 tjedana: \(frequencyAverage.formatted(.number.precision(.fractionLength(0...1))))")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        Chart(frequency, id: \.weekStart) { point in
            BarMark(
                x: .value("Tjedan", point.weekStart, unit: .weekOfYear),
                y: .value("Treninga", point.sessions)
            )
        }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartHeight(120, regular: 180)
        .accessibilityLabel(Text("Graf broja treninga po tjednima"))
    }

    @ViewBuilder
    private var weekCount: some View {
        if let goal = week.goal {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(week.sessions, format: .number).font(.metric)
                Text("od \(goal) treninga").font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("\(week.sessions) treninga").font(.metric)
        }
    }

    /// Npr. "Ovaj mjesec · 12 treninga · 2,8 tjedno"; dodir otvara Pregled na tom razdoblju.
    private func periodRow(title: LocalizedStringKey, summary: PeriodSummary) -> some View {
        NavigationLink {
            OverviewScreen(period: summary.period)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(verbatim: detail(summary)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func detail(_ summary: PeriodSummary) -> String {
        var parts = [String(localized: "\(summary.sessions) treninga"), PeriodText.perWeek(summary)]
        if summary.hardSets > 0 { parts.append(String(localized: "\(summary.hardSets) tvrdih serija")) }
        return parts.joined(separator: " · ")
    }
}
