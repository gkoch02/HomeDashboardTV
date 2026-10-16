import Foundation
import XCTest
@testable import DashboardCore

/// The Skylight layout's sky and text, over the Pi fixture (generated 2026-10-14, New York).
final class SkylightTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    private func event(_ summary: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(summary: summary, start: date(start), end: date(end), isAllDay: allDay)
    }

    func testTheSkyFollowsTheSunThroughTheDay() throws {
        let s = try snapshot()
        let night = Skylight.sky(s, now: date("2026-10-14T01:00:00-04:00"))
        XCTAssertTrue(night.isNight)
        XCTAssertLessThan(night.sunPath, 0)
        let noon = Skylight.sky(s, now: date("2026-10-14T13:00:00-04:00"))
        XCTAssertFalse(noon.isNight)
        XCTAssertGreaterThan(noon.altitude, 20)
        XCTAssertEqual(noon.sunPath, 0.5, accuracy: 0.1)
        let late = Skylight.sky(s, now: date("2026-10-14T21:00:00-04:00"))
        XCTAssertGreaterThan(late.sunPath, 1)
    }

    func testPartlyCloudyIsDryWithSomeCloud() throws {
        let sky = Skylight.sky(try snapshot(), now: date("2026-10-14T13:00:00-04:00"))
        XCTAssertEqual(sky.precip, .none)
        XCTAssertEqual(sky.intensity, 0)
        XCTAssertGreaterThan(sky.cover, 0.2)
        XCTAssertLessThan(sky.cover, 0.5)
        XCTAssertFalse(sky.hidesBodies)
    }

    func testRainHidesTheSunAndFallsHarderWithMoreWater() throws {
        var s = try snapshot()
        s.sources.weather?.data?.currentIcon = "10d"
        let sky = Skylight.sky(s, now: date("2026-10-14T13:00:00-04:00"))
        XCTAssertEqual(sky.precip, .rain)
        XCTAssertGreaterThan(sky.intensity, 0)
        XCTAssertTrue(sky.hidesBodies)
        XCTAssertLessThan(Skylight.precipIntensity(mm: 0.2, showers: false),
                          Skylight.precipIntensity(mm: 4, showers: false))
        XCTAssertEqual(Skylight.precipIntensity(mm: 40, showers: false), 1)
        XCTAssertEqual(Skylight.precipIntensity(mm: 0, showers: false), 0.2)
    }

    func testTheWindBlowsAwayFromWhereItComesFrom() throws {
        let weather = try XCTUnwrap(try snapshot().sources.weather?.data)
        var w = weather
        w.windDeg = 270  // a west wind blows east: right
        w.windSpeed = 20
        XCTAssertEqual(Skylight.drift(w, isMetric: false), 0.894, accuracy: 0.01)
        w.windDeg = 90
        XCTAssertLessThan(Skylight.drift(w, isMetric: false), 0)
        w.windDeg = 0  // a north wind has no sideways push, but the sky still drifts
        XCTAssertEqual(abs(Skylight.drift(w, isMetric: false)), 0.08, accuracy: 1e-9)
        w.windDeg = nil
        XCTAssertEqual(Skylight.drift(w, isMetric: false), 0.2)
    }

    func testTheMoonIsUpBetweenItsRiseAndSet() throws {
        let s = try snapshot()  // rises 11:26, sets 20:15
        XCTAssertNil(Skylight.moon(s, now: date("2026-10-14T09:00:00-04:00")))
        let up = try XCTUnwrap(Skylight.moon(s, now: date("2026-10-14T15:50:00-04:00")))
        XCTAssertEqual(up.path, 0.5, accuracy: 0.01)
        XCTAssertGreaterThan(up.fraction, 0)
        XCTAssertLessThan(up.fraction, 0.5, "waxing")
        XCTAssertNil(Skylight.moon(s, now: date("2026-10-14T21:00:00-04:00")))
    }

    func testAMorningSetBelongsToLastNightsMoon() throws {
        var s = try snapshot()
        s.moon?.rise = date("2026-10-14T20:00:00-04:00")
        s.moon?.set = date("2026-10-14T07:00:00-04:00")
        let morning = try XCTUnwrap(Skylight.moon(s, now: date("2026-10-14T06:00:00-04:00")))
        XCTAssertGreaterThan(morning.path, 0.9)
        XCTAssertNil(Skylight.moon(s, now: date("2026-10-14T12:00:00-04:00")))
        let evening = try XCTUnwrap(Skylight.moon(s, now: date("2026-10-14T21:00:00-04:00")))
        XCTAssertLessThan(evening.path, 0.1)
    }

    func testWithoutMoonTimesTheTransitPlacesIt() throws {
        var s = try snapshot()
        s.moon?.rise = nil
        s.moon?.set = nil
        let transit = try XCTUnwrap(Horizon.moonTransit(on: CivilDate(year: 2026, month: 10, day: 14),
                                                        moon: try XCTUnwrap(s.moon), zone: newYork))
        let at = try XCTUnwrap(Skylight.moon(s, now: transit.time))
        XCTAssertEqual(at.path, 0.5, accuracy: 1e-6)
        XCTAssertNil(Skylight.moon(s, now: transit.time.addingTimeInterval(-8 * 3600)))
    }

    func testTheRibbonStartsNowAndRunsADay() throws {
        let s = try snapshot()
        let weather = try XCTUnwrap(s.sources.weather?.data)
        let now = date("2026-10-14T07:30:00-04:00")
        let points = Skylight.ribbon(weather, now: now)
        XCTAssertEqual(points.count, 9)
        XCTAssertTrue(points[0].isNow)
        XCTAssertEqual(points[0].temp, weather.currentTemp)
        XCTAssertFalse(points.dropFirst().contains(where: \.isNow))
        XCTAssertGreaterThan(points[1].time, now.addingTimeInterval(3600), "a slot an hour away doubles the now point")
        XCTAssertLessThanOrEqual(try XCTUnwrap(points.last).time, now.addingTimeInterval(25 * 3600))
        XCTAssertEqual(points.map(\.time), points.map(\.time).sorted())
    }

    func testSunTimesCoverTodayAndTomorrowInOrder() throws {
        let times = Skylight.sunTimes(try snapshot(), now: date("2026-10-14T12:00:00-04:00"))
        XCTAssertEqual(times.map(\.rise), [true, false, true, false])
        XCTAssertEqual(times.map(\.time), times.map(\.time).sorted())
    }

    func testUpNextLeadsWithWhatIsOnAndStopsAfterTomorrow() throws {
        var s = try snapshot()
        s.sources.events?.data = [
            event("Done", "2026-10-14T08:00:00-04:00", "2026-10-14T09:00:00-04:00"),
            event("Later", "2026-10-14T15:00:00-04:00", "2026-10-14T16:00:00-04:00"),
            event("On now", "2026-10-14T09:30:00-04:00", "2026-10-14T11:00:00-04:00"),
            event("Holiday", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true),
            event("Tomorrow", "2026-10-15T09:00:00-04:00", "2026-10-15T10:00:00-04:00"),
            event("Too far", "2026-10-16T09:00:00-04:00", "2026-10-16T10:00:00-04:00"),
        ]
        let now = date("2026-10-14T10:00:00-04:00")
        XCTAssertEqual(Skylight.upNext(s, now: now, limit: 5).map(\.summary), ["On now", "Later", "Tomorrow"])
        XCTAssertEqual(Skylight.upNext(s, now: now, limit: 1).map(\.summary), ["On now"])
        XCTAssertEqual(Skylight.allDay(s, now: now).map(\.summary), ["Holiday"])
    }

    func testWhenReadsAtAGlance() {
        let now = date("2026-10-14T10:00:00-04:00")
        func when(_ start: String) -> String {
            Skylight.when(event("E", start, "2026-10-16T00:00:00-04:00"), now: now, zone: newYork)
        }
        XCTAssertEqual(when("2026-10-14T09:00:00-04:00"), "Now")
        XCTAssertEqual(when("2026-10-14T10:25:00-04:00"), "In 25 min")
        XCTAssertEqual(when("2026-10-14T12:00:00-04:00"), "In 2 h")
        XCTAssertEqual(when("2026-10-14T11:30:00-04:00"), "In 1.5 h")
        XCTAssertEqual(when("2026-10-14T15:30:00-04:00"), "3:30p")
        XCTAssertEqual(when("2026-10-15T09:00:00-04:00"), "Tomorrow 9a")
    }
}
