import Foundation

/// One day of the agenda, in the dashboard's zone.
public struct AgendaDay: Sendable, Equatable, Identifiable {
    public var day: CivilDate
    /// All-day events first, then timed events by start.
    public var events: [CalendarEvent]
    public var birthdays: [Birthday]

    public var id: CivilDate { day }
}

public enum Agenda {
    /// *count* days starting with the one containing *now*, each holding the events that
    /// overlap it. A multi-day event appears on every day it covers; an event ending exactly
    /// at midnight (every all-day event does) does not spill into the next day.
    public static func days(
        from snapshot: Snapshot,
        now: Date,
        count: Int
    ) -> [AgendaDay] {
        let zone = snapshot.timeZone
        let today = CivilDate(now, in: zone)
        let events = snapshot.sources.events?.data ?? []
        let birthdays = snapshot.sources.birthdays?.data ?? []
        return (0..<count).map { offset in
            let day = today.adding(days: offset)
            let start = day.start(in: zone)
            let end = day.adding(days: 1).start(in: zone)
            let overlapping = events
                .filter { $0.start < end && ($0.end > start || $0.start >= start) }
                .sorted { a, b in
                    if a.isAllDay != b.isAllDay { return a.isAllDay }
                    return a.start != b.start ? a.start < b.start : a.summary < b.summary
                }
            return AgendaDay(
                day: day,
                events: overlapping,
                birthdays: birthdays.filter { $0.date == day }
            )
        }
    }

    /// Birthdays from *now*'s day on, soonest first.
    public static func upcomingBirthdays(from snapshot: Snapshot, now: Date) -> [Birthday] {
        let today = CivilDate(now, in: snapshot.timeZone)
        return (snapshot.sources.birthdays?.data ?? [])
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
    }
}
