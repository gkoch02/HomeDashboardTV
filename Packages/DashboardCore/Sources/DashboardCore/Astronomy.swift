import Foundation

/// The Pi's moon and sun maths (`src/render/moon.py`, `src/astronomy.py`), for a snapshot made
/// without a Pi. The two must agree, so this follows the Python line for line, approximations
/// included: the phase from Meeus ch. 47–48's principal terms, new and full moons from ch. 49,
/// moonrise from Schlyter's simplified orbit, and the sun from NOAA's spreadsheet equations.
public enum Astronomy {
    /// Mean synodic month in days; ages are the true phase fraction in these days.
    static let synodicMonth = 29.53059
    /// 2000-01-01 12:00 UTC.
    private static let j2000 = Date(timeIntervalSince1970: 946_728_000)
    /// TT − UT, close enough for this decade.
    private static let deltaTDays = 69.0 / 86_400

    private static let utc = TimeZone(identifier: "UTC")!

    private static func sin(degrees: Double) -> Double { Foundation.sin(degrees * .pi / 180) }

    private static func noonUTC(_ day: CivilDate) -> Date {
        day.start(in: utc).addingTimeInterval(12 * 3600)
    }

    // MARK: Moon phase

    /// The moon's phase angle in degrees, in (-180, 180]: 180 new, 0 full, positive waxing.
    static func phaseAngle(at when: Date) -> Double {
        let t = (when.timeIntervalSince(j2000) / 86_400 + deltaTDays) / 36_525
        let elong = 297.8501921 + 445_267.1114034 * t - 0.0018819 * t * t
        let sunAnom = 357.5291092 + 35_999.0502909 * t - 0.0001536 * t * t
        let moonAnom = 134.9633964 + 477_198.8675055 * t + 0.0087414 * t * t
        let i = 180 - elong
            - 6.289 * sin(degrees: moonAnom)
            + 2.100 * sin(degrees: sunAnom)
            - 1.274 * sin(degrees: 2 * elong - moonAnom)
            - 0.658 * sin(degrees: 2 * elong)
            - 0.214 * sin(degrees: 2 * moonAnom)
            - 0.110 * sin(degrees: elong)
        return 180 - pythonMod(180 - i, 360)
    }

    /// How far through the lunation the moon is at noon UTC on *day*: 0 new, 0.5 full.
    public static func moonFraction(on day: CivilDate) -> Double {
        pythonMod((180 - phaseAngle(at: noonUTC(day))) / 360, 1)
    }

    /// The moon's age at noon UTC on *day* in mean-month days (0 new, ~14.77 full).
    public static func moonAge(on day: CivilDate) -> Double {
        moonFraction(on: day) * synodicMonth
    }

    /// The lit percentage of the disc at noon UTC on *day*.
    public static func moonIllumination(on day: CivilDate) -> Double {
        (1 + cos(phaseAngle(at: noonUTC(day)) * .pi / 180)) / 2 * 100
    }

    private static let phaseNames = [
        "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
        "Full Moon", "Waning Gibbous", "Third Quarter", "Waning Crescent",
    ]

    public static func moonPhaseName(on day: CivilDate) -> String {
        phaseNames[Int(moonFraction(on: day) * 8 + 0.5) % 8]
    }

    /// A full moon nearer than 57.4 Earth radii (about 365,700 km).
    public static func isSupermoon(on day: CivilDate) -> Bool {
        moonIllumination(on: day) >= 97 && moonGeocentric(at: noonUTC(day)).distance < 57.4
    }

    // MARK: New and full moons

    private static let newMoonTerms = [-0.40720, 0.17241, 0.01608, 0.01039, 0.00739, -0.00514, 0.00208]
    private static let fullMoonTerms = [-0.40614, 0.17302, 0.01614, 0.01043, 0.00734, -0.00515, 0.00209]

    /// The instant of lunation *k* (Meeus ch. 49): whole *k* a new moon, *k* + 0.5 a full one,
    /// counted from the new moon of 2000-01-06.
    static func principalPhase(_ k: Double) -> Date {
        let t = k / 1236.85
        var jde = 2_451_550.09766 + 29.530588861 * k + 0.00015437 * t * t
            - 0.000000150 * t * t * t + 0.00000000073 * t * t * t * t
        let e = 1 - 0.002516 * t - 0.0000074 * t * t
        let m = 2.5534 + 29.10535670 * k - 0.0000014 * t * t
        let mp = 201.5643 + 385.81693528 * k + 0.0107582 * t * t + 0.00001238 * t * t * t
        let f = 160.7108 + 390.67050284 * k - 0.0016118 * t * t - 0.00000227 * t * t * t
        let om = 124.7746 - 1.56375588 * k + 0.0020672 * t * t
        let c = k == k.rounded(.down) ? newMoonTerms : fullMoonTerms
        jde += c[0] * sin(degrees: mp)
            + c[1] * e * sin(degrees: m)
            + c[2] * sin(degrees: 2 * mp)
            + c[3] * sin(degrees: 2 * f)
            + c[4] * e * sin(degrees: mp - m)
            + c[5] * e * sin(degrees: mp + m)
            + c[6] * e * e * sin(degrees: 2 * m)
        jde += -0.00111 * sin(degrees: mp - 2 * f)
            - 0.00057 * sin(degrees: mp + 2 * f)
            + 0.00056 * e * sin(degrees: 2 * mp + m)
            - 0.00042 * sin(degrees: 3 * mp)
            + 0.00042 * e * sin(degrees: m + 2 * f)
            + 0.00038 * e * sin(degrees: m - 2 * f)
            - 0.00024 * e * sin(degrees: 2 * mp - m)
            - 0.00017 * sin(degrees: om)
            - 0.00007 * sin(degrees: mp + 2 * m)
        jde += 0.00004 * sin(degrees: 2 * mp - 2 * f)
            + 0.00004 * sin(degrees: 3 * m)
            + 0.00003 * sin(degrees: mp + m - 2 * f)
            + 0.00003 * sin(degrees: 2 * mp + 2 * f)
            - 0.00003 * sin(degrees: mp + m + 2 * f)
            + 0.00003 * sin(degrees: mp - m + 2 * f)
            - 0.00002 * sin(degrees: mp - m - 2 * f)
            - 0.00002 * sin(degrees: 3 * mp + m)
            + 0.00002 * sin(degrees: 4 * mp)
        let planetary: [(Double, Double)] = [
            (325, 299.77 + 0.107408 * k - 0.009173 * t * t),
            (165, 251.88 + 0.016321 * k),
            (164, 251.83 + 26.651886 * k),
            (126, 349.42 + 36.412478 * k),
            (110, 84.66 + 18.206239 * k),
            (62, 141.74 + 53.303771 * k),
            (60, 207.14 + 2.453732 * k),
            (56, 154.84 + 7.306860 * k),
            (47, 34.52 + 27.261239 * k),
            (42, 207.19 + 0.121824 * k),
            (40, 291.34 + 1.844379 * k),
            (37, 161.72 + 24.198154 * k),
            (35, 239.56 + 25.513099 * k),
            (23, 331.55 + 3.592518 * k),
        ]
        jde += planetary.reduce(0) { $0 + $1.0 * 1e-6 * sin(degrees: $1.1) }
        return j2000.addingTimeInterval((jde - 2_451_545 - deltaTDays) * 86_400)
    }

    /// The first date after *day*, in *zone*, on which a new (*full* false) or full moon falls,
    /// and the days until it.
    public static func nextPrincipal(after day: CivilDate, full: Bool, in zone: TimeZone) -> (date: CivilDate, days: Int) {
        let elapsed = (noonUTC(day).timeIntervalSince(j2000) / 86_400).rounded(.down)
        var k = (elapsed / synodicMonth).rounded(.down) - 1 + (full ? 0.5 : 0)
        while true {
            let when = CivilDate(principalPhase(k), in: zone)
            if when > day { return (when, day.days(until: when)) }
            k += 1
        }
    }

    // MARK: Moonrise

    /// The moon's geocentric right ascension (hours), declination and distance (Earth radii):
    /// Schlyter's simplified orbit, good to about a tenth of a degree.
    static func moonGeocentric(at date: Date) -> (ra: Double, dec: Double, distance: Double) {
        let d = julianDay(at: date) - 2_451_543.5
        let node = pythonMod(125.1228 - 0.0529538083 * d, 360) * .pi / 180
        let incl = 5.1454 * .pi / 180
        let perigee = pythonMod(318.0634 + 0.1643573223 * d, 360)
        let a = 60.2666
        let e = 0.054900
        let m = pythonMod(115.3654 + 13.0649929509 * d, 360) * .pi / 180

        var ea = m + e * Foundation.sin(m) * (1 + e * cos(m))
        for _ in 0..<2 {
            ea -= (ea - e * Foundation.sin(ea) - m) / (1 - e * cos(ea))
        }
        let xv = a * (cos(ea) - e)
        let yv = a * (1 - e * e).squareRoot() * Foundation.sin(ea)
        let v = atan2(yv, xv)
        let r = hypot(xv, yv)

        let vw = v + perigee * .pi / 180
        let xh = r * (cos(node) * cos(vw) - Foundation.sin(node) * Foundation.sin(vw) * cos(incl))
        let yh = r * (Foundation.sin(node) * cos(vw) + cos(node) * Foundation.sin(vw) * cos(incl))
        let zh = r * Foundation.sin(vw) * Foundation.sin(incl)

        let ecl = (23.4393 - 3.563e-7 * d) * .pi / 180
        let ye = yh * cos(ecl) - zh * Foundation.sin(ecl)
        let ze = yh * Foundation.sin(ecl) + zh * cos(ecl)
        let ra = pythonMod(atan2(ye, xh) * 180 / .pi, 360)
        let dec = atan2(ze, hypot(xh, ye)) * 180 / .pi
        return (ra / 15, dec, (xh * xh + ye * ye + ze * ze).squareRoot())
    }

    /// The altitude of the moon's centre at rise and set: parallax and the disc's radius
    /// nearly cancel refraction.
    private static let moonRiseAltitude = 0.125

    private static func moonAltitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        let (ra, dec, _) = moonGeocentric(at: date)
        let jd = julianDay(at: date)
        let days = jd - 2_451_545
        let t = days / 36_525
        let gmst = pythonMod(280.46061837 + 360.98564736629 * days + 0.000387933 * t * t - t * t * t / 38_710_000, 360)
        let ha = (pythonMod(gmst + longitude, 360) - ra * 15) * .pi / 180
        let decR = dec * .pi / 180
        let lat = latitude * .pi / 180
        let s = Foundation.sin(decR) * Foundation.sin(lat) + cos(decR) * cos(lat) * cos(ha)
        return asin(max(-1, min(1, s))) * 180 / .pi
    }

    /// Moonrise and moonset on *day* in *zone*: the day scanned in 10-minute steps from local
    /// midnight for the altitude's crossings, each bisected. Either is nil when it does not
    /// happen that day, as about once a month it does not.
    ///
    /// The Pi steps and bisects in wall-clock time (Python's arithmetic on datetimes sharing a
    /// zone), so this does too: a spring-forward day is scanned over its 23 real hours.
    public static func moonTimes(on day: CivilDate, latitude: Double, longitude: Double, in zone: TimeZone) -> (rise: Date?, set: Date?) {
        let midnight = day.start(in: zone)
        func alt(_ wall: Double) -> Double {
            moonAltitude(at: instant(wall: wall, after: midnight, in: zone), latitude: latitude, longitude: longitude) - moonRiseAltitude
        }
        var rise: Date?
        var set: Date?
        var prevT = 0.0
        var prevA = alt(prevT)
        for i in 1...144 {
            let curT = Double(i) * 600
            let curA = alt(curT)
            if prevA == 0 || (prevA < 0 && 0 < curA) || (prevA > 0 && 0 > curA) {
                var lo = prevT, hi = curT, loA = prevA
                for _ in 0..<12 {
                    let mid = lo + (hi - lo) / 2
                    let midA = alt(mid)
                    if (loA < 0) == (midA < 0) { lo = mid; loA = midA } else { hi = mid }
                }
                let crossing = instant(wall: lo + (hi - lo) / 2, after: midnight, in: zone)
                if curA > prevA, rise == nil {
                    rise = crossing
                } else if curA < prevA, set == nil {
                    set = crossing
                }
            }
            prevT = curT
            prevA = curA
        }
        return (rise, set)
    }

    /// The instant the clocks in *zone* read *wall* seconds past *midnight*, as Python's
    /// zoneinfo reads it: a time in a spring-forward gap takes the offset from before the
    /// change, and a repeated one in the fall the first of its two instants.
    private static func instant(wall: Double, after midnight: Date, in zone: TimeZone) -> Date {
        let before = Double(zone.secondsFromGMT(for: midnight))
        let naive = midnight.addingTimeInterval(before + wall)  // the wall time read as UTC
        let candidates = Set([before, Double(zone.secondsFromGMT(for: naive.addingTimeInterval(-before)))])
        let valid = candidates.filter { Double(zone.secondsFromGMT(for: naive.addingTimeInterval(-$0))) == $0 }
        return naive.addingTimeInterval(-(valid.max() ?? before))
    }

    // MARK: Sun

    /// The Julian Day at 00:00 UT on *day* (Meeus ch. 7).
    static func julianDay(_ day: CivilDate) -> Double {
        var y = day.year, m = day.month
        if m <= 2 { y -= 1; m += 12 }
        let a = y / 100
        let b = 2 - a + a / 4
        return Double(Int(365.25 * Double(y + 4716))) + Double(Int(30.6001 * Double(m + 1))) + Double(day.day + b) - 1524.5
    }

    /// The Julian Day at *date*, to the whole second below it, as the Pi's
    /// `_julian_day_full` drops the microseconds.
    static func julianDay(at date: Date) -> Double {
        let day = CivilDate(date, in: utc)
        return julianDay(day) + date.timeIntervalSince(day.start(in: utc)).rounded(.down) / 86_400
    }

    /// The sun's declination (degrees) and the equation of time (minutes) at Julian Day *jd*.
    private static func declinationAndEquationOfTime(_ jd: Double) -> (Double, Double) {
        let n = jd - 2_451_545
        let l = pythonMod(280.460 + 0.9856474 * n, 360)
        let g = pythonMod(357.528 + 0.9856003 * n, 360) * .pi / 180
        let lambda = (l + 1.915 * Foundation.sin(g) + 0.020 * Foundation.sin(2 * g)) * .pi / 180
        let eps = (23.439 - 0.0000004 * n) * .pi / 180
        let declination = asin(Foundation.sin(eps) * Foundation.sin(lambda)) * 180 / .pi
        let ra = atan2(cos(eps) * Foundation.sin(lambda), cos(lambda)) * 180 / .pi
        let eot = pythonMod(4 * (l - ra) + 720, 1440) - 720
        return (declination, eot)
    }

    /// The sun's altitude in degrees at *date*, without refraction.
    public static func solarAltitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        let (declination, eot) = declinationAndEquationOfTime(julianDay(at: date))
        let day = CivilDate(date, in: utc)
        let minutes = date.timeIntervalSince(day.start(in: utc)).rounded(.down) / 60
        let ha = ((minutes + eot + 4 * longitude) / 4 - 180) * .pi / 180
        let lat = latitude * .pi / 180
        let dec = declination * .pi / 180
        let s = Foundation.sin(lat) * Foundation.sin(dec) + cos(lat) * cos(dec) * cos(ha)
        return asin(max(-1, min(1, s))) * 180 / .pi
    }

    /// Solar noon on *day* (its UTC date, as the Pi's `sun_times` takes it).
    public static func solarNoon(on day: CivilDate, longitude: Double) -> Date {
        let (_, eot) = declinationAndEquationOfTime(julianDay(day) + 0.5)
        return day.start(in: utc).addingTimeInterval((720 - 4 * longitude - eot) * 60)
    }

    /// Python's `%`: the result takes the divisor's sign.
    private static func pythonMod(_ a: Double, _ b: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: b)
        return r != 0 && (r < 0) != (b < 0) ? r + b : r
    }
}

extension CivilDate {
    /// Whole days from this date to *other*.
    func days(until other: CivilDate) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        return Int((other.start(in: utc).timeIntervalSince(start(in: utc)) / 86_400).rounded())
    }
}
