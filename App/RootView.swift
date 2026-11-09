import Models
import SwiftData
import SwiftUI
import WidgetData

/// Glavna navigacija: pet tabova (specifikacija, odjeljak 3).
///
/// Pravila iz Apple HIG-a koja se ovdje primjenjuju:
/// * tab bar služi samo za navigaciju, akcije idu u toolbar;
/// * labele su jedna riječ, uz ispunjene SF Symbols;
/// * tabovi se nikad ne skrivaju ni onemogućuju, prazna sekcija objašnjava zašto je prazna;
/// * odlazak na drugi tab čuva stanje navigacije, a ponovni dodir na otvoren tab vraća ga na korijen;
/// * na iPadu se tab bar pretvara u sidebar (`.sidebarAdaptable`), na iPhoneu je dolje.
struct RootView: View {
    enum Section: Hashable {
        case home, history, schedules, exercises, statistics
    }

    @State private var selection: Section = .home
    /// Brojač ponovnih dodira po tabu. Promjena vraća tab na korijen, a odlazak na drugi tab čuva stanje.
    @State private var rootResets: [Section: Int] = [:]
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
        TabView(selection: tabSelection) {
            Tab("Početna", systemImage: "house.fill", value: Section.home) {
                HomeScreen(rootReset: rootResets[.home, default: 0], request: $homeRequest)
            }
            Tab("Povijest", systemImage: "clock.fill", value: Section.history) {
                HistoryScreen(rootReset: rootResets[.history, default: 0])
            }
            Tab("Rasporedi", systemImage: "calendar", value: Section.schedules) {
                SchedulesScreen(rootReset: rootResets[.schedules, default: 0])
            }
            Tab("Vježbe", systemImage: "dumbbell.fill", value: Section.exercises) {
                ExercisesScreen(rootReset: rootResets[.exercises, default: 0])
            }
            Tab("Statistika", systemImage: "chart.bar.fill", value: Section.statistics) {
                StatisticsScreen(rootReset: rootResets[.statistics, default: 0])
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
        // Dodir na Live Activity otvara Početnu i preko nje puni ekran aktivnog treninga,
        // a widgeti otvaraju Početnu, pregled tjedna, težinu ili zadnji trening.
        .onOpenURL { url in
            guard let link = WidgetLink(url: url) else { return }
            selection = .home
            homeRequest = HomeRequest(link)
        }
        // Gumb ▶ na widgetu i kontrola "Započni trening" (intent se izvršava u aplikaciji).
        .onChange(of: AppRequestRouter.shared.pending, initial: true) {
            guard let pending = AppRequestRouter.shared.take() else { return }
            selection = .home
            homeRequest = pending
        }
        // Podaci s drugih uređaja (iCloud) ne prolaze kroz spremanje u ovoj aplikaciji: widgeti se osvježe nakon uvoza.
        .onChange(of: SyncMonitor.shared.tracker.lastImport) {
            WidgetRefresher.shared.scheduleRefresh()
        }
        // Trening pokrenut iz Prečaca, Sirija ili Action buttona otvara se kao dodir na Live Activity.
        // `initial`: pri hladnom pokretanju akcija može završiti prije nego što se prozor prikaže.
        .onChange(of: IntentRouter.shared.opensActiveWorkout, initial: true) { _, opens in
            guard opens else { return }
            IntentRouter.shared.opensActiveWorkout = false
            selection = .home
            homeRequest = .activeWorkout
        }
        .appAccent(settings?.accent)
        .preferredColorScheme(settings?.theme.colorScheme)
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingScreen()
                .appAccent(settings?.accent)
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
            GymAppShortcuts.updateAppShortcutParameters()
            ReminderScheduler.refresh(context: context)
            PhoneWatchSync.shared.refreshContext()
            await LegacyCardioPlans.removeFromWatch()
            await HealthService.shared.importNewData(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            // Satu se šalju svježi treninzi i postavke, i kad korisnik izađe iz aplikacije nakon izmjena.
            if phase != .inactive { PhoneWatchSync.shared.refreshContext() }
            // Prečaci nude spremljene treninge kao parametar fraze ("Započni Push u Apolonu"). Osvježava se
            // pri izlasku iz aplikacije, pa vrijede i novi, preimenovani i obrisani treninzi.
            if phase == .background { GymAppShortcuts.updateAppShortcutParameters() }
            // Widgeti dobivaju svježu snimku i kad se nije ništa spremilo (npr. novi dan dok je aplikacija bila zatvorena).
            if phase == .background { WidgetRefresher.shared.refresh() }
            guard phase == .active else { return }
            ReminderScheduler.refresh(context: context)
            WidgetRefresher.shared.scheduleRefresh()
            // Trening započet na satu dok je iPhone bio zaključan dobiva Live Activity tek sad:
            // sustav je dopušta pokrenuti samo dok je aplikacija otvorena.
            WorkoutLiveUpdates.shared.refresh()
            // Novi treninzi, težina i visina iz Zdravlja (samo ako je korisnik povezao Zdravlje).
            Task { await HealthService.shared.importNewData(context: context) }
        }
    }
}

extension RootView {
    /// Odabir taba. Dodir na tab koji je već otvoren vraća ga na korijen (Apple HIG),
    /// a ostali tabovi zadržavaju gdje je korisnik stao.
    private var tabSelection: Binding<Section> {
        Binding(
            get: { selection },
            set: { tapped in
                if tapped == selection { rootResets[tapped, default: 0] += 1 }
                selection = tapped
            }
        )
    }

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
