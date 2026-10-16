import SwiftUI

/// The sky's colour for the sun's altitude: Horizon's sky and the Light Cycle dial's band.
enum SkyColour {
    /// Day blue through gold, orange and plum to night, by altitude in degrees.
    private static let stops: [(h: Double, c: (Double, Double, Double))] = [
        (60, (0.10, 0.33, 0.66)),
        (25, (0.20, 0.47, 0.80)),
        (12, (0.46, 0.67, 0.89)),
        (5, (0.93, 0.80, 0.62)),
        (1, (0.99, 0.65, 0.36)),
        (-2, (0.93, 0.44, 0.30)),
        (-5, (0.68, 0.29, 0.38)),
        (-8, (0.34, 0.19, 0.39)),
        (-12, (0.13, 0.12, 0.29)),
        (-16, (0.05, 0.06, 0.15)),
        (-90, (0.025, 0.03, 0.08)),
    ]

    static func rgb(_ h: Double) -> (Double, Double, Double) {
        if h >= stops[0].h { return stops[0].c }
        for (a, b) in zip(stops, stops.dropFirst()) where h >= b.h {
            let t = (h - b.h) / (a.h - b.h)
            return (b.c.0 + (a.c.0 - b.c.0) * t, b.c.1 + (a.c.1 - b.c.1) * t, b.c.2 + (a.c.2 - b.c.2) * t)
        }
        return stops[stops.count - 1].c
    }

    static func color(_ h: Double) -> Color {
        let c = rgb(h)
        return Color(red: c.0, green: c.1, blue: c.2)
    }
}
