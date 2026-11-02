import Models
import SwiftData
import SwiftUI
import Stats
import Units

/// Povijest odrađenih treninga: popis s filterom i sortiranjem te kalendar s točkicama.
struct HistoryScreen: View {
    @Query(filter: #Predicate<Session> { $0.stateRaw == "finished" }, sort: \Session.startedAt, order: .reverse)
    private var sessions: [Session]
    @Query private var settingsList: [UserSettings]

    @State private var filter = HistoryFilter()
    @State private var showsCalendar = false
    @State private var selectedDay: Date?
    @State private var month = Date()

    private var unit: WeightUnit { settingsList.first?.weightUnit ?? .kilograms }
    private var visible: [Session] { filter.apply(to: sessions) }

    /// Popis ispod kalendara: samo treninzi odabranog dana.
    private var listed: [Session] {
        guard showsCalendar, let selectedDay else { return visible }
        return visible.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: selectedDay) }
    }

    var body: some View {
        NavigationStack {
            List {
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
                        NavigationLink(value: session) { SessionRow(session: session) }
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
                } else if listed.isEmpty {
                    ContentUnavailableView(
                        "Nema treninga",
                        systemImage: "magnifyingglass",
                        description: Text(showsCalendar ? "Za odabrani dan nema odrađenih treninga." : "Nijedan trening ne odgovara filteru.")
                    )
                }
            }
            .navigationTitle("Povijest")
            .navigationDestination(for: Session.self) { SessionDetailScreen(session: $0, unit: unit) }
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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdayHeaders, id: \.self) { symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
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
        .accessibilityValue(hasWorkout ? Text("Ima trening") : Text(""))
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

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) {
            month = next
            selectedDay = nil
        }
    }
}
