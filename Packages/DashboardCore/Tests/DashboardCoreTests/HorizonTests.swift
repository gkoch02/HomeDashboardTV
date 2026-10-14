import Foundation
import XCTest
@testable import DashboardCore

/// The Horizon model over the Pi fixture (New York, generated 2026-10-14 03:27 local).
final class HorizonTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private func date(_ iso: String) -> Date { PythonISODate.parse(iso)! }

    private func snapshot() throws -> Snapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/snapshot", withExtension: "json"))
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    private func axis(_ now: String = "2026-10-14T03:27:00-04:00") -> TimeAxis {
        TimeAxis(start: Horizon.windowStart(now: date(now), in: newYork), x0: 0, x1: 1000, zone: newYork)
    }

    // MARK: Axis

    func testTheWindowStartsAtTheSlotHoldingNow() {
        XCTAssertEqual(Horizon.windowStart(now: date("2026-10-14T03:27:00-04:00"), in: newYork),
                       date("2026-10-14T03:00:00-04:00"))
        XCTAssertEqual(Horizon.windowStart(now: date("2026-10-14T23:59:00-04:00"), in: newYork),
                       date("2026-10-14T21:00:00-04:00"))
    }

    func testTheWindowStartsOnTheClockHourAcrossDST() {
        // 2026-03-08 springs forward at 02:00, 2026-11-01 falls back at 02:00.
        XCTAssertEqual(Horizon.windowStart(now: date("2026-03-08T03:30:00-04:00"), in: newYork),
                       date("2026-03-08T03:00:00-04:00"))
        XCTAssertEqual(Horizon.windowStart(now: date("2026-11-01T03:30:00-05:00"), in: newYork),
                       date("2026-11-01T03:00:00-05:00"))
        XCTAssertEqual(Horizon.windowStart(now: date("2026-11-01T01:30:00-05:00"), in: newYork),
                       date("2026-11-01T00:00:00-04:00"))
    }

    func testNightHoursAreNarrowerAndTheMapInverts() {
        let a = axis()
        let night = a.x(date("2026-10-14T04:00:00-04:00")) - a.x(date("2026-10-14T03:00:00-04:00"))
        let day = a.x(date("2026-10-14T13:00:00-04:00")) - a.x(date("2026-10-14T12:00:00-04:00"))
        XCTAssertEqual(night / day, 0.35, accuracy: 1e-9)
        XCTAssertEqual(a.x(a.end), 1000, accuracy: 1e-9)
        let t = date("2026-10-15T17:20:00-04:00")
        XCTAssertEqual(a.time(atX: a.x(t)).timeIntervalSince(t), 0, accuracy: 1)
        XCTAssertLessThan(a.xUnclamped(a.start.addingTimeInterval(-3600)), 0)
    }

    func testMidnightsSplitTheWindowIntoDays() {
        let a = axis()
        XCTAssertEqual(a.midnights.map(\.day), [
            CivilDate(year: 2026, month: 10, day: 15),
            CivilDate(year: 2026, month: 10, day: 16),
            CivilDate(year: 2026, month: 10, day: 17),
        ])
        XCTAssertEqual(a.dayColumns.count, 4)
        XCTAssertEqual(a.dayColumns.first?.x0, 0)
        XCTAssertEqual(a.dayColumns.last?.x1, 1000)
    }

    func testADSTDayHasTwentyFiveHourColumns() {
        // New York falls back on 2026-11-01.
        let a = TimeAxis(start: date("2026-11-01T00:00:00-04:00"), hours: 30, x0: 0, x1: 1000, zone: newYork)
        XCTAssertEqual(a.midnights.first?.day, CivilDate(year: 2026, month: 11, day: 2))
        XCTAssertEqual(a.midnights.first?.x ?? 0, a.x(date("2026-11-01T01:00:00-04:00").addingTimeInterval(24 * 3600)), accuracy: 1e-6)
    }

    // MARK: Sun

    func testTheSunArcsBetweenSunriseAndSunset() throws {
        let weather = try XCTUnwrap(snapshot().sources.weather?.data)
        let sun = SunModel(weather: weather, zone: newYork)
        let rise = try XCTUnwrap(weather.sunrise)
        XCTAssertEqual(sun.altitude(at: rise), 0, accuracy: 0.5)
        let noons = sun.noons(in: axis())
        XCTAssertEqual(noons.count, 3)
        XCTAssertEqual(noons[0].altitude, 50, accuracy: 0.01)
        XCTAssertLessThan(sun.altitude(at: date("2026-10-15T01:00:00-04:00")), -40 + 1e-9)
        XCTAssertEqual(sun.altitude(at: rise.addingTimeInterval(-1800)), -6, accuracy: 0.5)
    }

    func testThePiSunBlockDrivesTheAltitude() throws {
        let s = try snapshot()
        let block = try XCTUnwrap(s.sun)
        XCTAssertEqual(block.start, date("2026-10-14T00:00:00-04:00"))
        XCTAssertEqual(block.stepMinutes, 15)
        XCTAssertEqual(block.altitudes.count, 385)

        let sun = SunModel(snapshot: s)
        XCTAssertTrue(sun.isExact)
        let tenAM = date("2026-10-14T10:00:00-04:00")
        XCTAssertEqual(sun.altitude(at: tenAM), block.altitudes[40], accuracy: 1e-9)
        let between = tenAM.addingTimeInterval(450)
        XCTAssertEqual(sun.altitude(at: between), (block.altitudes[40] + block.altitudes[41]) / 2, accuracy: 1e-9)
        // Past the samples, the arc.
        let later = block.start.addingTimeInterval(5 * 86_400)
        XCTAssertEqual(sun.altitude(at: later), sun.arcAltitude(at: later))

        let noons = sun.noons(in: axis())
        XCTAssertEqual(noons.map(\.time), block.noons.prefix(3).map(\.time))
        XCTAssertEqual(noons[0].altitude, block.noons[0].altitude)
        XCTAssertLessThan(noons[0].altitude, 50)  // October in New York, not the arc's 50°
    }

    func testTheDemoShiftCarriesTheSunBlock() throws {
        let s = try snapshot()
        let shifted = s.shiftedToToday(now: date("2026-10-20T09:00:00-04:00"))
        XCTAssertEqual(shifted.sun?.start, date("2026-10-20T00:00:00-04:00"))
        XCTAssertEqual(shifted.sun?.altitudes, s.sun?.altitudes)
        XCTAssertEqual(shifted.sun?.noons.first?.time, s.sun?.noons.first?.time.addingTimeInterval(6 * 86_400))
    }

    func testWithoutWeatherTheSunKeepsFixedHours() {
        let sun = SunModel(weather: nil, zone: newYork)
        XCTAssertEqual(sun.rise, 6.5)
        XCTAssertEqual(sun.set, 19.5)
    }

    // MARK: Forecast

    func testSlotsAreLedInFromTheReadingNow() throws {
        let s = try snapshot()
        let weather = try XCTUnwrap(s.sources.weather?.data)
        let slots = Horizon.slots(weather: weather, axis: axis())
        let first = try XCTUnwrap(slots.first)
        XCTAssertTrue(first.isStandIn)
        XCTAssertLessThanOrEqual(first.start, axis().start)
        XCTAssertEqual(first.temp, weather.currentTemp)
        XCTAssertFalse(slots[1].isStandIn)
        for (a, b) in zip(slots, slots.dropFirst()) { XCTAssertEqual(a.end, b.start) }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(slots.last).start, axis().end)
    }

    func testExtremesAreTurningPointsAndNeverStandIns() throws {
        let weather = try XCTUnwrap(snapshot().sources.weather?.data)
        let a = axis()
        let slots = Horizon.slots(weather: weather, axis: a)
        let extremes = Horizon.extremes(slots, axis: a)
        XCTAssertFalse(extremes.isEmpty)
        for e in extremes {
            let i = try XCTUnwrap(slots.firstIndex { $0.start == e.time })
            XCTAssertFalse(slots[i].isStandIn)
            if e.kind == .high {
                XCTAssertGreaterThanOrEqual(e.temp, max(slots[i - 1].temp, slots[i + 1].temp))
            } else {
                XCTAssertLessThanOrEqual(e.temp, min(slots[i - 1].temp, slots[i + 1].temp))
            }
        }
    }

    func testAFlatDayIsNotStretched() {
        func slot(_ t: Double) -> HorizonSlot {
            HorizonSlot(start: .now, end: .now, temp: t, icon: "01d", precipChance: 0, precipMm: nil, isStandIn: false)
        }
        let scale = Horizon.tempScale([slot(60), slot(62)])
        XCTAssertEqual(scale.hi - scale.lo, 14)
        XCTAssertEqual((scale.hi + scale.lo) / 2, 61)
    }

    func testIconsMapToTheSky() {
        XCTAssertEqual(SkyKind(icon: "04d").level, 3)
        XCTAssertEqual(SkyKind(icon: "10n").precip, .rain)
        XCTAssertTrue(SkyKind(icon: "13d").hidesBodies)
        XCTAssertFalse(SkyKind(icon: "02d").hidesBodies)
    }

    func testOutlookNamesTheWarmestColdestAndRain() throws {
        let weather = try XCTUnwrap(snapshot().sources.weather?.data)
        let a = axis()
        let rows = Horizon.outlook(Horizon.slots(weather: weather, axis: a), axis: a)
        XCTAssertEqual(rows.map(\.label), ["WARMEST", "COLDEST", "RAIN"])
        XCTAssertTrue(rows[0].value.hasSuffix("°"))
    }

    // MARK: Calendar

    func testAllDayChipsIncludeBirthdaysInTheWindow() throws {
        let chips = Horizon.allDayChips(try snapshot(), axis: axis())
        let conference = try XCTUnwrap(chips.first { $0.label == "Tech Conference" })
        XCTAssertEqual(conference.end, date("2026-10-17T00:00:00-04:00"))
        let mom = try XCTUnwrap(chips.first { $0.isBirthday })
        XCTAssertEqual(mom.label, "Mom's birthday")
        XCTAssertEqual(mom.short, "Mom")
        XCTAssertFalse(chips.contains { $0.short == "Jake" })  // the 21st is past the window
    }

    func testSpansSitAboveTheSingleDaysTheyCross() {
        let rows = Horizon.stackChips([
            (x0: 0, x1: 100, multiDay: false, chip: "dentist"),
            (x0: 0, x1: 300, multiDay: true, chip: "trip"),
            (x0: 200, x1: 300, multiDay: false, chip: "lunch"),
            (x0: 400, x1: 500, multiDay: false, chip: "free day"),
        ])
        XCTAssertEqual(rows, [["trip", "free day"], ["dentist", "lunch"]])
    }

    func testAFullDayEndsOnTheCountRow() {
        XCTAssertEqual(Horizon.listRows(events: 3, hidden: 0, available: 5).shown, 3)
        XCTAssertEqual(Horizon.listRows(events: 6, hidden: 0, available: 5).shown, 4)
        XCTAssertEqual(Horizon.listRows(events: 6, hidden: 0, available: 5).more, 2)
        XCTAssertEqual(Horizon.listRows(events: 2, hidden: 1, available: 5).more, 1)
    }

    func testDayNames() {
        let a = axis()
        let now = date("2026-10-14T03:27:00-04:00")
        XCTAssertEqual(Horizon.dayName(CivilDate(year: 2026, month: 10, day: 14), now: now, axis: a), "TODAY")
        XCTAssertEqual(Horizon.dayName(CivilDate(year: 2026, month: 10, day: 15), now: now, axis: a), "TOMORROW")
        XCTAssertEqual(Horizon.dayName(CivilDate(year: 2026, month: 10, day: 16), now: now, axis: a), "FRIDAY")
        let evening = date("2026-10-14T19:10:00-04:00")
        XCTAssertEqual(Horizon.dayName(CivilDate(year: 2026, month: 10, day: 14), now: evening,
                                       axis: axis("2026-10-14T19:10:00-04:00")), "TONIGHT")
    }

    func testTheMoonTransitsLaterAsItWaxes() throws {
        let moon = try XCTUnwrap(snapshot().moon)
        let day = CivilDate(year: 2026, month: 10, day: 14)
        let transit = try XCTUnwrap(Horizon.moonTransit(on: day, moon: moon, zone: newYork))
        XCTAssertGreaterThan(transit.time, day.start(in: newYork).addingTimeInterval(12 * 3600))
        XCTAssertNil(Horizon.moonTransit(on: CivilDate(year: 2026, month: 11, day: 1), moon: moon, zone: newYork))
    }
}
