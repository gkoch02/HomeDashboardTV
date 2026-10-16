import Foundation

/// SF Symbol names for OpenWeatherMap icon codes (`01d`, `10n`, …), which is what the Pi
/// stores. The two digits are the condition, the letter is day or night.
public enum WeatherSymbol {
    public static func name(for icon: String) -> String {
        let night = icon.hasSuffix("n")
        switch icon.prefix(2) {
        case "01": return night ? "moon.stars.fill" : "sun.max.fill"
        case "02": return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case "03": return "cloud.fill"
        case "04": return "smoke.fill"
        case "09": return "cloud.drizzle.fill"
        case "10": return night ? "cloud.moon.rain.fill" : "cloud.sun.rain.fill"
        case "11": return "cloud.bolt.rain.fill"
        case "13": return "snowflake"
        case "50": return "cloud.fog.fill"
        default: return "thermometer.medium"
        }
    }
}

/// The sixteen-point compass name for a wind bearing in degrees: "NW", "SSE".
public enum Compass {
    public static func point(_ deg: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 22.5 + 0.5) % 16
        return points[i]
    }
}
