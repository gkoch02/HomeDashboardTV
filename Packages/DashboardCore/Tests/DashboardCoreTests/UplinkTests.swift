import Foundation
import XCTest
@testable import DashboardCore

/// The Uplink layout's orbit, voice trace, narration and signal, over the Pi fixture
/// (generated 2026-10-14, New York).
final class UplinkTests: XCTestCase {
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    private func event(_ summary: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(summary: summary, start: date(start), end: date(end), isAllDay: allDay)
    }

    func testTheOrbitTurnsAroundNow() {
        let now = date("2026-10-14T12:00:00-04:00")
        XCTAssertEqual(Uplink.turn(now, now: now), 0)
        XCTAssertEqual(Uplink.turn(date("2026-10-14T18:00:00-04:00"), now: now), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Uplink.turn(date("2026-10-14T06:00:00-04:00"), now: now), -0.25, accuracy: 1e-9)
        XCTAssertEqual(Uplink.turn(date("2026-10-15T00:00:00-04:00"), now: now), -0.5, accuracy: 1e-9)
        XCTAssertEqual(Uplink.turn(date("2026-10-15T15:00:00-04:00"), now: now), 0.125, accuracy: 1e-9)
    }

    func testNodesAreWhatIsUnderWayOrComing() throws {
        var s = try snapshot()
        s.sources.events?.data = [
            event("Holiday", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true),
            event("Done", "2026-10-14T08:00:00-04:00", "2026-10-14T09:00:00-04:00"),
            event("Standup", "2026-10-14T10:00:00-04:00", "2026-10-14T13:00:00-04:00"),
            event("Dinner", "2026-10-14T18:00:00-04:00", "2026-10-14T21:00:00-04:00"),
            event("Far", "2026-10-15T09:00:00-04:00", "2026-10-15T10:00:00-04:00"),
        ]
        let nodes = Uplink.nodes(s, now: date("2026-10-14T12:00:00-04:00"))
        XCTAssertEqual(nodes.map(\.event.summary), ["Standup", "Dinner"])
        XCTAssertTrue(nodes[0].isActive)
        XCTAssertEqual(nodes[0].start, 0)
        XCTAssertEqual(nodes[0].end, 1.0 / 24, accuracy: 1e-9)
        XCTAssertEqual(nodes[1].start, 0.25, accuracy: 1e-9)
        XCTAssertEqual(nodes[1].end, 0.375, accuracy: 1e-9)
    }

    func testTheTraceRunsThroughTheRibbon() throws {
        let weather = try XCTUnwrap(try snapshot().sources.weather?.data)
        let now = date("2026-10-14T12:00:00-04:00")
        let ribbon = Skylight.ribbon(weather, now: now)
        let trace = Uplink.trace(weather, now: now, count: 49)
        XCTAssertEqual(trace.count, 49)
        XCTAssertEqual(trace[0].temp, ribbon[0].temp)
        let lo = ribbon.map(\.temp).min()!, hi = ribbon.map(\.temp).max()!
        XCTAssertTrue(trace.allSatisfy { $0.temp >= lo - 1e-9 && $0.temp <= hi + 1e-9 })
        XCTAssertTrue(trace.allSatisfy { (0...1).contains($0.precip) })
    }

    func testTheNarratorReadsAtAPace() {
        XCTAssertEqual(Uplink.narration(words: 5), 4)
        XCTAssertEqual(Uplink.narration(words: 19), 6, accuracy: 1e-9)
        XCTAssertEqual(Uplink.narration(words: 200), 14)
        XCTAssertEqual(Uplink.spoken(words: 10, progress: 0), 0)
        XCTAssertEqual(Uplink.spoken(words: 10, progress: 0.31), 4)
        XCTAssertEqual(Uplink.spoken(words: 10, progress: 2), 10)
    }

    func testTheSignalIsTheShareOfCurrentSources() throws {
        var s = try snapshot().sources
        s.events?.staleness = .fresh
        s.weather?.staleness = .aging
        s.birthdays?.staleness = .fresh
        s.airQuality = Source(fetchedAt: nil, staleness: .fresh, data: nil)
        XCTAssertEqual(Uplink.signal(s), 5)
        s.weather?.staleness = .expired
        XCTAssertEqual(Uplink.signal(s), 4)
        s.airQuality = nil
        XCTAssertEqual(Uplink.signal(s), 3)
        XCTAssertEqual(Uplink.signal(Sources()), 0)
    }
}
