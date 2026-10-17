import Foundation
import XCTest
@testable import DashboardCore

/// The Cyberpunk layout's job list, contacts, gauges and decrypt, over the Pi fixture
/// (generated 2026-10-14, New York).
final class CyberpunkTests: XCTestCase {
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    private func event(_ summary: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(summary: summary, start: date(start), end: date(end), isAllDay: allDay)
    }

    private func with(_ events: [CalendarEvent]) throws -> Snapshot {
        var s = try snapshot()
        s.sources.events?.data = events
        return s
    }

    func testTheDecryptLocksIntoTheText() {
        let text = "PARTLY CLOUDY"
        let seed = Cyberpunk.seed(text)
        XCTAssertEqual(Cyberpunk.decrypt(text, progress: 1, seed: seed, frame: 9), text)
        let start = Cyberpunk.decrypt(text, progress: 0, seed: seed, frame: 0)
        XCTAssertEqual(start.count, text.count)
        XCTAssertNotEqual(start, text)
        XCTAssertEqual(Array(start)[6], " ", "a space never scrambles")
        XCTAssertTrue(start.filter { $0 != " " }.allSatisfy { Cyberpunk.hex.contains($0) })
        XCTAssertEqual(Cyberpunk.decrypt(text, progress: 0.5, seed: seed, frame: 3),
                       Cyberpunk.decrypt(text, progress: 0.5, seed: seed, frame: 3))
    }

    func testTheHourSetsTheDistrict() {
        XCTAssertEqual(Cyberpunk.district(hour24: 0), "PACIFICA")
        XCTAssertEqual(Cyberpunk.district(hour24: 13), "WESTBROOK")
        XCTAssertEqual(Cyberpunk.district(hour24: 23), "WATSON")
    }

    func testTheNextJobIsTrackedAndOnesUnderWayAreActive() throws {
        let s = try with([
            event("Holiday", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true),
            event("Done", "2026-10-14T08:00:00-04:00", "2026-10-14T09:00:00-04:00"),
            event("Standup", "2026-10-14T10:00:00-04:00", "2026-10-14T10:30:00-04:00"),
            event("Lunch", "2026-10-14T12:00:00-04:00", "2026-10-14T13:00:00-04:00"),
            event("Dinner", "2026-10-14T19:00:00-04:00", "2026-10-14T21:00:00-04:00"),
            event("Dentist", "2026-10-15T09:00:00-04:00", "2026-10-15T10:00:00-04:00"),
        ])
        let jobs = Cyberpunk.jobs(s, now: date("2026-10-14T10:15:00-04:00"), limit: 6)
        XCTAssertEqual(jobs.map(\.event.summary), ["Holiday", "Standup", "Lunch", "Dinner", "Dentist"])
        XCTAssertEqual(jobs.map(\.state), [.allDay, .active, .tracked, .upcoming, .tomorrow])
    }

    func testTimedJobsComeBeforeAllDayOnesWhenRoomIsShort() throws {
        let s = try with([
            event("Holiday", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true),
            event("Standup", "2026-10-14T10:00:00-04:00", "2026-10-14T10:30:00-04:00"),
            event("Lunch", "2026-10-14T12:00:00-04:00", "2026-10-14T13:00:00-04:00"),
        ])
        let jobs = Cyberpunk.jobs(s, now: date("2026-10-14T09:00:00-04:00"), limit: 2)
        XCTAssertEqual(jobs.map(\.event.summary), ["Standup", "Lunch"])
        XCTAssertEqual(jobs.map(\.state), [.tracked, .upcoming])
        XCTAssertEqual(Cyberpunk.jobs(s, now: date("2026-10-14T09:00:00-04:00"), limit: 0), [])
    }

    func testContactsAreTheFortnightsBirthdays() throws {
        var s = try snapshot()
        s.sources.birthdays?.data = [
            Birthday(name: "Later", date: CivilDate(year: 2026, month: 10, day: 28)),
            Birthday(name: "Soon", date: CivilDate(year: 2026, month: 10, day: 16), age: 40),
            Birthday(name: "Past", date: CivilDate(year: 2026, month: 10, day: 13)),
            Birthday(name: "Edge", date: CivilDate(year: 2026, month: 10, day: 27)),
        ]
        let now = date("2026-10-14T12:00:00-04:00")
        XCTAssertEqual(Cyberpunk.contacts(s, now: now, limit: 3).map(\.name), ["Soon", "Edge"])
        XCTAssertEqual(Cyberpunk.contacts(s, now: now, limit: 1).map(\.name), ["Soon"])
    }

    func testTheGaugesStayOnTheirBars() {
        XCTAssertEqual(Cyberpunk.fraction(42, low: 35, high: 49), 0.5)
        XCTAssertEqual(Cyberpunk.fraction(60, low: 35, high: 49), 1)
        XCTAssertEqual(Cyberpunk.fraction(20, low: 35, high: 49), 0)
        XCTAssertEqual(Cyberpunk.fraction(40, low: 40, high: 40), 0.5)
        let rise = date("2026-10-14T07:00:00-04:00"), set = date("2026-10-14T19:00:00-04:00")
        XCTAssertEqual(Cyberpunk.daylight(now: date("2026-10-14T13:00:00-04:00"), rise: rise, set: set)!, 0.5, accuracy: 1e-9)
        XCTAssertNil(Cyberpunk.daylight(now: date("2026-10-14T21:00:00-04:00"), rise: rise, set: set))
    }
}
