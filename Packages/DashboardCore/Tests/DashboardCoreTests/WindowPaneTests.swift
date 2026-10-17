import Foundation
import XCTest
@testable import DashboardCore

/// The Window layout's pane and lamps, over the Pi fixture (generated 2026-10-14, New York).
final class WindowPaneTests: XCTestCase {
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    func testAPartlyCloudyMorningLeavesTheGlassAlmostDry() throws {
        let glass = WindowPane.glass(try snapshot(), now: date("2026-10-14T09:00:00-04:00"))
        XCTAssertEqual(glass.wet, 0.02)
        XCTAssertEqual(glass.snow, 0)
        XCTAssertEqual(glass.frost, 0, "42 °F is above freezing")
        XCTAssertEqual(glass.mist, 0, "65 % humidity leaves no mist")
        XCTAssertFalse(glass.storm)
        XCTAssertGreaterThan(glass.altitude, 0)
    }

    func testRainWetsThePaneByHowHardItFalls() {
        XCTAssertEqual(WindowPane.wetness(raining: true, intensity: 0), 0.35)
        XCTAssertEqual(WindowPane.wetness(raining: true, intensity: 1), 1)
        XCTAssertEqual(WindowPane.wetness(raining: true, intensity: 3), 1)
        XCTAssertEqual(WindowPane.wetness(raining: false, intensity: 1), 0.02)
    }

    func testFrostCreepsInBelowFreezing() {
        XCTAssertEqual(WindowPane.frost(celsius: 5), 0)
        XCTAssertEqual(WindowPane.frost(celsius: 1), 0)
        XCTAssertEqual(WindowPane.frost(celsius: -2), 0.5, accuracy: 0.001)
        XCTAssertEqual(WindowPane.frost(celsius: -5), 1)
        XCTAssertEqual(WindowPane.frost(celsius: -20), 1)
    }

    func testFogAndDampAirMistTheGlass() {
        XCTAssertEqual(WindowPane.mist(humidity: 99, fog: true), 0.55)
        XCTAssertEqual(WindowPane.mist(humidity: 70, fog: false), 0)
        XCTAssertEqual(WindowPane.mist(humidity: 100, fog: false), 0.3, accuracy: 0.001)
        XCTAssertEqual(WindowPane.mist(humidity: nil, fog: false), 0)
    }

    func testFirefliesComeOutOnWarmDrySummerNights() {
        XCTAssertEqual(WindowPane.fireflies(celsius: 22, dry: true, altitude: -15, month: 7), 1)
        XCTAssertEqual(WindowPane.fireflies(celsius: 16, dry: true, altitude: -15, month: 7), 0.5, accuracy: 0.001)
        XCTAssertEqual(WindowPane.fireflies(celsius: 22, dry: true, altitude: -15, month: 10), 0, "not in October")
        XCTAssertEqual(WindowPane.fireflies(celsius: 22, dry: false, altitude: -15, month: 7), 0, "not in the rain")
        XCTAssertEqual(WindowPane.fireflies(celsius: 22, dry: true, altitude: 10, month: 7), 0, "not by day")
        XCTAssertEqual(WindowPane.fireflies(celsius: 10, dry: true, altitude: -15, month: 7), 0, "not on a cold night")
        XCTAssertEqual(WindowPane.fireflies(celsius: nil, dry: true, altitude: -15, month: 7), 0)
    }

    func testTheLampsAreTheNextEventsAndTheWeeksBirthday() throws {
        let lamps = WindowPane.lamps(try snapshot(), now: date("2026-10-15T15:20:00-04:00"))
        XCTAssertEqual(lamps.events.map(\.summary), ["Coffee with Sam", "Bug Triage", "Sprint Retro"])
        XCTAssertEqual(lamps.birthday?.name, "Mom")
    }

    func testABirthdayGetsALampFromSixDaysBefore() throws {
        let s = try snapshot()
        XCTAssertEqual(WindowPane.lamps(s, now: date("2026-10-26T09:00:00-04:00")).birthday?.name, "Alice", "today")
        XCTAssertEqual(WindowPane.lamps(s, now: date("2026-10-27T09:00:00-04:00")).birthday?.name, "Bob", "six days off")
        XCTAssertNil(WindowPane.lamps(s, now: date("2026-11-02T09:00:00-04:00")).birthday, "none left")
    }
}
