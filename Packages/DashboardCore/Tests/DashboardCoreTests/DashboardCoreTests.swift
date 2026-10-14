import Foundation
import XCTest
@testable import DashboardCore

/// `Fixtures/snapshot.json` is real output of the Pi's `/api/dashboard`, rendered from
/// HomeDashboard's dummy data in America/New_York on 2026-10-14 (generated_at 03:27 local),
/// with the Pi's coordinates set to New York so the moon block carries rise and set.
final class DashboardCoreTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private let newYork = TimeZone(identifier: "America/New_York")!

    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func minimal(sources: [String: Any] = [:], schema: Int = 1) -> [String: Any] {
        [
            "schema_version": schema,
            "generated_at": "2026-10-14T09:00:00-04:00",
            "timezone": "America/New_York",
            "utc_offset_seconds": -14400,
            "units": "imperial",
            "quote": ["text": "t", "author": "a"],
            "sources": sources,
        ]
    }

    // MARK: Decoding

    func testDecodesThePiFixture() throws {
        let snapshot = try DashboardClient.validated(fixture())
        XCTAssertEqual(snapshot.timeZone, newYork)
        XCTAssertEqual(snapshot.sources.events?.staleness, .fresh)
        XCTAssertFalse(try XCTUnwrap(snapshot.sources.events?.data).isEmpty)
        XCTAssertEqual(snapshot.sources.weather?.data?.forecast.isEmpty, false)
        XCTAssertEqual(snapshot.sources.birthdays?.data?.first?.name, "Mom")
        XCTAssertNil(snapshot.sources.airQuality, "the fixture's Pi has PurpleAir off")
    }

    func testPythonTimestampsKeepTheirMicrosecondsAndOffset() {
        let parsed = date("2026-10-14T01:42:13.553625-04:00")
        XCTAssertEqual(parsed.timeIntervalSince1970, 1_791_956_533.553625, accuracy: 0.000_01)
        XCTAssertEqual(date("2026-10-14T05:42:13+00:00"), date("2026-10-14T01:42:13-04:00"))
    }

    func testNaiveTimestampReadsAsUTC() {
        XCTAssertEqual(date("2026-10-14T05:42:13"), date("2026-10-14T05:42:13+00:00"))
    }

    func testExpiredSourceDecodesWithNoData() throws {
        let body = minimal(sources: [
            "weather": ["fetched_at": "2026-09-01T00:00:00+00:00", "staleness": "expired", "data": NSNull()],
        ])
        let weather = try XCTUnwrap(Snapshot.decode(json(body)).sources.weather)
        XCTAssertEqual(weather.staleness, .expired)
        XCTAssertNil(weather.data)
    }

    func testUnknownStalenessLevelDoesNotFailThePayload() throws {
        let body = minimal(sources: [
            "birthdays": ["fetched_at": NSNull(), "staleness": "ancient", "data": NSNull()],
        ])
        XCTAssertEqual(try Snapshot.decode(json(body)).sources.birthdays?.staleness, .unknown)
    }

    func testNewerSchemaIsRefused() throws {
        XCTAssertThrowsError(try DashboardClient.validated(json(minimal(schema: 2)))) { error in
            XCTAssertEqual(error as? DashboardClientError, .unsupportedSchema(2))
        }
    }

    func testZoneFallsBackToTheOffsetWhenThePiIsOnLocal() throws {
        var body = minimal()
        body["timezone"] = NSNull()
        body["utc_offset_seconds"] = 3600
        let snapshot = try Snapshot.decode(json(body))
        XCTAssertEqual(snapshot.timeZone(local: newYork).secondsFromGMT(), 3600,
                       "a TV in another zone falls back to the Pi's offset")
    }

    func testLocalPiUsesTheTVsZoneWhenTheyAgree() throws {
        var body = minimal()
        body["timezone"] = NSNull()  // generated_at is -04:00, New York's October offset
        let zone = try Snapshot.decode(json(body)).timeZone(local: newYork)
        XCTAssertEqual(zone, newYork, "the named zone keeps DST for next week's days")
    }

    // MARK: Agenda

    private func event(_ summary: String, _ start: String, _ end: String, allDay: Bool = false) -> [String: Any] {
        ["summary": summary, "start": start, "end": end, "is_all_day": allDay]
    }

    private func snapshot(events: [[String: Any]], birthdays: [[String: Any]] = []) throws -> Snapshot {
        try Snapshot.decode(json(minimal(sources: [
            "events": ["fetched_at": "2026-10-14T09:00:00-04:00", "staleness": "fresh", "data": events],
            "birthdays": ["fetched_at": "2026-10-14T09:00:00-04:00", "staleness": "fresh", "data": birthdays],
        ])))
    }

    func testAgendaPlacesEventsOnTheirDayInTheDashboardZone() throws {
        // 23:30 in New York is already the next day in UTC; it must stay on the 14th.
        let s = try snapshot(events: [event("Late", "2026-10-14T23:30:00-04:00", "2026-10-14T23:59:00-04:00")])
        let days = Agenda.days(from: s, now: date("2026-10-14T12:00:00-04:00"), count: 2)
        XCTAssertEqual(days.map(\.day), [CivilDate(year: 2026, month: 10, day: 14), CivilDate(year: 2026, month: 10, day: 15)])
        XCTAssertEqual(days[0].events.map(\.summary), ["Late"])
        XCTAssertTrue(days[1].events.isEmpty)
    }

    func testAllDayEventDoesNotSpillPastMidnight() throws {
        let s = try snapshot(events: [
            event("Holiday", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true),
        ])
        let days = Agenda.days(from: s, now: date("2026-10-14T08:00:00-04:00"), count: 2)
        XCTAssertEqual(days[0].events.map(\.summary), ["Holiday"])
        XCTAssertTrue(days[1].events.isEmpty)
    }

    func testMultiDayEventShowsOnEveryDayItCovers() throws {
        let s = try snapshot(events: [
            event("Trip", "2026-10-14T00:00:00-04:00", "2026-10-17T00:00:00-04:00", allDay: true),
        ])
        let days = Agenda.days(from: s, now: date("2026-10-14T08:00:00-04:00"), count: 4)
        XCTAssertEqual(days.map(\.events.count), [1, 1, 1, 0])
    }

    func testAllDayEventsComeFirstThenByStart() throws {
        let s = try snapshot(events: [
            event("Lunch", "2026-10-14T12:00:00-04:00", "2026-10-14T13:00:00-04:00"),
            event("Standup", "2026-10-14T09:00:00-04:00", "2026-10-14T09:15:00-04:00"),
            event("Holiday", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true),
        ])
        let days = Agenda.days(from: s, now: date("2026-10-14T08:00:00-04:00"), count: 1)
        XCTAssertEqual(days[0].events.map(\.summary), ["Holiday", "Standup", "Lunch"])
    }

    func testBirthdaysLandOnTheirDayAndUpcomingSkipsThePast() throws {
        let s = try snapshot(events: [], birthdays: [
            ["name": "Ada", "date": "2026-10-15", "age": 36],
            ["name": "Old", "date": "2026-10-01", "age": NSNull()],
        ])
        let now = date("2026-10-14T08:00:00-04:00")
        XCTAssertEqual(Agenda.days(from: s, now: now, count: 2)[1].birthdays.map(\.name), ["Ada"])
        XCTAssertEqual(Agenda.upcomingBirthdays(from: s, now: now).map(\.name), ["Ada"])
    }

    // MARK: Demo shift

    func testDemoShiftMovesTheWeekToToday() throws {
        let s = try DashboardClient.validated(fixture())
        let now = date("2026-11-02T10:00:00-05:00")  // across the DST change, 19 days on
        let shifted = s.shiftedToToday(now: now)
        XCTAssertEqual(CivilDate(shifted.generatedAt, in: newYork), CivilDate(year: 2026, month: 11, day: 2))
        let original = try XCTUnwrap(s.sources.events?.data?.first)
        let moved = try XCTUnwrap(shifted.sources.events?.data?.first)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = newYork
        XCTAssertEqual(cal.component(.hour, from: moved.start), cal.component(.hour, from: original.start),
                       "a whole-day shift keeps the wall-clock time across DST")
        XCTAssertEqual(shifted.sources.birthdays?.data?.first?.date, CivilDate(year: 2026, month: 11, day: 5))
    }

    // MARK: Client

    func testTypedAddressGetsSchemeAndDefaultPort() {
        XCTAssertEqual(DashboardClient.baseURL(forTyped: "dashboard.local")?.absoluteString, "http://dashboard.local:8080/")
        XCTAssertEqual(DashboardClient.baseURL(forTyped: " 192.168.1.20:9000 ")?.absoluteString, "http://192.168.1.20:9000/")
        XCTAssertEqual(DashboardClient.baseURL(forTyped: "https://pi.example:443")?.absoluteString, "https://pi.example:443/")
        XCTAssertNil(DashboardClient.baseURL(forTyped: "   "))
    }

    func testRequestCarriesBasicAuthOnlyWithCredentials() {
        let base = URL(string: "http://pi.local:8080/")!
        XCTAssertNil(DashboardClient(baseURL: base).request.value(forHTTPHeaderField: "Authorization"))
        let authed = DashboardClient(baseURL: base, username: "admin", password: "pw").request
        XCTAssertEqual(authed.value(forHTTPHeaderField: "Authorization"), "Basic YWRtaW46cHc=")
        XCTAssertEqual(authed.url?.absoluteString, "http://pi.local:8080/api/dashboard")
    }

    func testAQIBandsFollowTheEPABreakpoints() throws {
        func band(_ aqi: Int) throws -> AirQuality.Band {
            let body = minimal(sources: [
                "air_quality": ["fetched_at": "2026-10-14T09:00:00-04:00", "staleness": "fresh",
                                "data": ["aqi": aqi, "category": "x", "pm25": 1.0]],
            ])
            return try XCTUnwrap(Snapshot.decode(json(body)).sources.airQuality?.data).band
        }
        XCTAssertEqual(try [0, 50, 51, 100, 101, 150, 151, 200, 201, 300, 301, 500].map(band),
                       [.good, .good, .moderate, .moderate, .sensitive, .sensitive,
                        .unhealthy, .unhealthy, .veryUnhealthy, .veryUnhealthy, .hazardous, .hazardous])
    }

    func testAQIShortLabelsFitTheBadge() throws {
        let body = minimal(sources: [
            "air_quality": ["fetched_at": "2026-10-14T09:00:00-04:00", "staleness": "fresh",
                            "data": ["aqi": 128, "category": "Unhealthy for Sensitive Groups", "pm25": 47.0]],
        ])
        let airQuality = try XCTUnwrap(Snapshot.decode(json(body)).sources.airQuality?.data)
        XCTAssertEqual(airQuality.shortLabel, "Sensitive groups", "the Pi's category is too long for the badge")
    }

    func testShortLocationIsTheFirstLine() throws {
        let s = try snapshot(events: [
            event("Faire", "2026-10-14T00:00:00-04:00", "2026-10-15T00:00:00-04:00", allDay: true)
                .merging(["location": "Casa de Fruta\n10021 Pacheco Pass Hwy, Hollister"]) { $1 },
            event("Call", "2026-10-14T09:00:00-04:00", "2026-10-14T10:00:00-04:00")
                .merging(["location": "  \nZoom"]) { $1 },
        ])
        XCTAssertEqual(s.sources.events?.data?.map(\.shortLocation), ["Casa de Fruta", "Zoom"])
    }

    // MARK: Moon

    func testMoonBlockDecodes() throws {
        let moon = try XCTUnwrap(DashboardClient.validated(fixture()).moon)
        XCTAssertEqual(moon.phaseName, "Waxing Crescent")
        XCTAssertEqual(moon.days.count, 7)
        XCTAssertEqual(moon.today?.date, CivilDate(year: 2026, month: 10, day: 14))
        XCTAssertNotNil(moon.rise)
        XCTAssertEqual(moon.next.kind, "full")
        XCTAssertEqual(moon.next.date, CivilDate(year: 2026, month: 10, day: 26))
    }

    func testOlderPiWithoutMoonStillDecodes() throws {
        XCTAssertNil(try Snapshot.decode(json(minimal())).moon)
    }

    private func area(_ points: [CGPoint]) -> Double {
        guard points.count > 2 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += Double(a.x * b.y - b.x * a.y)
        }
        return abs(sum) / 2
    }

    func testLitOutlineEnclosesTheLitShare() {
        for fraction in [0.05, 0.124, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9] {
            let lit = area(MoonGeometry.litOutline(fraction: fraction, samples: 400)) / .pi
            XCTAssertEqual(lit, MoonGeometry.litShare(fraction: fraction), accuracy: 0.002, "fraction \(fraction)")
        }
        XCTAssertTrue(MoonGeometry.litOutline(fraction: 0).isEmpty, "new moon")
    }

    func testWaxingLightsTheRightLimbAndWaningTheLeft() {
        let waxing = MoonGeometry.litOutline(fraction: 0.15)
        let waning = MoonGeometry.litOutline(fraction: 0.85)
        XCTAssertGreaterThan(waxing.map(\.x).reduce(0, +), 0)
        XCTAssertLessThan(waning.map(\.x).reduce(0, +), 0)
    }

    func testMoonPhaseShareMatchesThePiIllumination() throws {
        // The Pi's illumination is the same cosine, so the drawn area agrees with the number.
        for day in try XCTUnwrap(DashboardClient.validated(fixture()).moon).days {
            XCTAssertEqual(MoonGeometry.litShare(fraction: day.fraction) * 100, day.illumination, accuracy: 0.6)
        }
    }

    func testCompactTimeMatchesThePi() {
        XCTAssertEqual(CompactTime.string(date("2026-10-14T11:26:20-04:00"), in: newYork), "11:26a")
        XCTAssertEqual(CompactTime.string(date("2026-10-14T14:00:00-04:00"), in: newYork), "2p")
        XCTAssertEqual(CompactTime.string(date("2026-10-14T00:05:00-04:00"), in: newYork), "12:05a")
    }

    func testDemoShiftMovesTheMoonDays() throws {
        let s = try DashboardClient.validated(fixture())
        let shifted = s.shiftedToToday(now: date("2026-10-20T10:00:00-04:00"))
        XCTAssertEqual(shifted.moon?.today?.date, CivilDate(year: 2026, month: 10, day: 20))
        XCTAssertEqual(shifted.moon?.next.date, CivilDate(year: 2026, month: 11, day: 1))
    }

    // MARK: Halftone

    func testHalftoneRollsOverOnlyAfterDuskWithNothingLeft() throws {
        let s = try snapshot(events: [
            event("Dinner", "2026-10-14T19:30:00-04:00", "2026-10-14T21:00:00-04:00"),
            event("Breakfast", "2026-10-15T08:00:00-04:00", "2026-10-15T09:00:00-04:00"),
        ])
        // No weather, so dusk is 18:00. Before it: today.
        XCTAssertFalse(Agenda.halftoneDay(from: s, now: date("2026-10-14T17:00:00-04:00")).isTomorrow)
        // After dusk but dinner still on: today.
        XCTAssertFalse(Agenda.halftoneDay(from: s, now: date("2026-10-14T20:00:00-04:00")).isTomorrow)
        // After dusk and dinner done: tomorrow, with tomorrow's events.
        let late = Agenda.halftoneDay(from: s, now: date("2026-10-14T21:30:00-04:00"))
        XCTAssertTrue(late.isTomorrow)
        XCTAssertEqual(late.day.events.map(\.summary), ["Breakfast"])
    }

    func testHalftoneDoesNotRollOverAtMiddayWhenTheDayIsDone() throws {
        let s = try snapshot(events: [event("Standup", "2026-10-14T09:00:00-04:00", "2026-10-14T09:15:00-04:00")])
        XCTAssertFalse(Agenda.halftoneDay(from: s, now: date("2026-10-14T10:30:00-04:00")).isTomorrow)
    }

    func testHalftoneSceneMapsIconsAndTones() {
        let size = CGSize(width: 900, height: 640)
        let clear = HalftoneScene(icon: "01d", size: size)
        XCTAssertEqual(clear.kind, .clear)
        XCTAssertFalse(clear.night)
        let (c, r) = try! XCTUnwrap(clear.body)
        XCTAssertLessThan(clear.tone(at: c), 0.1, "the sun's face is near paper")
        XCTAssertEqual(clear.rays.count, 12)
        let tips = clear.rays.map { hypot($0[1].x - c.x, $0[1].y - c.y) / r }
        XCTAssertEqual(tips.max() ?? 0, 1.9, accuracy: 0.001, "long rays")
        XCTAssertEqual(tips.min() ?? 0, 1.5, accuracy: 0.001, "short rays")
        let reach = clear.rays.flatMap { $0 }
        XCTAssertTrue(reach.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x <= 900 && $0.y <= 640 }, "no ray leaves the pane")
        XCTAssertTrue(HalftoneScene(icon: "01n", size: size).rays.isEmpty, "the moon has no rays")
        XCTAssertEqual(HalftoneScene(icon: "10n", size: size).kind, .rain)
        XCTAssertGreaterThan(HalftoneScene(icon: "01n", size: size).tone(at: CGPoint(x: 20, y: 20)), 0.7, "the night sky is dark")
        XCTAssertNil(HalftoneScene(icon: "04d", size: size).body, "overcast hides the sun")
        XCTAssertEqual(HalftoneScene(icon: "11d", size: size).bolt.count, 7)
        for kind in HalftoneScene.Kind.allCases {
            let scene = HalftoneScene(kind: kind, night: false, size: size)
            for x in stride(from: 0.0, through: 900, by: 37) {
                for y in stride(from: 0.0, through: 640, by: 41) {
                    let t = scene.tone(at: CGPoint(x: x, y: y))
                    XCTAssert((0...1).contains(t), "\(kind) tone \(t) out of range")
                }
            }
        }
    }

    func testWeatherSymbols() {
        XCTAssertEqual(WeatherSymbol.name(for: "01d"), "sun.max.fill")
        XCTAssertEqual(WeatherSymbol.name(for: "01n"), "moon.stars.fill")
        XCTAssertEqual(WeatherSymbol.name(for: "zz"), "thermometer.medium")
    }
}
