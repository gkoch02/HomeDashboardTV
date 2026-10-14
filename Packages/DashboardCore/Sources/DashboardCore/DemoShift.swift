import Foundation

extension Snapshot {
    /// The same snapshot moved forward by whole days so its first day is *now*'s, for the
    /// bundled demo data: a recorded week would otherwise show an empty agenda a week later.
    /// Whole days keep every event on its weekday-relative slot and its clock time.
    public func shiftedToToday(now: Date) -> Snapshot {
        let zone = timeZone
        let from = CivilDate(generatedAt, in: zone).start(in: zone)
        let to = CivilDate(now, in: zone).start(in: zone)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let days = cal.dateComponents([.day], from: from, to: to).day ?? 0
        guard days != 0 else { return self }

        func move(_ date: Date) -> Date { cal.date(byAdding: .day, value: days, to: date) ?? date }

        var copy = self
        copy.generatedAt = move(generatedAt)
        copy.sources.events?.data = sources.events?.data?.map { e in
            var e = e
            e.start = move(e.start)
            e.end = move(e.end)
            return e
        }
        copy.sources.birthdays?.data = sources.birthdays?.data?.map { b in
            var b = b
            b.date = b.date.adding(days: days)
            return b
        }
        if var moon = moon {
            moon.rise = moon.rise.map(move)
            moon.set = moon.set.map(move)
            moon.next.date = moon.next.date.adding(days: days)
            moon.days = moon.days.map { d in
                var d = d
                d.date = d.date.adding(days: days)
                return d
            }
            copy.moon = moon
        }
        if var sun = sun {
            sun.start = move(sun.start)
            sun.noons = sun.noons.map { n in
                var n = n
                n.time = move(n.time)
                return n
            }
            copy.sun = sun
        }
        if var w = sources.weather?.data {
            w.sunrise = w.sunrise.map(move)
            w.sunset = w.sunset.map(move)
            w.forecast = w.forecast.map { f in
                var f = f
                f.date = f.date.adding(days: days)
                return f
            }
            w.hourly = w.hourly.map { h in
                var h = h
                h.time = move(h.time)
                return h
            }
            copy.sources.weather?.data = w
        }
        return copy
    }
}
