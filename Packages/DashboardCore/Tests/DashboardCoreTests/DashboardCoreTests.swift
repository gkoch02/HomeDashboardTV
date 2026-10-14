import Foundation
import XCTest
@testable import DashboardCore

/// `Fixtures/snapshot.json` is real output of the Pi's `/api/dashboard`, rendered from
/// HomeDashboard's dummy data in America/New_York on 2026-10-14 (generated_at 01:42 local).
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

    func testWeatherSymbols() {
        XCTAssertEqual(WeatherSymbol.name(for: "01d"), "sun.max.fill")
        XCTAssertEqual(WeatherSymbol.name(for: "01n"), "moon.stars.fill")
        XCTAssertEqual(WeatherSymbol.name(for: "zz"), "thermometer.medium")
    }
}
