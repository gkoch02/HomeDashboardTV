import CoreGraphics
import Foundation

/// The sunlit part of the moon's disc, as the Pi's `moon_render._lit_span` draws it.
///
/// For a lunation fraction `f`, the terminator on each scanline sits at `x = xlim * cos(2πf)`,
/// where `xlim` is the limb's half-width there. Waxing (`f < 0.5`) lights the right limb,
/// waning the left. The outline runs down the lit limb and back up the terminator.
public enum MoonGeometry {
    /// The lit region's outline on a unit disc centred at the origin (y down), or an empty
    /// array at new moon.
    public static func litOutline(fraction: Double, samples: Int = 96) -> [CGPoint] {
        let phase = fraction.truncatingRemainder(dividingBy: 1).magnitude
        let c = cos(2 * .pi * phase)
        if c >= 0.9999 { return [] }  // new moon: nothing lit
        let side: Double = phase < 0.5 ? 1 : -1
        var points: [CGPoint] = []
        for i in 0...samples {  // the limb, top to bottom
            let phi = -Double.pi / 2 + Double.pi * Double(i) / Double(samples)
            points.append(CGPoint(x: side * cos(phi), y: sin(phi)))
        }
        for i in (0...samples).reversed() {  // the terminator, bottom to top
            let phi = -Double.pi / 2 + Double.pi * Double(i) / Double(samples)
            points.append(CGPoint(x: side * c * cos(phi), y: sin(phi)))
        }
        return points
    }

    /// The lit share of the disc for *fraction*: the area `litOutline` encloses over π.
    public static func litShare(fraction: Double) -> Double {
        (1 - cos(2 * .pi * fraction)) / 2
    }
}

/// "9a", "11:30a", "2p": the Pi's `fmt_time`, which the moonphase panel and the day
/// cards both use.
public enum CompactTime {
    public static func string(_ date: Date, in zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "a" : "p"
        return minute == 0 ? "\(twelve)\(suffix)" : String(format: "%d:%02d%@", twelve, minute, suffix)
    }
}
