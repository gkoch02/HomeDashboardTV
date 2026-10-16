import Foundation

/// The Pi's `fuzzyclock` theme's words for the time (`fuzzyclock_panel.fuzzy_time`): the minute
/// snapped to the nearest five, said as "half past seven" or "twenty five to nine", with
/// "midnight" and "noon" at the top of the twelve o'clock hours.
public enum FuzzyClock {
    private static let hours = [
        "twelve", "one", "two", "three", "four", "five",
        "six", "seven", "eight", "nine", "ten", "eleven",
    ]

    public static func phrase(_ now: Date, in zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: now)
        let hour = c.hour ?? 0
        var h = hour % 12
        var bucket = ((c.minute ?? 0) + 2) / 5 * 5
        if bucket == 60 {
            bucket = 0
            h = (h + 1) % 12
        }
        // As on the Pi, the clock hour decides, so 23:58 is "twelve o'clock", not midnight.
        if bucket == 0 && hour == 0 { return "midnight" }
        if bucket == 0 && hour == 12 { return "noon" }
        let name = hours[h], next = hours[(h + 1) % 12]
        switch bucket {
        case 0: return "\(name) o'clock"
        case 5: return "five past \(name)"
        case 10: return "ten past \(name)"
        case 15: return "quarter past \(name)"
        case 20: return "twenty past \(name)"
        case 25: return "twenty five past \(name)"
        case 30: return "half past \(name)"
        case 35: return "twenty five to \(next)"
        case 40: return "twenty to \(next)"
        case 45: return "quarter to \(next)"
        case 50: return "ten to \(next)"
        default: return "five to \(next)"
        }
    }

    /// How a phrase is coloured, as the panel splits it (`_phrase_segments`).
    public enum Ink: Sendable, Equatable { case primary, plain, secondary }

    /// The minutes in the primary accent, "past" or "to" plain, the hour in the secondary;
    /// "seven" of "seven o'clock" in the primary; "noon" and "midnight" wholly primary.
    public static func segments(_ phrase: String) -> [(text: String, ink: Ink)] {
        if phrase == "midnight" || phrase == "noon" { return [(phrase, .primary)] }
        if phrase.hasSuffix(" o'clock") {
            return [(String(phrase.dropLast(" o'clock".count)), .primary), (" o'clock", .plain)]
        }
        let words = phrase.split(separator: " ").map(String.init)
        guard let pivot = words.firstIndex(where: { $0 == "past" || $0 == "to" }),
              pivot > 0, pivot < words.count - 1 else { return [(phrase, .plain)] }
        return [
            (words[..<pivot].joined(separator: " "), .primary),
            (" \(words[pivot]) ", .plain),
            (words[(pivot + 1)...].joined(separator: " "), .secondary),
        ]
    }
}
