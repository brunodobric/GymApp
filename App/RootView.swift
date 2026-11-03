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
        .fullScreenCover(isPresented: Binding(get: { needsOnboarding }, set: { _ in })) {
            OnboardingScreen()
                .tint(settings?.accent.color ?? AccentChoice.blue.color)
        }
        .task { ReminderScheduler.refresh(context: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ReminderScheduler.refresh(context: context) }
        }
    }
}

#Preview {
    RootView()
}
