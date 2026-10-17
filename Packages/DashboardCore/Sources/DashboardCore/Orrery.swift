import Foundation

/// The Orrery layout's model: where the inner planets stand round the sun, where the moon is
/// in its month, the year's turning points, and how the daylight is changing. Orrery has no Pi
/// theme behind it; it is drawn for the TV.
public enum Orrery {
    public enum Planet: CaseIterable, Sendable {
        case mercury, venus, earth, mars
    }

    /// Mean orbital elements at J2000.0: mean longitude and its daily motion, longitude of
    /// perihelion, eccentricity (Standish, JPL, for 1800–2050).
    private static func elements(_ planet: Planet) -> (l0: Double, rate: Double, perihelion: Double, e: Double) {
        switch planet {
        case .mercury: return (252.25032, 4.09233445, 77.45780, 0.20564)
        case .venus: return (181.97910, 1.60213034, 131.60247, 0.00678)
        case .earth: return (100.46457, 0.98560910, 102.93768, 0.01671)
        case .mars: return (355.44657, 0.52402068, 336.05637, 0.09339)
        }
    }

    private static let j2000 = Date(timeIntervalSince1970: 946_728_000)  // 2000-01-01 12:00 UTC

    /// The planet's heliocentric ecliptic longitude at *date*, in degrees from 0 up to 360: its
    /// mean longitude corrected by the equation of the centre, within a degree for an orrery's
    /// purposes (Mercury, the most eccentric, to about one).
    public static func longitude(_ planet: Planet, at date: Date) -> Double {
        let (l0, rate, perihelion, e) = elements(planet)
        let days = date.timeIntervalSince(j2000) / 86_400
        let mean = l0 + rate * days
        let anomaly = (mean - perihelion) * .pi / 180
        let centre = (2 * e - e * e * e / 4) * sin(anomaly) + 1.25 * e * e * sin(2 * anomaly)
            + 13.0 / 12.0 * e * e * e * sin(3 * anomaly)
        return wrap(mean + centre * 180 / .pi)
    }

    /// The moon's angle from the sun as seen from the earth, in degrees: 0 new, 180 full,
    /// growing through the month.
    public static func elongation(ageDays: Double) -> Double {
        wrap(ageDays / synodicMonth * 360)
    }

    public static let synodicMonth = 29.530589

    /// The equinoxes and solstices.
    public enum Turning: CaseIterable, Sendable {
        case marchEquinox, juneSolstice, septemberEquinox, decemberSolstice

        /// "Spring equinox", "Winter solstice": named for the northern hemisphere's seasons
        /// unless *southern*.
        public func name(southern: Bool) -> String {
            switch (self, southern) {
            case (.marchEquinox, false), (.septemberEquinox, true): return "Spring equinox"
            case (.juneSolstice, false), (.decemberSolstice, true): return "Summer solstice"
            case (.septemberEquinox, false), (.marchEquinox, true): return "Autumn equinox"
            case (.decemberSolstice, false), (.juneSolstice, true): return "Winter solstice"
            }
        }
    }

    /// When *turning* falls in *year*: Meeus's mean instants (Astronomical Algorithms, ch. 27,
    /// years 2000 to 3000), within an hour or so, plenty for a count of days.
    public static func instant(_ turning: Turning, year: Int) -> Date {
        let y = Double(year - 2000) / 1000
        let c: [Double] = switch turning {
        case .marchEquinox: [2451623.80984, 365242.37404, 0.05169, -0.00411, -0.00057]
        case .juneSolstice: [2451716.56767, 365241.62603, 0.00325, 0.00888, -0.00030]
        case .septemberEquinox: [2451810.21715, 365242.01767, -0.11575, 0.00337, 0.00078]
        case .decemberSolstice: [2451900.05952, 365242.74049, -0.06223, -0.00823, 0.00032]
        }
        let jde = c[0] + y * (c[1] + y * (c[2] + y * (c[3] + y * c[4])))
        return Date(timeIntervalSince1970: (jde - 2440587.5) * 86_400)
    }

    /// The next equinox or solstice after *date*.
    public static func nextTurning(after date: Date) -> (turning: Turning, date: Date) {
        let year = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date).year!
        return [year, year + 1]
            .flatMap { y in Turning.allCases.map { ($0, instant($0, year: y)) } }
            .first { $0.1 > date }!
    }

    /// Whole days from *now*'s day to *date*'s, in *zone*.
    public static func days(from now: Date, to date: Date, in zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }

    /// Today's daylight, and how much longer (or, negative, shorter) tomorrow's is.
    public static func daylight(_ snapshot: Snapshot, now: Date) -> (length: TimeInterval, change: TimeInterval?)? {
        let sun = SunModel(snapshot: snapshot)
        let today = CivilDate(now, in: snapshot.timeZone)
        guard let (rise, set) = LightCycle.daylight(snapshot, sun: sun, on: today) else { return nil }
        let length = set.timeIntervalSince(rise)
        let change = LightCycle.daylight(snapshot, sun: sun, on: today.adding(days: 1))
            .map { $0.set.timeIntervalSince($0.rise) - length }
        return (length, change)
    }

    /// Whether the dashboard is south of the equator, which the Pi doesn't say: while the sun
    /// is south of the equator, the north has days under twelve hours and the south over.
    /// Nil within a few days of an equinox, when both are near twelve.
    public static func isSouthern(_ snapshot: Snapshot, now: Date) -> Bool? {
        guard let length = daylight(snapshot, now: now)?.length else { return nil }
        let sun = (longitude(.earth, at: now) + 180) * .pi / 180
        let declination = asin(sin(23.44 * .pi / 180) * sin(sun)) * 180 / .pi
        guard abs(declination) > 2, abs(length - 43_200) > 600 else { return nil }
        return (declination < 0) == (length > 43_200)
    }

    static func wrap(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}
