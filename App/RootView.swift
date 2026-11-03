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
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [UserSettings]

    private var settings: UserSettings? { settingsList.first }

    /// Dok postavke ne postoje ili onboarding nije obavljen, prikazuje se onboarding.
    private var needsOnboarding: Bool { !(settings?.onboardingCompleted ?? false) }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Početna", systemImage: "house.fill", value: Section.home) {
                HomeScreen()
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
        .task {
            ReminderScheduler.refresh(context: context)
            PhoneWatchSync.shared.refreshContext()
            await HealthService.shared.importNewData(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            // Satu se šalju svježi treninzi i postavke, i kad korisnik izađe iz aplikacije nakon izmjena.
            if phase != .inactive { PhoneWatchSync.shared.refreshContext() }
            guard phase == .active else { return }
            ReminderScheduler.refresh(context: context)
            // Novi treninzi, težina i visina iz Zdravlja (samo ako je korisnik povezao Zdravlje).
            Task { await HealthService.shared.importNewData(context: context) }
        }
    }
}

#Preview {
    RootView()
}
