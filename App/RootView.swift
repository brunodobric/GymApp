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
    }
}

#Preview {
    RootView()
}
