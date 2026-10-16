import Foundation

/// A live clock's figures, split so a layout can set the AM/PM apart.
public enum ClockTime {
    /// "11:42" and "PM" in a 12-hour locale, "23:42" and nil in a 24-hour one.
    public static func parts(_ now: Date, in zone: TimeZone) -> (time: String, period: String?) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: now)
        let hour = c.hour ?? 0
        let minute = c.minute ?? 0
        let twelve = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
        guard twelve else { return (String(format: "%02d:%02d", hour, minute), nil) }
        return (String(format: "%d:%02d", hour % 12 == 0 ? 12 : hour % 12, minute), hour < 12 ? "AM" : "PM")
    }
}
