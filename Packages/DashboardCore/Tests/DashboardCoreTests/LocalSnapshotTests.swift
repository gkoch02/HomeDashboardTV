import Foundation
import XCTest
@testable import DashboardCore

/// The snapshot made without a Pi. The astronomy is checked against values from the Pi's own
/// Python (`src/render/moon.py`, `src/astronomy.py` at HomeDashboard a5dd200) and against the
/// moon and sun blocks of `Fixtures/snapshot.json`, which the Pi made for New York on
/// 2026-10-14. The `open-meteo-*` fixtures are real Open-Meteo answers for New York, recorded
/// at 23:30 on Thursday 2026-10-29 there.
final class LocalSnapshotTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let nyc = LocalSnapshot.Place(name: "New York", latitude: 40.7128, longitude: -74.006, timezone: "America/New_York")

    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func civil(_ iso: String) -> CivilDate {
        let p = iso.split(separator: "-").map { Int($0)! }
        return CivilDate(year: p[0], month: p[1], day: p[2])
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // MARK: Astronomy against the Pi

    private struct Case {
        var date: String, zone: String, lat: Double, lon: Double
        var name: String, supermoon: Bool
        var full: (String, Int), new: (String, Int)
        var rise: TimeInterval?, set: TimeInterval?
    }

    private let cases = [
        Case(date: "2026-10-14", zone: "America/New_York", lat: 40.7128, lon: -74.006,
             name: "Waxing Crescent", supermoon: false, full: ("2026-10-26", 12), new: ("2026-11-09", 26),
             rise: 1791991580.053711, set: 1792023353.979492),
        // The spring-forward day, with no moonrise.
        Case(date: "2026-03-08", zone: "America/Los_Angeles", lat: 37.77, lon: -122.42,
             name: "Waning Gibbous", supermoon: false, full: ("2026-04-01", 24), new: ("2026-03-18", 10),
             rise: nil, set: 1772988618.969726),
        Case(date: "2027-01-01", zone: "Europe/London", lat: 51.5, lon: -0.12, name: "Third Quarter", supermoon: false,
             full: ("2027-01-22", 21), new: ("2027-01-07", 6),
             rise: 1798768478.979492, set: 1798803376.977539),
        Case(date: "2026-06-21", zone: "Australia/Sydney", lat: -33.87, lon: 151.21, name: "First Quarter", supermoon: false,
             full: ("2026-06-30", 9), new: ("2026-07-14", 23),
             rise: 1782004932.055664, set: 1782048744.946289),
        Case(date: "2026-12-24", zone: "Asia/Tokyo", lat: 35.68, lon: 139.69, name: "Full Moon", supermoon: true,
             full: ("2027-01-22", 29), new: ("2027-01-08", 15),
             rise: 1798097357.006836, set: 1798063055.053711),
    ]

    func testMoonPhaseMatchesThePi() {
        let day = civil("2026-10-14")
        XCTAssertEqual(Astronomy.moonAge(on: day), 3.6526218529792973, accuracy: 1e-9)
        XCTAssertEqual(Astronomy.moonFraction(on: day), 0.12368943028159265, accuracy: 1e-11)
        XCTAssertEqual(Astronomy.moonIllumination(on: day), 14.354727516860688, accuracy: 1e-9)
        XCTAssertEqual(Astronomy.moonFraction(on: civil("2026-03-08")), 0.6618312807949325, accuracy: 1e-11)
    }

    func testPhaseNamesNextPhasesAndSupermoonsMatchThePi() {
        for c in cases {
            let day = civil(c.date)
            let zone = TimeZone(identifier: c.zone)!
            XCTAssertEqual(Astronomy.moonPhaseName(on: day), c.name, c.date)
            XCTAssertEqual(Astronomy.isSupermoon(on: day), c.supermoon, c.date)
            let full = Astronomy.nextPrincipal(after: day, full: true, in: zone)
            let new = Astronomy.nextPrincipal(after: day, full: false, in: zone)
            XCTAssertEqual(full.date, civil(c.full.0), c.date)
            XCTAssertEqual(full.days, c.full.1, c.date)
            XCTAssertEqual(new.date, civil(c.new.0), c.date)
            XCTAssertEqual(new.days, c.new.1, c.date)
        }
    }

    func testMoonriseAndMoonsetMatchThePi() {
        for c in cases {
            let times = Astronomy.moonTimes(on: civil(c.date), latitude: c.lat, longitude: c.lon, in: TimeZone(identifier: c.zone)!)
            XCTAssertEqual(times.rise == nil, c.rise == nil, c.date)
            XCTAssertEqual(times.set == nil, c.set == nil, c.date)
            if let rise = times.rise, let expected = c.rise {
                XCTAssertEqual(rise.timeIntervalSince1970, expected, accuracy: 1, c.date)
            }
            if let set = times.set, let expected = c.set {
                XCTAssertEqual(set.timeIntervalSince1970, expected, accuracy: 1, c.date)
            }
        }
    }

    func testTheSunMatchesThePi() {
        XCTAssertEqual(Astronomy.solarNoon(on: civil("2026-10-14"), longitude: -74.006).timeIntervalSince1970, 1791996120.960607, accuracy: 0.001)
        XCTAssertEqual(Astronomy.solarAltitude(at: date("2026-10-14T15:30:00Z"), latitude: 40.7128, longitude: -74.006),
                       38.251931748691476, accuracy: 1e-9)
    }

    /// The fixture's sun block was made with the Pi at longitude -74.0 (its moon block at
    /// -74.006), so the sun is only held to it loosely; the exact check is the one above.
    func testTheMoonAndSunBlocksMatchThePiFixture() throws {
        let pi = try DashboardClient.validated(fixture("snapshot"))
        let now = pi.generatedAt
        let today = CivilDate(now, in: newYork)
        let moon = LocalSnapshot.moon(today: today, place: nyc, quote: nil)
        let piMoon = try XCTUnwrap(pi.moon)
        XCTAssertEqual(moon.phaseName, piMoon.phaseName)
        XCTAssertEqual(moon.supermoon, piMoon.supermoon)
        XCTAssertEqual(moon.next, piMoon.next)
        XCTAssertEqual(try XCTUnwrap(moon.rise).timeIntervalSince(try XCTUnwrap(piMoon.rise)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(moon.set).timeIntervalSince(try XCTUnwrap(piMoon.set)), 0, accuracy: 0.001)
        XCTAssertEqual(moon.days.map(\.date), piMoon.days.map(\.date))
        for (mine, theirs) in zip(moon.days, piMoon.days) {
            XCTAssertEqual(mine.ageDays, theirs.ageDays, accuracy: 0.005)
            XCTAssertEqual(mine.fraction, theirs.fraction, accuracy: 0.00005)
            XCTAssertEqual(mine.illumination, theirs.illumination, accuracy: 0.05)
        }

        let sun = LocalSnapshot.sun(today: today, place: nyc)
        let piSun = try XCTUnwrap(pi.sun)
        XCTAssertEqual(sun.start, piSun.start)
        XCTAssertEqual(sun.stepMinutes, piSun.stepMinutes)
        XCTAssertEqual(sun.altitudes.count, piSun.altitudes.count)
        for (mine, theirs) in zip(sun.altitudes, piSun.altitudes) {
            XCTAssertEqual(mine, theirs, accuracy: 0.1)
        }
        XCTAssertEqual(sun.noons.count, piSun.noons.count)
        for (mine, theirs) in zip(sun.noons, piSun.noons) {
            XCTAssertEqual(mine.time.timeIntervalSince(theirs.time), 0, accuracy: 2)
            XCTAssertEqual(mine.altitude, theirs.altitude, accuracy: 0.1)
        }
    }

    func testASpringForwardDayHasFewerSunSamples() {
        let la = LocalSnapshot.Place(name: "SF", latitude: 37.77, longitude: -122.42, timezone: "America/Los_Angeles")
        // Four days from the 8th's midnight lose an hour: 92 + 3 × 96 steps, plus the end.
        XCTAssertEqual(LocalSnapshot.sun(today: civil("2026-03-08"), place: la).altitudes.count, 4 * 96 - 4 + 1)
    }

    // MARK: Quote

    func testTheQuotePickMatchesThePi() throws {
        XCTAssertEqual(LocalSnapshot.quoteIndex(key: "2026-10-14", count: 144), 55)
        XCTAssertEqual(LocalSnapshot.quoteIndex(key: "moonphase-2026-10-14", count: 144), 106)
        XCTAssertEqual(LocalSnapshot.quoteIndex(key: "2026-10-14", count: 7), 6)
        XCTAssertEqual(LocalSnapshot.quoteIndex(key: "2027-02-28", count: 144), 0)

        // The bundled store is the Pi's, so the day's quote is the panel's.
        let store = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "HomeDashboardTV/Resources/quotes.json")
        let quotes = try JSONDecoder().decode([Quote].self, from: Data(contentsOf: store))
        let pi = try DashboardClient.validated(fixture("snapshot"))
        let today = CivilDate(pi.generatedAt, in: newYork)
        XCTAssertEqual(LocalSnapshot.quote(for: today, prefix: "", in: quotes), pi.quote)
        XCTAssertEqual(LocalSnapshot.quote(for: today, prefix: "moonphase-", in: quotes), pi.moon?.quote)
        XCTAssertNil(LocalSnapshot.quote(for: today, prefix: "", in: []))
    }

    // MARK: Open-Meteo

    /// The forecast fixture's own moment: 23:30 on Thursday the 29th in New York.
    private let recorded = Date(timeIntervalSince1970: 1_793_331_000)

    func testTheForecastReadsAsThePiSendsIt() throws {
        let w = try OpenMeteo.weather(from: fixture("open-meteo-forecast"), now: recorded, zone: newYork, place: "New York")
        XCTAssertEqual(w.currentTemp, 57.0)
        XCTAssertEqual(w.currentIcon, "01n", "clear, at night")
        XCTAssertEqual(w.currentDescription, "clear sky")
        XCTAssertEqual(w.humidity, 79)
        XCTAssertEqual(w.pressure, 1018.4)
        XCTAssertEqual(w.windDeg, 232)
        XCTAssertEqual(w.locationName, "New York")
        XCTAssertGreaterThanOrEqual(w.high, w.low)
        let sunrise = try XCTUnwrap(w.sunrise)
        XCTAssertEqual(CivilDate(sunrise, in: newYork), civil("2026-10-29"))

        // Tomorrow on, as the Pi's forecast: the six days after the 29th.
        XCTAssertEqual(w.forecast.map(\.date), (1...6).map { civil("2026-10-29").adding(days: $0) })
        XCTAssertTrue(w.forecast.allSatisfy { $0.icon.hasSuffix("d") && ($0.precipChance ?? 0) <= 1 })

        // OWM's 3-hour grid: on UTC hours divisible by 3, after now.
        XCTAssertEqual(w.hourly.count, 40)
        XCTAssertGreaterThan(try XCTUnwrap(w.hourly.first).time, recorded)
        XCTAssertTrue(w.hourly.allSatisfy { Int($0.time.timeIntervalSince1970) % 10_800 == 0 })
        XCTAssertTrue(zip(w.hourly, w.hourly.dropFirst()).allSatisfy { $1.time.timeIntervalSince($0.time) == 10_800 })
    }

    func testWMOCodesBecomeOWMIcons() {
        XCTAssertEqual(OpenMeteo.icon(0, day: true), "01d")
        XCTAssertEqual(OpenMeteo.icon(2, day: false), "03n")
        XCTAssertEqual(OpenMeteo.icon(45, day: true), "50d")
        XCTAssertEqual(OpenMeteo.icon(63, day: true), "10d")
        XCTAssertEqual(OpenMeteo.icon(81, day: true), "09d")
        XCTAssertEqual(OpenMeteo.icon(67, day: true), "13d", "freezing rain is OWM's snow")
        XCTAssertEqual(OpenMeteo.icon(75, day: false), "13n")
        XCTAssertEqual(OpenMeteo.icon(95, day: true), "11d")
    }

    func testTheAirReadsAsThePurpleAirBlock() throws {
        let air = try OpenMeteo.airQuality(from: fixture("open-meteo-air"))
        XCTAssertEqual(air.aqi, 70)
        XCTAssertEqual(air.category, "Moderate")
        XCTAssertEqual(air.pm25, 17.8)
        XCTAssertEqual(OpenMeteo.category(aqi: 151), "Unhealthy")
    }

    func testPlacesSearchTellsSameNamedPlacesApart() throws {
        let found = try OpenMeteo.places(from: fixture("open-meteo-search"))
        XCTAssertEqual(found.first?.detail, "Springfield, Missouri, United States")
        XCTAssertEqual(found.first?.place.timezone, "America/Chicago")
        XCTAssertEqual(Set(found.map(\.id)).count, found.count)
    }

    // MARK: Assembly

    func testStalenessFollowsThePisMultiples() {
        XCTAssertEqual(Staleness(age: 3600, ttl: 3600), .fresh)
        XCTAssertEqual(Staleness(age: 3601, ttl: 3600), .aging)
        XCTAssertEqual(Staleness(age: 3 * 3600, ttl: 3600), .stale)
        XCTAssertEqual(Staleness(age: 4 * 3600 + 1, ttl: 3600), .expired)
    }

    func testTheSnapshotCarriesThePlacesZoneAndWithholdsExpiredData() throws {
        let weather = try OpenMeteo.weather(from: fixture("open-meteo-forecast"), now: recorded, zone: newYork, place: nil)
        let event = CalendarEvent(summary: "Standup", start: recorded, end: recorded.addingTimeInterval(1800), isAllDay: false)
        let snapshot = LocalSnapshot.make(
            now: recorded, place: nyc, metric: false, quotes: [Quote(text: "t", author: "a")],
            weather: .read(weather, at: recorded.addingTimeInterval(-5 * 3600)),
            airQuality: .pending,
            events: .read([event], at: recorded),
            birthdays: .off
        )
        XCTAssertEqual(snapshot.timeZone, newYork)
        XCTAssertEqual(snapshot.utcOffsetSeconds, -4 * 3600)
        XCTAssertFalse(snapshot.isMetric)
        XCTAssertEqual(snapshot.sources.weather?.staleness, .expired)
        XCTAssertNil(snapshot.sources.weather?.data)
        XCTAssertEqual(snapshot.sources.events?.data, [event])
        XCTAssertEqual(snapshot.sources.airQuality?.staleness, .unknown)
        XCTAssertNil(snapshot.sources.airQuality?.data)
        XCTAssertNil(snapshot.sources.birthdays, "a source that is off is absent, as a Pi's disabled one")
        XCTAssertEqual(snapshot.moon?.days.count, 7)
        XCTAssertEqual(snapshot.quote?.text, "t")
    }

    func testTheEventWindowStartsOnMonday() {
        // Thursday the 29th: from Monday the 26th to two weeks past tomorrow.
        let window = LocalSnapshot.eventWindow(now: recorded, in: newYork)
        XCTAssertEqual(window.start, date("2026-10-26T00:00:00-04:00"))
        XCTAssertEqual(window.end, date("2026-11-13T00:00:00-05:00"))
        let sunday = LocalSnapshot.eventWindow(now: date("2026-11-01T12:00:00-05:00"), in: newYork)
        XCTAssertEqual(sunday.start, date("2026-10-26T00:00:00-04:00"))
    }
}
