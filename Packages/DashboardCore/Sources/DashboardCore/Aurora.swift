import Foundation

/// The Aurora layout's model: curtains of light whose colour is the air and whose motion is
/// the wind. Aurora has no Pi theme behind it; it is drawn for an OLED TV.
public enum Aurora {
    /// The curtain's colours, as hues in degrees: its bright lower edge, and the fringe at its top.
    public struct Curtain: Sendable, Equatable {
        public var edge: Double
        public var fringe: Double
    }

    /// The edge's hue along the AQI: green in good air, amber by the top of moderate, red by
    /// unhealthy, on to magenta.
    private static let stops: [(aqi: Double, hue: Double)] = [
        (0, 158), (50, 142), (100, 52), (150, 28), (200, -10), (300, -40),
    ]

    /// The curtain for the air now: a real aurora's green with violet tops in good air, warming
    /// as the AQI climbs, its fringe a deeper shade of its edge once the air is no longer good.
    /// Every step of the AQI moves both hues a little, never a jump. Without a reading, the
    /// green of good air.
    public static func curtain(aqi: Int?) -> Curtain {
        let a = min(max(Double(aqi ?? 25), 0), 300)
        var hue = stops[stops.count - 1].hue
        for (p, q) in zip(stops, stops.dropFirst()) where a <= q.aqi {
            hue = p.hue + (q.hue - p.hue) * (a - p.aqi) / (q.aqi - p.aqi)
            break
        }
        let edge = wrap(hue)
        let violet = 285.0
        let deeper = wrap(edge - 30)
        // Leaving good air, the violet turns down the wheel through blue to the deeper shade:
        // always that way round, so it never swings across to the far side.
        let t = min(max((a - 40) / 50, 0), 1)
        let down = wrap(deeper - violet) - 360
        return Curtain(edge: edge, fringe: wrap(violet + down * t))
    }

    /// How restless the curtains are, from the wind: 0 in a calm, 1 at 25 mph (11 m/s), at most
    /// 1.6. A moderate stir without a reading.
    public static func unrest(windSpeed: Double?, isMetric: Bool) -> Double {
        guard let speed = windSpeed else { return 0.3 }
        let mph = isMetric ? speed * 2.23694 : speed
        return min(max(mph / 25, 0), 1.6)
    }

    static func wrap(_ hue: Double) -> Double {
        let h = hue.truncatingRemainder(dividingBy: 360)
        return h < 0 ? h + 360 : h
    }
}
