import Models
import SwiftData
import SwiftUI
import Stats
import Units

/// Povijest odrađenih treninga: popis s filterom i sortiranjem te kalendar s točkicama.
///
/// U regular širini (iPad) popis i detalji treninga stoje jedan pored drugog (`NavigationSplitView`).
/// U compact širini split view se sklapa u običan stog, pa se iPhone ponaša kao prije.
struct HistoryScreen: View {
    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }) private var ownSessions: [Session]
    /// Kardio iz Zdravlja je u lokalnoj bazi (ne sinkronizira se), a u povijesti stoji uz vlastite treninge.
    @Query private var healthWorkouts: [HealthWorkout]
    private var sessions: [Session] { Session.merged(ownSessions, health: healthWorkouts) }
    @Query private var settingsList: [UserSettings]

    @State private var filter = HistoryFilter()
    @State private var showsCalendar = false
    @State private var selectedDay: Date?
    @State private var month = Date()
    /// Odabrani trening u popisu (id, da obrisani trening ne ostane odabran).
    @State private var selectedId: UUID?

    private var unit: WeightUnit { UserSettings.preferred(in: settingsList)?.weightUnit ?? .kilograms }
    private var visible: [Session] { filter.apply(to: sessions) }

    /// S kalendarom: treninzi prikazanog mjeseca ili odabranog dana.
    private var listed: [Session] {
        showsCalendar ? filter.apply(to: sessions, month: month, day: selectedDay) : visible
    }

    private var selectedSession: Session? {
        guard let selectedId else { return nil }
        return sessions.first { $0.id == selectedId }
    }

    var body: some View {
        NavigationSplitView {
            sessionList
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            NavigationStack {
                if let session = selectedSession {
                    SessionDetailScreen(session: session, unit: unit)
                        .id(session.id)
                } else {
                    ContentUnavailableView(
                        "Odaberi trening",
                        systemImage: "clock",
                        description: Text("Detalji odabranog treninga prikazuju se ovdje.")
                    )
                }
            }
        }
        // Obrisan trening (npr. iz detalja) više nije odabran, pa se na iPhoneu vraća popis.
        .onChange(of: sessions.map(\.id)) { _, ids in
            if let selectedId, !ids.contains(selectedId) { self.selectedId = nil }
        }
    }

    private var sessionList: some View {
        List(selection: $selectedId) {
            if showsCalendar {
                Section {
                    CalendarMonthView(
                        month: $month, selectedDay: $selectedDay,
                        workoutDays: Set(visible.map { Calendar.current.startOfDay(for: $0.startedAt) })
                    )
                }
            }
            Section {
                ForEach(listed) { session in
                    NavigationLink(value: session.id) { SessionRow(session: session) }
                        .openInWindowMenu(DetailWindow.session, value: session.id)
                }
                // Poruka ide u popis ispod kalendara, ne preko cijelog ekrana.
                if showsCalendar && listed.isEmpty && !sessions.isEmpty {
                    Text(selectedDay == nil ? "U ovom mjesecu nema odrađenih treninga." : "Za odabrani dan nema odrađenih treninga.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "Još nema treninga",
                    systemImage: "clock",
                    description: Text("Ovdje će biti svi odrađeni treninzi.")
                )
            } else if listed.isEmpty && !showsCalendar {
                ContentUnavailableView(
                    "Nema treninga",
                    systemImage: "magnifyingglass",
                    description: Text("Nijedan trening ne odgovara filteru.")
                )
            }
        }
        .navigationTitle("Povijest")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showsCalendar ? "Popis" : "Kalendar", systemImage: showsCalendar ? "list.bullet" : "calendar") {
                    showsCalendar.toggle()
                    if !showsCalendar { selectedDay = nil }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
    }

    private var filterMenu: some View {
        Menu("Filter", systemImage: filter.kinds.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") {
            Section("Vrsta") {
                ForEach(WorkoutKind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { filter.kinds.contains(kind) },
                        set: { isOn in
                            if isOn { filter.kinds.insert(kind) } else { filter.kinds.remove(kind) }
                        }
                    ))
                }
            }
            Section("Datum") {
                Picker("Redoslijed", selection: $filter.sort) {
                    Text("Najnoviji prvi").tag(HistorySort.newestFirst)
                    Text("Najstariji prvi").tag(HistorySort.oldestFirst)
                }
            }
        }
    }
}

extension WorkoutKind {
    var title: LocalizedStringKey {
        switch self {
        case .strength: "Snaga"
        case .cardio: "Kardio"
        }
    }

    var symbol: String {
        switch self {
        case .strength: "dumbbell.fill"
        case .cardio: "figure.run"
        }
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(duration)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var duration: String {
        guard let end = session.endedAt else { return "" }
        return Duration.seconds(max(0, end.timeIntervalSince(session.startedAt)))
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

/// Mjesec s točkicom ispod dana u kojem je odrađen trening. Dodir na dan ga odabire, ponovni dodir poništava odabir.
private struct CalendarMonthView: View {
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let workoutDays: Set<Date>

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Prethodni mjesec", systemImage: "chevron.left") { shift(-1) }
                    .labelStyle(.iconOnly)
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button("Sljedeći mjesec", systemImage: "chevron.right") { shift(1) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)

            // Obični Grid umjesto LazyVGrida: lijena mreža unutar retka popisa smetala je pomicanju popisa.
            Grid(horizontalSpacing: 0, verticalSpacing: 6) {
                GridRow {
                    ForEach(weekdayHeaders, id: \.self) { symbol in
                        Text(symbol).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
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
        }
        .padding(.vertical, 4)
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let hasWorkout = workoutDays.contains(calendar.startOfDay(for: day))
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.body)
                Circle()
                    .fill(hasWorkout ? Color.accentColor : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.formatted(date: .complete, time: .omitted)))
        .accessibilityValue(hasWorkout ? Text("Ima trening") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Dani mjeseca, s praznim mjestima ispred prvog dana da stupci odgovaraju danima u tjednu.
    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: leading) + dates.map { Optional($0) }
    }

    /// Dani po tjednima, zadnji tjedan dopunjen praznim mjestima do sedam.
    private var weeks: [[Date?]] {
        let all = days
        return stride(from: 0, to: all.count, by: 7).map { start in
            let week = Array(all[start..<min(start + 7, all.count)])
            return week + Array(repeating: nil, count: 7 - week.count)
        }
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) {
            month = next
            selectedDay = nil
        }
    }
}
