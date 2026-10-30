import Foundation
import XCTest
@testable import DashboardCore

/// The Ephemeris pair's strip, lanes, daylight, hour labels and check line, over the Pi fixture
/// (generated 2026-10-14, New York).
final class EphemerisTests: XCTestCase {
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    private func event(_ summary: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(summary: summary, start: date(start), end: date(end), isAllDay: allDay)
    }

    func testTheWindowRunsFromAnHourBack() {
        let now = date("2026-10-14T12:00:00-04:00")
        let window = Ephemeris.Window(now: now)
        XCTAssertEqual(window.start, date("2026-10-14T11:00:00-04:00"))
        XCTAssertEqual(window.end, date("2026-10-15T11:00:00-04:00"))
        XCTAssertEqual(window.fraction(now), 1.0 / 24, accuracy: 1e-9)
        XCTAssertEqual(window.fraction(date("2026-10-14T23:00:00-04:00")), 0.5, accuracy: 1e-9)
    }

    func testSpansAreClampedAndKnowWhereTheyStand() throws {
        var s = try snapshot()
        s.sources.events?.data = [
            event("Holiday", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true),
            event("Long gone", "2026-10-14T08:00:00-04:00", "2026-10-14T09:00:00-04:00"),
            event("Lunch", "2026-10-14T10:30:00-04:00", "2026-10-14T11:30:00-04:00"),
            event("Standup", "2026-10-14T11:45:00-04:00", "2026-10-14T13:00:00-04:00"),
            event("Dinner", "2026-10-14T18:00:00-04:00", "2026-10-14T21:00:00-04:00"),
            event("Gym", "2026-10-15T07:00:00-04:00", "2026-10-15T08:00:00-04:00"),
            event("Late", "2026-10-15T10:30:00-04:00", "2026-10-15T12:00:00-04:00"),
            event("Beyond", "2026-10-15T13:00:00-04:00", "2026-10-15T14:00:00-04:00"),
        ]
        let now = date("2026-10-14T12:00:00-04:00")
        let spans = Ephemeris.spans(s, now: now, window: Ephemeris.Window(now: now))
        XCTAssertEqual(spans.map(\.event.summary), ["Lunch", "Standup", "Dinner", "Gym", "Late"])
        XCTAssertEqual(spans.map(\.state), [.past, .active, .next, .later, .later])
        XCTAssertEqual(spans[0].start, 0)
        XCTAssertEqual(spans[0].end, 0.5 / 24, accuracy: 1e-9)
        XCTAssertEqual(spans[2].start, 7.0 / 24, accuracy: 1e-9)
        XCTAssertEqual(spans[4].end, 1)
    }

    func testLanesKeepRoomForALabel() {
        let lanes = Ephemeris.lanes([(0.10, 0.20), (0.15, 0.30), (0.21, 0.22), (0.25, 0.40), (0.26, 0.27), (0.5, 0.6)],
                                  minLength: 0.05, count: 2)
        XCTAssertEqual(lanes, [0, 1, 0, nil, 0, 0])
        XCTAssertEqual(Ephemeris.lanes([(0, 1)], minLength: 0.1, count: 0), [nil])
    }

    func testDaylightIsCutAtTheStripsEdges() {
        let now = date("2026-10-14T12:00:00-04:00")
        let window = Ephemeris.Window(now: now)
        let times: [(time: Date, rise: Bool)] = [
            (date("2026-10-14T07:00:00-04:00"), true), (date("2026-10-14T18:00:00-04:00"), false),
            (date("2026-10-15T07:00:00-04:00"), true), (date("2026-10-15T18:00:00-04:00"), false),
        ]
        let stretches = Ephemeris.daylight(times, window: window)
        XCTAssertEqual(stretches.count, 2)
        XCTAssertEqual(stretches[0].lowerBound, 0)
        XCTAssertEqual(stretches[0].upperBound, 7.0 / 24, accuracy: 1e-9)
        XCTAssertEqual(stretches[1].lowerBound, 20.0 / 24, accuracy: 1e-9)
        XCTAssertEqual(stretches[1].upperBound, 1)
        // Starting with a set: the strip began in daylight.
        let fromSet = Ephemeris.daylight(Array(times.dropFirst()), window: window)
        XCTAssertEqual(fromSet.first?.lowerBound, 0)
        XCTAssertTrue(Ephemeris.daylight([], window: window).isEmpty)
    }

    func testHoursAreTheZonesOwn() throws {
        let now = date("2026-10-14T12:10:00-04:00")
        let window = Ephemeris.Window(now: now)
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let hours = Ephemeris.hours(in: window, zone: kolkata)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kolkata
        XCTAssertEqual(hours.count, 24)
        XCTAssertTrue(hours.allSatisfy { cal.component(.minute, from: $0) == 0 })
        XCTAssertTrue(hours.allSatisfy { $0 >= window.start && $0 < window.end })
        XCTAssertEqual(hours.first, date("2026-10-14T11:30:00-04:00"))
        let york = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(Ephemeris.hours(in: window, zone: york).first, date("2026-10-14T12:00:00-04:00"))
    }

    func testTheTraceStaysOnTheStrip() throws {
        let weather = try XCTUnwrap(try snapshot().sources.weather?.data)
        let now = date("2026-10-14T12:00:00-04:00")
        let window = Ephemeris.Window(now: now)
        let trace = Ephemeris.trace(weather, now: now, window: window)
        XCTAssertFalse(trace.isEmpty)
        XCTAssertTrue(trace.allSatisfy { (0...1).contains(window.fraction($0.time)) })
        XCTAssertTrue(trace.first?.isNow == true)
    }

    func testLabelsStepByWhatFits() {
        XCTAssertEqual(Ephemeris.labelStep(hourWidth: 105, minSpacing: 90), 1)
        XCTAssertEqual(Ephemeris.labelStep(hourWidth: 75, minSpacing: 90), 2)
        XCTAssertEqual(Ephemeris.labelStep(hourWidth: 40, minSpacing: 90), 3)
        XCTAssertEqual(Ephemeris.labelStep(hourWidth: 5, minSpacing: 90), 6)
    }

    func testTheCheckLineNamesWhatIsStale() {
        func source<V>(_ staleness: Staleness) -> Source<V> { Source(fetchedAt: nil, staleness: staleness, data: nil) }
        var sources = Sources(events: source(.fresh), weather: source(.aging), birthdays: nil, airQuality: source(.fresh))
        XCTAssertEqual(Ephemeris.stale(sources), [])
        sources.weather = source(.stale)
        sources.airQuality = source(.expired)
        XCTAssertEqual(Ephemeris.stale(sources), ["Weather", "Air"])
    }
}
