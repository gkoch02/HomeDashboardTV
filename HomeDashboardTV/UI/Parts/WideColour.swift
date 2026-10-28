import SwiftUI

/// Display P3 for the inks that carry a layout: an Apple TV 4K in an HDR or Dolby Vision
/// Format puts out wide colour, and an OLED shows it, while its 4K SDR Format sends Rec.709
/// and these fall back to the nearest sRGB colour.
///
/// A hero ink keeps the numbers of the sRGB ink it replaces and declares them in P3: the
/// same red, green and blue amounts of purer primaries, so a saturated ink moves a little
/// further out on the same hue and a near-neutral one hardly moves. Text, grounds and
/// anything that must match the Pi's palette stay in sRGB.
extension Color {
    static func p3(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.displayP3, red: red, green: green, blue: blue)
    }

    /// A hue, saturation and brightness as a P3 ink, as `Color(hue:saturation:brightness:)`
    /// would make it in sRGB.
    static func p3(hue: Double, saturation: Double, brightness: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        PlatformColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
        return p3(Double(r), Double(g), Double(b))
    }
}
