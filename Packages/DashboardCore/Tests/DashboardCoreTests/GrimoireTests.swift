import Foundation
import XCTest
@testable import DashboardCore

/// The Grimoire layout's watches, quest log, feast days, moon lines, dragon's breath and
/// candles, over the Pi fixture (generated 2026-10-14, New York).
final class GrimoireTests: XCTestCase {
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    private func event(_ summary: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(summary: summary, start: date(start), end: date(end), isAllDay: allDay)
    }

    func testTheWatchesFollowTheSun() {
        // Sunrise at 6:24, sunset at 19:51: noon between them at 13:07.
        let rise = 6.4, set = 19.85
        XCTAssertEqual(Grimoire.watch(hour: 0.5, rise: rise, set: set), "The Witching Hour")
        XCTAssertEqual(Grimoire.watch(hour: 3, rise: rise, set: set), "The Small Hours")
        XCTAssertEqual(Grimoire.watch(hour: 6, rise: rise, set: set), "Dawn")
        XCTAssertEqual(Grimoire.watch(hour: 9, rise: rise, set: set), "Morning")
        XCTAssertEqual(Grimoire.watch(hour: 13, rise: rise, set: set), "High Noon")
        XCTAssertEqual(Grimoire.watch(hour: 16, rise: rise, set: set), "Afternoon")
        XCTAssertEqual(Grimoire.watch(hour: 20, rise: rise, set: set), "Dusk")
        XCTAssertEqual(Grimoire.watch(hour: 21.5, rise: rise, set: set), "Evening")
        XCTAssertEqual(Grimoire.watch(hour: 22.5, rise: rise, set: set), "Nightfall")
        XCTAssertEqual(Grimoire.watch(hour: 23.5, rise: rise, set: set), "The Witching Hour")
        // Without a sun, the day turns at half past six.
        XCTAssertEqual(Grimoire.watch(hour: 7), "Dawn")
        XCTAssertEqual(Grimoire.watch(hour: 12.5), "High Noon")
        XCTAssertEqual(Grimoire.watch(hour: 18), "Dusk")
    }

    func testTheWatchReadsTheWeathersSun() throws {
        let s = try snapshot()
        XCTAssertEqual(Grimoire.watch(s, now: date("2026-10-14T13:00:00-04:00")), "High Noon")
        XCTAssertEqual(Grimoire.watch(s, now: date("2026-10-14T19:30:00-04:00")), "Dusk")
    }

    func testTheDateLineIsAChroniclers() {
        let zone = TimeZone(identifier: "America/New_York")!
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(Grimoire.dateLine(date("2026-10-14T12:00:00-04:00"), zone: zone, locale: locale), "Wednesday, the 14th of October")
        XCTAssertEqual(Grimoire.dateLine(date("2026-11-01T12:00:00-04:00"), zone: zone, locale: locale), "Sunday, the 1st of November")
        XCTAssertEqual(Grimoire.dateLine(date("2026-10-22T12:00:00-04:00"), zone: zone, locale: locale), "Thursday, the 22nd of October")
    }

    func testTheQuestLogLeadsWithWhatIsUnderWay() throws {
        var s = try snapshot()
        s.sources.events?.data = [
            event("Conference", "2026-10-14T00:00:00-04:00", "2026-10-17T00:00:00-04:00", allDay: true),
            event("Done", "2026-10-14T08:00:00-04:00", "2026-10-14T09:00:00-04:00"),
            event("Standup", "2026-10-14T11:30:00-04:00", "2026-10-14T12:30:00-04:00"),
            event("Yoga", "2026-10-14T17:30:00-04:00", "2026-10-14T18:30:00-04:00"),
            event("Dinner", "2026-10-14T19:00:00-04:00", "2026-10-14T21:00:00-04:00"),
            event("Planning", "2026-10-15T10:00:00-04:00", "2026-10-15T11:00:00-04:00"),
            event("Far", "2026-10-16T10:00:00-04:00", "2026-10-16T11:00:00-04:00"),
        ]
        let now = date("2026-10-14T12:00:00-04:00")
        let quests = Grimoire.quests(s, now: now, limit: 8)
        XCTAssertEqual(quests.map(\.event.summary), ["Conference", "Standup", "Yoga", "Dinner", "Planning"])
        XCTAssertEqual(quests.map(\.state), [.daily, .underway, .next, .today, .tomorrow])
        // Short of room, the timed quests come first and the dailies fill what is left.
        XCTAssertEqual(Grimoire.quests(s, now: now, limit: 4).map(\.event.summary), ["Standup", "Yoga", "Dinner", "Planning"])
        XCTAssertEqual(Grimoire.quests(s, now: now, limit: 0), [])
    }

    func testFeastDaysAreTheMonthsBirthdays() throws {
        let s = try snapshot()
        let zone = s.timeZone
        let feasts = Grimoire.feasts(s, now: date("2026-10-14T12:00:00-04:00"), limit: 5)
        XCTAssertEqual(feasts.map(\.birthday.name), ["Mom", "Jake", "Alice", "Bob"])
        XCTAssertEqual(feasts.map(\.daysAway), [3, 7, 12, 18])
        XCTAssertEqual(Grimoire.feastWhen(feasts[0], zone: zone), "In 3 days")
        XCTAssertEqual(Grimoire.feastWhen(feasts[1], zone: zone), "Wed, Oct 21")
        XCTAssertEqual(Grimoire.feasts(s, now: date("2026-10-14T12:00:00-04:00"), days: 10, limit: 5).map(\.birthday.name), ["Mom", "Jake"])
        let today = Grimoire.feasts(s, now: date("2026-10-17T08:00:00-04:00"), limit: 1)[0]
        XCTAssertEqual(today.daysAway, 0)
        XCTAssertEqual(Grimoire.feastWhen(today, zone: zone), "Today")
    }

    func testTheMoonLines() throws {
        var moon = try XCTUnwrap(try snapshot().moon)
        XCTAssertEqual(Grimoire.moonLine(moon), "Waxing Crescent, 14% lit")
        XCTAssertEqual(Grimoire.nextMoon(moon), "Full moon in 12 days")
        moon.next.days = 1
        XCTAssertEqual(Grimoire.nextMoon(moon), "Full moon tomorrow")
        moon.next.days = 0
        moon.next.kind = "new"
        XCTAssertEqual(Grimoire.nextMoon(moon), "New moon tonight")
    }

    func testTheDragonsBreath() {
        XCTAssertEqual(Grimoire.breath(.good), "Sweet")
        XCTAssertEqual(Grimoire.breath(.sensitive), "Sour")
        XCTAssertEqual(Grimoire.breath(.hazardous), "Deadly")
    }

    func testTheCandlesBurnWhileTheDataIsCurrent() throws {
        var s = try snapshot().sources
        s.events?.staleness = .fresh
        s.weather?.staleness = .aging
        s.birthdays?.staleness = .expired
        s.airQuality = nil
        let candles = Grimoire.candles(s)
        XCTAssertEqual(candles.map(\.name), ["Calendar", "Weather", "Birthdays"])
        XCTAssertEqual(candles.map(\.candle), [.lit, .guttering, .out])
        XCTAssertEqual(Grimoire.candle(.unknown), .out)
        XCTAssertTrue(Grimoire.candles(Sources()).isEmpty)
    }
}
