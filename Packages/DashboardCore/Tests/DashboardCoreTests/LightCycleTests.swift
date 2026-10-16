import Foundation
import XCTest
@testable import DashboardCore

/// The Light Cycle dial's numbers, over the Pi fixture (generated 2026-10-14, New York).
final class LightCycleTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let day = CivilDate(year: 2026, month: 10, day: 14)
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    private func event(_ summary: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(summary: summary, start: date(start), end: date(end), isAllDay: allDay)
    }

    func testHoursAreClockHoursInTheDashboardZone() {
        XCTAssertEqual(LightCycle.hour(date("2026-10-14T13:30:00-04:00"), in: newYork), 13.5, accuracy: 1e-9)
        XCTAssertEqual(LightCycle.hour(date("2026-10-14T13:30:00-04:00"), in: TimeZone(identifier: "UTC")!),
                       17.5, accuracy: 1e-9)
    }

    func testSpansClipToTheDayAndSkipAllDayEvents() {
        let spans = LightCycle.spans([
            event("Overnight", "2026-10-13T22:00:00-04:00", "2026-10-14T01:00:00-04:00"),
            event("Conference", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true),
            event("Late", "2026-10-14T23:00:00-04:00", "2026-10-15T02:00:00-04:00"),
            event("Tomorrow", "2026-10-15T09:00:00-04:00", "2026-10-15T10:00:00-04:00"),
        ], on: day, zone: newYork)
        XCTAssertEqual(spans.map(\.event.summary), ["Overnight", "Late"])
        XCTAssertEqual(spans[0].start, 0)
        XCTAssertEqual(spans[0].end, 1, accuracy: 1e-9)
        XCTAssertEqual(spans[1].start, 23, accuracy: 1e-9)
        XCTAssertEqual(spans[1].end, 24)
    }

    func testOverlapsTakeTheInnerLaneAndInstantsGetASliver() {
        let spans = LightCycle.spans([
            event("A", "2026-10-14T09:00:00-04:00", "2026-10-14T10:00:00-04:00"),
            event("B", "2026-10-14T09:30:00-04:00", "2026-10-14T11:00:00-04:00"),
            event("C", "2026-10-14T10:00:00-04:00", "2026-10-14T10:00:00-04:00"),
        ], on: day, zone: newYork)
        XCTAssertEqual(spans.map(\.lane), [0, 1, 0])
        XCTAssertEqual(spans[2].end - spans[2].start, 1.0 / 6, accuracy: 1e-9)
    }

    func testTheBandSamplesTheWholeDay() throws {
        let sun = SunModel(snapshot: try snapshot())
        let altitudes = LightCycle.altitudes(sun, on: day)
        XCTAssertEqual(altitudes.count, 24 * 6 + 1)
        XCTAssertLessThan(altitudes[0], -18, "midnight is night")
        XCTAssertGreaterThan(altitudes[12 * 6], 20, "noon is day")
    }

    func testSunTimesComeFromTheHorizonCrossings() throws {
        let sun = SunModel(snapshot: try snapshot())
        let times = try XCTUnwrap(LightCycle.sunTimes(sun, on: day))
        XCTAssertEqual(sun.altitude(at: times.rise), -0.833, accuracy: 0.05)
        XCTAssertEqual(sun.altitude(at: times.set), -0.833, accuracy: 0.05)
        XCTAssertLessThan(times.rise, times.set)
    }

    func testDaylightPrefersTheAltitudesOverTheWeather() throws {
        let snapshot = try snapshot()
        let exact = SunModel(snapshot: snapshot)
        XCTAssertEqual(LightCycle.daylight(snapshot, sun: exact, on: day)?.rise,
                       LightCycle.sunTimes(exact, on: day)?.rise)
        let fallback = SunModel(weather: snapshot.sources.weather?.data, zone: newYork)
        XCTAssertEqual(LightCycle.daylight(snapshot, sun: fallback, on: day)?.rise, date("2026-10-14T06:24:00-04:00"))
        XCTAssertNil(LightCycle.daylight(snapshot, sun: fallback, on: day.adding(days: 1)), "the weather's are today's only")
    }

    func testOctoberDaysShortenAndTheFallbackArcSaysNothing() throws {
        let snapshot = try snapshot()
        let change = try XCTUnwrap(LightCycle.dayLengthChange(SunModel(snapshot: snapshot), from: day))
        XCTAssertLessThan(change, -60)
        XCTAssertGreaterThan(change, -240)
        let fallback = SunModel(weather: snapshot.sources.weather?.data, zone: newYork)
        XCTAssertNil(LightCycle.dayLengthChange(fallback, from: day))
    }

    func testFormatsMatchThePanel() {
        XCTAssertEqual(LightCycle.formatChange(112), "+1m 52s")
        XCTAssertEqual(LightCycle.formatChange(-125), "−2m 05s")
        XCTAssertEqual(LightCycle.formatLength(12 * 3600 + 54 * 60 + 10), "12h 54m")
    }
}
