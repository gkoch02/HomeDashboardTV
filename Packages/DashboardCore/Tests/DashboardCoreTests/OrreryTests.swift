import Foundation
import XCTest
@testable import DashboardCore

/// The Orrery layout's planets, seasons and daylight.
final class OrreryTests: XCTestCase {
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func apart(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    /// At an equinox or solstice the sun stands at 0, 90, 180 or 270 degrees as seen from the
    /// earth, so the earth stands opposite it.
    func testTheEarthStandsOppositeTheSunAtTheTurningPoints() {
        XCTAssertLessThan(apart(Orrery.longitude(.earth, at: date("2026-03-20T14:46:00Z")), 180), 0.5)
        XCTAssertLessThan(apart(Orrery.longitude(.earth, at: date("2026-06-21T08:24:00Z")), 270), 0.5)
        XCTAssertLessThan(apart(Orrery.longitude(.earth, at: date("2026-09-23T00:05:00Z")), 0), 0.5)
        XCTAssertLessThan(apart(Orrery.longitude(.earth, at: date("2026-12-21T20:50:00Z")), 90), 0.5)
    }

    /// The planets go round at their own rates: Mercury about four times a year, Mars about
    /// once in two.
    func testThePlanetsKeepTheirPeriods() {
        let start = date("2026-01-01T00:00:00Z")
        for (planet, days) in [(Orrery.Planet.mercury, 87.969), (.venus, 224.701), (.earth, 365.256), (.mars, 686.98)] {
            let later = start.addingTimeInterval(days * 86_400)
            XCTAssertLessThan(apart(Orrery.longitude(planet, at: start), Orrery.longitude(planet, at: later)), 1.5, "\(planet)")
        }
    }

    /// Meeus's mean instants against the published 2026 ones, within two hours.
    func testTheTurningPointsFallWhenTheyShould() {
        let published: [(Orrery.Turning, String)] = [
            (.marchEquinox, "2026-03-20T14:46:00Z"), (.juneSolstice, "2026-06-21T08:24:00Z"),
            (.septemberEquinox, "2026-09-23T00:05:00Z"), (.decemberSolstice, "2026-12-21T20:50:00Z"),
        ]
        for (turning, iso) in published {
            XCTAssertEqual(Orrery.instant(turning, year: 2026).timeIntervalSince(date(iso)), 0, accuracy: 7_200, "\(turning)")
        }
    }

    func testTheNextTurningPointRollsIntoTheNewYear() {
        let next = Orrery.nextTurning(after: date("2026-10-16T12:00:00Z"))
        XCTAssertEqual(next.turning, .decemberSolstice)
        XCTAssertEqual(Orrery.days(from: date("2026-10-16T12:00:00Z"), to: next.date, in: TimeZone(identifier: "UTC")!), 66)
        XCTAssertEqual(Orrery.nextTurning(after: date("2026-12-25T00:00:00Z")).turning, .marchEquinox)
    }

    func testTheSeasonsAreNamedForTheHemisphere() {
        XCTAssertEqual(Orrery.Turning.decemberSolstice.name(southern: false), "Winter solstice")
        XCTAssertEqual(Orrery.Turning.decemberSolstice.name(southern: true), "Summer solstice")
        XCTAssertEqual(Orrery.Turning.marchEquinox.name(southern: false), "Spring equinox")
    }

    func testNewYorkIsNorthOfTheEquator() throws {
        XCTAssertEqual(Orrery.isSouthern(try snapshot(), now: date("2026-10-14T12:00:00-04:00")), false)
    }

    func testTheMoonsElongationRunsThroughTheMonth() {
        XCTAssertEqual(Orrery.elongation(ageDays: 0), 0)
        XCTAssertEqual(Orrery.elongation(ageDays: Orrery.synodicMonth / 2), 180, accuracy: 0.001)
        XCTAssertEqual(Orrery.elongation(ageDays: Orrery.synodicMonth / 4), 90, accuracy: 0.001)
    }

    /// On the day the clocks go forward, 3:30 is three and a half hours round the face, though
    /// only two and a half have passed since midnight.
    func testTheClockFaceFollowsTheWallClock() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let day = CivilDate(year: 2027, month: 3, day: 14)
        XCTAssertEqual(Orrery.clockHours(date("2027-03-14T03:30:00-04:00"), from: day, in: newYork), 3.5, accuracy: 0.001)
        XCTAssertEqual(Orrery.clockHours(date("2027-03-15T09:30:00-04:00"), from: day, in: newYork), 33.5, accuracy: 0.001)
        XCTAssertEqual(Orrery.clockHours(date("2026-11-01T23:00:00-05:00"), from: CivilDate(year: 2026, month: 11, day: 1), in: newYork),
                       23, accuracy: 0.001, "the day the clocks go back")
    }

    /// The Pi samples the moon's age at noon UTC, which is 8 a.m. in New York in summer.
    func testTheMoonAgesFromNoonUTC() throws {
        let moon = try XCTUnwrap(try snapshot().moon?.today)
        XCTAssertEqual(Orrery.moonAge(moon, at: moon.date.start(in: TimeZone(identifier: "UTC")!).addingTimeInterval(12 * 3600)),
                       moon.ageDays, accuracy: 0.0001)
        XCTAssertEqual(Orrery.moonAge(moon, at: date("\(String(format: "%04d-%02d-%02d", moon.date.year, moon.date.month, moon.date.day))T12:00:00-04:00")),
                       moon.ageDays + 4.0 / 24, accuracy: 0.0001)
    }

    /// Mid-October in New York the days are shortening by about two minutes a day.
    func testTheDaylightShortensInOctober() throws {
        let light = try XCTUnwrap(Orrery.daylight(try snapshot(), now: date("2026-10-14T12:00:00-04:00")))
        XCTAssertEqual(light.length / 3600, 11.2, accuracy: 0.3)
        let change = try XCTUnwrap(light.change)
        XCTAssertLessThan(change, -60)
        XCTAssertGreaterThan(change, -240)
    }
}
