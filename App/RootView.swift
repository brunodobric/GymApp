import Models
import SwiftData
import SwiftUI

/// Glavna navigacija: pet tabova (specifikacija, odjeljak 3).
///
/// Pravila iz Apple HIG-a koja se ovdje primjenjuju:
/// * tab bar služi samo za navigaciju, akcije idu u toolbar;
/// * labele su jedna riječ, uz ispunjene SF Symbols;
/// * tabovi se nikad ne skrivaju ni onemogućuju, prazna sekcija objašnjava zašto je prazna;
/// * na iPadu se tab bar pretvara u sidebar (`.sidebarAdaptable`), na iPhoneu je dolje.
struct RootView: View {
    enum Section: Hashable {
        case home, history, schedules, exercises, statistics
    }

    @State private var selection: Section = .home
    @State private var showsOnboarding = false
    /// Zahtjev Početnoj iz tipkovničkog prečaca (⌘N, ⌘,).
    @State private var homeRequest: HomeRequest?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [UserSettings]

    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }

    /// Dok postavke ne postoje ili onboarding nije obavljen, prikazuje se onboarding.
    private var needsOnboarding: Bool { !(settings?.onboardingCompleted ?? false) }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Početna", systemImage: "house.fill", value: Section.home) {
                HomeScreen(request: $homeRequest)
            }
            Tab("Povijest", systemImage: "clock.fill", value: Section.history) {
                HistoryScreen()
            }
            Tab("Rasporedi", systemImage: "calendar", value: Section.schedules) {
                SchedulesScreen()
            }
            Tab("Vježbe", systemImage: "dumbbell.fill", value: Section.exercises) {
                ExercisesScreen()
            }
            Tab("Statistika", systemImage: "chart.bar.fill", value: Section.statistics) {
                StatisticsScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Prečaci iz izbornika (AppCommands) djeluju na prozor koji je u fokusu.
        .focusedSceneValue(\.rootActions, RootActions(
            select: { selection = $0 },
            request: { request in
                selection = .home
                homeRequest = request
            }
        ))
        // Dodir na Live Activity otvara Početnu i preko nje puni ekran aktivnog treninga.
        .onOpenURL { url in
            guard LiveActivityLink.isActiveWorkout(url) else { return }
            selection = .home
            homeRequest = .activeWorkout
        }
        .tint(settings?.accent.color ?? AccentChoice.blue.color)
        .preferredColorScheme(settings?.theme.colorScheme)
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingScreen()
                .tint(settings?.accent.color ?? AccentChoice.blue.color)
        }
        // Kratka odgoda: ako je onboarding potreban zbog brisanja podataka, list Postavki se prvo mora zatvoriti.
        .task(id: needsOnboarding) {
            if needsOnboarding { try? await Task.sleep(for: .milliseconds(600)) }
            showsOnboarding = needsOnboarding
        }
        .sheet(isPresented: Binding(
            get: { notificationSchedule != nil },
            set: { if !$0 { NotificationRouter.shared.openScheduleId = nil } }
        )) {
            if let schedule = notificationSchedule {
                UpcomingWorkoutSheet(schedule: schedule) { NotificationRouter.shared.openScheduleId = nil }
            }
        }
        .task {
            PendingTemplateFromSession.discardLeftover(context: context)
            ReminderScheduler.refresh(context: context)
            PhoneWatchSync.shared.refreshContext()
            await HealthService.shared.importNewData(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            // Satu se šalju svježi treninzi i postavke, i kad korisnik izađe iz aplikacije nakon izmjena.
            if phase != .inactive { PhoneWatchSync.shared.refreshContext() }
            // Izvan aplikacije kraj odmora može biti alarm u Dynamic Islandu, pa se zakazuje iznova.
            if phase == .background { WorkoutLiveUpdates.shared.appDidEnterBackground() }
            guard phase == .active else { return }
            ReminderScheduler.refresh(context: context)
            // Trening započet na satu dok je iPhone bio zaključan dobiva Live Activity tek sad:
            // sustav je dopušta pokrenuti samo dok je aplikacija otvorena.
            WorkoutLiveUpdates.shared.refresh()
            // Novi treninzi, težina i visina iz Zdravlja (samo ako je korisnik povezao Zdravlje).
            Task { await HealthService.shared.importNewData(context: context) }
        }
    }
}

extension RootView {
    /// Raspored iz dodirnutog podsjetnika (ako još postoji).
    private var notificationSchedule: Schedule? {
        guard let id = NotificationRouter.shared.openScheduleId else { return nil }
        var descriptor = FetchDescriptor<Schedule>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

#Preview {
    RootView()
}
