import Foundation

/// The Pi's `weatherglass` theme as numbers (`weatherglass_panel.py`): the barometer's scale and
/// words, the thermometer's scale and zones, the hygrometer's comfort band, the UV categories,
/// and the pressure trend.
public enum Weatherglass {
    // MARK: The barometer

    /// 950 to 1050 hPa over a 270° sweep: 950 at the lower left, 1000 at the top, 1050 at the
    /// lower right. The gap at the bottom carries the reading.
    public static let pressureRange = 950.0...1050.0
    public static let startDegrees = 225.0
    public static let sweepDegrees = 270.0

    /// The banjo barometer's words at their inch-of-mercury places (28.5 to 30.5 inHg).
    public static let words: [(hPa: Double, word: String)] = [
        (965, "STORMY"), (982, "RAIN"), (999, "CHANGE"), (1016, "FAIR"), (1033, "VERY DRY"),
    ]

    /// The dial angle for a pressure, in degrees anticlockwise from three o'clock (maths
    /// convention, +y up), clamped to the scale.
    public static func angle(hPa: Double) -> Double {
        let p = min(max(hPa, pressureRange.lowerBound), pressureRange.upperBound)
        let fraction = (p - pressureRange.lowerBound) / (pressureRange.upperBound - pressureRange.lowerBound)
        return startDegrees - sweepDegrees * fraction
    }

    /// "RISING +3", "FALLING -2" or "STEADY" against an earlier reading; nil without one. A
    /// change of a hectopascal or less is steady.
    public static func trend(_ current: Double, from previous: Double?) -> String? {
        guard let previous else { return nil }
        let delta = current - previous
        if delta > 1 { return String(format: "RISING +%.0f", delta) }
        if delta < -1 { return String(format: "FALLING %.0f", delta) }
        return "STEADY"
    }

    // MARK: The thermometer

    public struct Scale: Sendable, Equatable {
        public var low: Double
        public var high: Double
        public var symbol: String
        public var majors: [Double]
        /// The comfortable band, and where cold and hot begin.
        public var comfort: ClosedRange<Double>
        public var cold: Double
        public var hot: Double
    }

    public static func thermometer(isMetric: Bool) -> Scale {
        isMetric
            ? Scale(low: -20, high: 45, symbol: "°C", majors: [-20, -10, 0, 10, 20, 30, 40],
                    comfort: 16...24, cold: 0, hot: 30)
            : Scale(low: 0, high: 110, symbol: "°F", majors: [0, 20, 40, 60, 80, 100],
                    comfort: 60...75, cold: 32, hot: 85)
    }

    // MARK: The hygrometer and the UV index

    /// The hygrometer's green band.
    public static let comfortableHumidity = 40.0...60.0

    /// The EPA's UV categories.
    public static func uvCategory(_ uv: Double) -> String {
        switch uv {
        case ..<3: return "LOW"
        case ..<6: return "MODERATE"
        case ..<8: return "HIGH"
        case ..<11: return "VERY HIGH"
        default: return "EXTREME"
        }
    }
}

/// Pressure readings kept on the TV for the barometer's trend needle, as the Pi keeps its own
/// (`weatherglass_pressure_history.json`): at most one sample every 30 minutes, the last 48.
/// The trend compares now with the oldest sample between 1 and 36 hours old.
public struct PressureHistory: Codable, Sendable, Equatable {
    public struct Sample: Codable, Sendable, Equatable {
        public var time: Date
        public var hPa: Double
    }

    public private(set) var samples: [Sample]

    static let maxSamples = 48
    static let minGap: TimeInterval = 30 * 60
    static let minAge: TimeInterval = 3600
    static let maxAge: TimeInterval = 36 * 3600

    public init(samples: [Sample] = []) { self.samples = samples }

    /// Adds a reading taken at *time* (the weather's fetch time), unless the last sample is
    /// under half an hour older.
    public mutating func record(_ hPa: Double, at time: Date) {
        if let last = samples.last, time.timeIntervalSince(last.time) < Self.minGap { return }
        samples.append(Sample(time: time, hPa: hPa))
        samples = Array(samples.suffix(Self.maxSamples))
    }

    /// The oldest reading between 1 and 36 hours before *now*.
    public func previous(now: Date) -> Double? {
        samples
            .filter { (Self.minAge...Self.maxAge).contains(now.timeIntervalSince($0.time)) }
            .min { $0.time < $1.time }?
            .hPa
    }
}
