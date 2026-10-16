import Foundation
import XCTest
@testable import DashboardCore

/// The Fuzzy Clock's words, as the Pi's `tests/test_fuzzyclock_panel.py` has them, and the
/// Weatherglass's instruments.
final class FuzzyClockTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func phrase(_ hour: Int, _ minute: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = newYork
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: hour, minute: minute))!
        return FuzzyClock.phrase(date, in: newYork)
    }

    func testEveryFiveMinutesOfAnHour() {
        XCTAssertEqual((0..<12).map { phrase(7, $0 * 5) }, [
            "seven o'clock", "five past seven", "ten past seven", "quarter past seven",
            "twenty past seven", "twenty five past seven", "half past seven",
            "twenty five to eight", "twenty to eight", "quarter to eight", "ten to eight",
            "five to eight",
        ])
    }

    func testMinutesSnapToTheNearestFive() {
        XCTAssertEqual(phrase(7, 2), "seven o'clock")
        XCTAssertEqual(phrase(7, 3), "five past seven")
        XCTAssertEqual(phrase(7, 32), "half past seven")
        XCTAssertEqual(phrase(8, 58), "nine o'clock")
    }

    func testMidnightAndNoon() {
        XCTAssertEqual(phrase(0, 0), "midnight")
        XCTAssertEqual(phrase(0, 2), "midnight")
        XCTAssertEqual(phrase(12, 1), "noon")
        XCTAssertEqual(phrase(11, 55), "five to twelve")
        XCTAssertEqual(phrase(0, 55), "five to one")
        XCTAssertEqual(phrase(23, 58), "twelve o'clock", "the Pi goes by the clock hour")
    }

    func testTheZoneIsTheDashboards() {
        let date = PythonISODate.parse("2026-03-23T19:30:00Z")!
        XCTAssertEqual(FuzzyClock.phrase(date, in: newYork), "half past three")
    }

    func testSegmentsColourMinutesAndHour() {
        let split = FuzzyClock.segments("twenty five to nine")
        XCTAssertEqual(split.map(\.text), ["twenty five", " to ", "nine"])
        XCTAssertEqual(split.map(\.ink), [.primary, .plain, .secondary])
        XCTAssertEqual(FuzzyClock.segments("seven o'clock").map(\.text), ["seven", " o'clock"])
        XCTAssertEqual(FuzzyClock.segments("noon").map(\.ink), [.primary])
    }
}

final class WeatherglassTests: XCTestCase {
    func testTheDialRunsFromLowerLeftOverTheTopToLowerRight() {
        XCTAssertEqual(Weatherglass.angle(hPa: 950), 225)
        XCTAssertEqual(Weatherglass.angle(hPa: 1000), 90)
        XCTAssertEqual(Weatherglass.angle(hPa: 1050), -45)
        XCTAssertEqual(Weatherglass.angle(hPa: 900), 225, "clamped")
        XCTAssertEqual(Weatherglass.angle(hPa: 1100), -45, "clamped")
    }

    func testTrendWords() {
        XCTAssertNil(Weatherglass.trend(1013, from: nil))
        XCTAssertEqual(Weatherglass.trend(1016, from: 1013), "RISING +3")
        XCTAssertEqual(Weatherglass.trend(1010, from: 1013), "FALLING -3")
        XCTAssertEqual(Weatherglass.trend(1013.8, from: 1013), "STEADY")
    }

    func testUVCategories() {
        XCTAssertEqual([0, 2.9, 3, 5.9, 6, 8, 11].map(Weatherglass.uvCategory),
                       ["LOW", "LOW", "MODERATE", "MODERATE", "HIGH", "VERY HIGH", "EXTREME"])
    }

    func testPressureFromThePi() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        let snapshot = try DashboardClient.validated(Data(contentsOf: url))
        XCTAssertNotNil(snapshot.sources.weather?.data?.pressure)
    }

    func testHistoryKeepsASampleEveryHalfHourAndTheLast48() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var history = PressureHistory()
        history.record(1010, at: t0)
        history.record(1011, at: t0.addingTimeInterval(600))
        XCTAssertEqual(history.samples.map(\.hPa), [1010], "ten minutes on is too soon")
        for k in 1...60 { history.record(1000 + Double(k), at: t0.addingTimeInterval(Double(k) * 1800)) }
        XCTAssertEqual(history.samples.count, 48)
        XCTAssertEqual(history.samples.last?.hPa, 1060)
    }

    func testTheTrendComparesWithTheOldestSampleOneTo36HoursOld() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let history = PressureHistory(samples: [
            .init(time: now.addingTimeInterval(-40 * 3600), hPa: 990),  // too old
            .init(time: now.addingTimeInterval(-30 * 3600), hPa: 1005),
            .init(time: now.addingTimeInterval(-3 * 3600), hPa: 1009),
            .init(time: now.addingTimeInterval(-1800), hPa: 1012),  // too recent
        ])
        XCTAssertEqual(history.previous(now: now), 1005)
        XCTAssertNil(PressureHistory(samples: [.init(time: now.addingTimeInterval(-600), hPa: 1)]).previous(now: now))
    }
}
