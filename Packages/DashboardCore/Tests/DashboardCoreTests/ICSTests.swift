import Foundation
import XCTest
@testable import DashboardCore

/// `Fixtures/calendar.ics` read as the Pi reads a feed. The expected instances are the Pi's own
/// (`calendar_ical` with icalendar 7.3 and recurring-ical-events, HomeDashboard a5dd200) for
/// New York over the 60 days from Monday 2026-10-26, less the two it shows though they are
/// cancelled: a CANCELLED event, and a CANCELLED override of one standup.
final class ICSTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func feed() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/calendar", withExtension: "ics"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private var window: Range<Date> {
        let start = CivilDate(year: 2026, month: 10, day: 26)
        return start.start(in: newYork)..<start.adding(days: 60).start(in: newYork)
    }

    /// (summary, start, end, all day), as Unix times.
    private let expected: [(String, TimeInterval, TimeInterval, Bool)] = [
        ("Gym", 1793012400, 1793016000, false),
        ("Bins out", 1793073600, 1793160000, true),
        ("Water the plants", 1793102400, 1793103000, false),
        ("Standup across the clock change", 1793106000, 1793106900, false),
        ("Take the pills", 1793149200, 1793149500, false),
        ("Take the pills", 1793235600, 1793235900, false),
        ("Standup across the clock change", 1793278800, 1793279700, false),
        ("Take the pills", 1793322000, 1793322300, false),
        ("Gym", 1793358000, 1793361600, false),
        ("Water the plants", 1793361600, 1793362200, false),
        ("Dentist, Dr. Lee", 1793385000, 1793388600, false),
        ("Timesheets", 1793390400, 1793392200, false),
        ("Book club", 1793401200, 1793408400, false),
        ("Take the pills", 1793408400, 1793408700, false),
        ("Halloween", 1793419200, 1793505600, true),
        ("Pay rent", 1793419200, 1793505600, true),
        ("Floating breakfast", 1793449800, 1793453400, false),
        ("Take the pills", 1793494800, 1793495100, false),
        ("Take the pills", 1793584800, 1793585100, false),
        ("Gym", 1793620800, 1793624400, false),
        ("Water the plants", 1793624400, 1793625000, false),
        ("Call with London", 1793631600, 1793634300, false),
        ("Take the pills", 1793671200, 1793671500, false),
        ("Anniversary", 1793682000, 1793768400, true),
        ("Standup across the clock change", 1793714400, 1793715300, false),
        ("Gym", 1793793600, 1793797200, false),
        ("West coast call", 1793811600, 1793815200, false),
        ("Trip to the coast", 1793854800, 1794114000, true),
        ("Water the plants", 1793883600, 1793884200, false),
        ("Standup (moved)", 1793894400, 1793895300, false),
        ("Gym", 1793966400, 1793970000, false),
        ("Water the plants", 1794142800, 1794143400, false),
        ("Gym", 1794225600, 1794229200, false),
        ("Bins out", 1794286800, 1794373200, true),
        ("Council meeting", 1794353400, 1794358800, false),
        ("Gym", 1794398400, 1794402000, false),
        ("Water the plants", 1794402000, 1794402600, false),
        ("Standup across the clock change", 1794492000, 1794492900, false),
        ("Gym", 1794571200, 1794574800, false),
        ("Water the plants", 1794661200, 1794661800, false),
        ("Standup across the clock change", 1794924000, 1794924900, false),
        ("Standup across the clock change", 1795096800, 1795097700, false),
        ("Bins out", 1795496400, 1795582800, true),
        ("Standup across the clock change", 1795528800, 1795529700, false),
        ("Standup across the clock change", 1795701600, 1795702500, false),
        ("Book club", 1795824000, 1795831200, false),
        ("Timesheets", 1796072400, 1796074200, false),
        ("Standup across the clock change", 1796133600, 1796134500, false),
        ("Standup across the clock change", 1796306400, 1796307300, false),
        ("Bins out", 1796706000, 1796792400, true),
        ("Standup across the clock change", 1796738400, 1796739300, false),
        ("Council meeting", 1796772600, 1796778000, false),
        ("Standup across the clock change", 1796911200, 1796912100, false),
        ("Standup across the clock change", 1797343200, 1797344100, false),
        ("Standup across the clock change", 1797516000, 1797516900, false),
        ("Bins out", 1797915600, 1798002000, true),
        ("Standup across the clock change", 1797948000, 1797948900, false),
        ("Standup across the clock change", 1798120800, 1798121700, false),
    ]

    func testEveryInstanceMatchesThePi() throws {
        let events = ICS.parse(try feed(), zone: newYork, window: window).events
        let got = events.map { "\($0.summary) \(Int($0.start.timeIntervalSince1970)) \(Int($0.end.timeIntervalSince1970)) \($0.isAllDay)" }
        let want = expected.map { "\($0.0) \(Int($0.1)) \(Int($0.2)) \($0.3)" }
        XCTAssertEqual(Set(got).subtracting(want), [], "instances the Pi does not have")
        XCTAssertEqual(Set(want).subtracting(got), [], "instances the Pi has")
        XCTAssertEqual(got.count, want.count)
    }

    func testTextAndTheCalendarsName() throws {
        let parsed = ICS.parse(try feed(), zone: newYork, window: window, fallbackName: "example.com")
        XCTAssertEqual(parsed.name, "Family")
        let dentist = try XCTUnwrap(parsed.events.first { $0.summary.hasPrefix("Dentist") })
        XCTAssertEqual(dentist.summary, "Dentist, Dr. Lee")
        XCTAssertEqual(dentist.location, "12 Main St\nSuite 4")
        XCTAssertEqual(dentist.calendarName, "Family")
        XCTAssertTrue(parsed.events.contains { $0.summary == "Standup across the clock change" }, "a folded line is joined")
    }

    func testTheStandupKeepsItsWallClockTimeAcrossTheChange() throws {
        let standups = ICS.parse(try feed(), zone: newYork, window: window).events.filter { $0.summary.hasPrefix("Standup across") }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = newYork
        XCTAssertTrue(standups.allSatisfy { cal.component(.hour, from: $0.start) == 9 })
        XCTAssertTrue(standups.contains { $0.start < CivilDate(year: 2026, month: 11, day: 1).start(in: newYork) })
        XCTAssertTrue(standups.contains { $0.start > CivilDate(year: 2026, month: 11, day: 2).start(in: newYork) })
    }

    func testAnOldDailyRuleStillReachesTheWindow() {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:old
        SUMMARY:Walk the dog
        DTSTART;TZID=America/New_York:20050301T070000
        DURATION:PT30M
        RRULE:FREQ=DAILY
        END:VEVENT
        BEGIN:VEVENT
        UID:minutely
        SUMMARY:Runaway
        DTSTART:20261027T120000Z
        RRULE:FREQ=MINUTELY
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICS.parse(text, zone: newYork, window: window).events
        XCTAssertEqual(events.filter { $0.summary == "Walk the dog" }.count, 60)
        XCTAssertEqual(events.filter { $0.summary == "Runaway" }.count, 1, "a rule finer than daily leaves the first instance")
    }

    func testADailyAllDayEventEndsAtMidnightAcrossTheChange() {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:daily
        SUMMARY:Holiday week
        DTSTART;VALUE=DATE:20260307
        DTEND;VALUE=DATE:20260308
        RRULE:FREQ=DAILY;COUNT=3
        END:VEVENT
        END:VCALENDAR
        """
        let start = CivilDate(year: 2026, month: 3, day: 7)
        let events = ICS.parse(text, zone: newYork, window: start.start(in: newYork)..<start.adding(days: 7).start(in: newYork)).events
        XCTAssertEqual(events.map(\.end), (1...3).map { start.adding(days: $0).start(in: newYork) })
    }

    func testDurationsAndZones() {
        XCTAssertEqual(ICS.duration("PT45M"), 2700)
        XCTAssertEqual(ICS.duration("P1DT2H"), 93_600)
        XCTAssertEqual(ICS.duration("P2W"), 1_209_600)
        XCTAssertEqual(ICS.duration("-PT15M"), -900)
        XCTAssertNil(ICS.duration("PT"))
        XCTAssertEqual(ICS.timeZone("/mozilla.org/20050126_1/America/New_York"), newYork)
        XCTAssertEqual(ICS.timeZone("Eastern Standard Time"), newYork)
        XCTAssertNil(ICS.timeZone("Nowhere Standard Time"))
    }
}
