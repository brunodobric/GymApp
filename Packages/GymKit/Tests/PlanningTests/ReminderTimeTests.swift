import Foundation
import Testing
@testable import Planning

@Suite("Vrijeme podsjetnika")
struct ReminderTimeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zagreb")!
        return calendar
    }

    @Test("Minute od ponoći u datum i natrag")
    func roundTrip() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        for minutes in [0, 7 * 60 + 30, 18 * 60 + 5, 23 * 60 + 59] {
            let date = ReminderTime.date(fromMinutes: minutes, on: day, calendar: calendar)
            #expect(ReminderTime.minutes(from: date, calendar: calendar) == minutes)
        }
    }

    @Test("Vrijeme izvan dana se ograničava na dan")
    func clamps() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ReminderTime.minutes(from: ReminderTime.date(fromMinutes: -5, on: day, calendar: calendar), calendar: calendar) == 0)
        #expect(ReminderTime.minutes(from: ReminderTime.date(fromMinutes: 2000, on: day, calendar: calendar), calendar: calendar) == 1439)
    }

    @Test("Dan se uključuje i isključuje, a popis ostaje sortiran")
    func toggling() {
        #expect(ReminderTime.toggling(2, in: [4, 6]) == [2, 4, 6])
        #expect(ReminderTime.toggling(4, in: [2, 4, 6]) == [2, 6])
        #expect(ReminderTime.toggling(1, in: []) == [1])
        #expect(ReminderTime.weekdaysFromMonday.first == 2 && ReminderTime.weekdaysFromMonday.last == 1)
    }
}
