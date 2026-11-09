import Foundation
import Testing
@testable import Stats

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// Petak 15. 1. 2027., 08:00 UTC.
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400

private func point(daysAgo: Double) -> ExercisePoint {
    ExercisePoint(date: now.addingTimeInterval(-daysAgo * day), bestWeightKg: 50, bestReps: 8, estimatedOneRepMaxKg: nil, volumeKg: 400)
}

@Suite("Raspon grafa napretka")
struct ChartRangeTests {
    private let points = [400, 200, 70, 45, 20, 3, 0].map { point(daysAgo: $0) }

    @Test func allKeepsEveryPoint() {
        #expect(ChartRange.all.interval(now: now, calendar: utc) == nil)
        #expect(ChartRange.all.filter(points, now: now, calendar: utc).count == points.count)
    }

    @Test func monthsCountBackFromStartOfToday() throws {
        let interval = try #require(ChartRange.months(1).interval(now: now, calendar: utc))
        // 15. 12. 2026. u ponoć do sada.
        #expect(interval.start == utc.date(from: DateComponents(year: 2026, month: 12, day: 15)))
        #expect(interval.end == now)
        #expect(ChartRange.months(1).filter(points, now: now, calendar: utc).count == 3)
        #expect(ChartRange.months(2).filter(points, now: now, calendar: utc).count == 4)
        #expect(ChartRange.months(6).filter(points, now: now, calendar: utc).count == 5)
        #expect(ChartRange.months(12).filter(points, now: now, calendar: utc).count == 6)
    }

    @Test func customIncludesWholeDaysAndSwapsReversedDates() throws {
        let from = now.addingTimeInterval(-45 * day).addingTimeInterval(3600)
        let to = now.addingTimeInterval(-20 * day).addingTimeInterval(-3600)
        let range = ChartRange.custom(from: to, to: from)
        let interval = try #require(range.interval(now: now, calendar: utc))
        #expect(interval.start == utc.startOfDay(for: from))
        #expect(interval.end < utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: to))!)
        #expect(range.filter(points, now: now, calendar: utc).map(\.date) == [point(daysAgo: 45).date, point(daysAgo: 20).date])
    }
}
