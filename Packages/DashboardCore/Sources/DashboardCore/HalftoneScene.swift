import CoreGraphics
import Foundation

/// The weather illustration of the Halftone layout, as a tone field: ink coverage from 0
/// (bare paper) to 1 (solid ink) at any point of the art pane.
///
/// The Pi's halftone themes draw a procedural scene per OWM icon and dither it. Here the
/// scene is analytic, so the TV can screen it at any resolution: the view samples `tone(at:)`
/// on a rotated grid and prints a dot whose area is the tone, an AM halftone. Linework that
/// must stay crisp (the sun's rays and ring, the lightning, stars, flakes) is drawn as vectors
/// on top; `body`, `rays` and `bolt` give their geometry.
public struct HalftoneScene: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case clear, fewClouds, clouds, overcast, rain, thunder, snow, mist
    }

    public var kind: Kind
    public var night: Bool
    public var size: CGSize

    public init(kind: Kind, night: Bool, size: CGSize) {
        self.kind = kind
        self.night = night
        self.size = size
    }

    /// The scene for an OWM icon code (`01d`, `10n`, ...).
    public init(icon: String, size: CGSize) {
        let night = icon.hasSuffix("n")
        let kind: Kind
        switch icon.prefix(2) {
        case "01": kind = .clear
        case "02": kind = .fewClouds
        case "03": kind = .clouds
        case "04": kind = .overcast
        case "09", "10": kind = .rain
        case "11": kind = .thunder
        case "13": kind = .snow
        case "50": kind = .mist
        default: kind = .clouds
        }
        self.init(kind: kind, night: night, size: size)
    }

    private var unit: CGFloat { min(size.width, size.height) }

    // MARK: Geometry

    /// The sun or moon: centre and radius, or nil when cloud hides it (overcast, rain, snow,
    /// thunder).
    public var body: (centre: CGPoint, radius: CGFloat)? {
        switch kind {
        case .clear:
            return (CGPoint(x: size.width * 0.5, y: size.height * 0.5), unit * 0.2)
        case .fewClouds, .mist:
            return (CGPoint(x: size.width * 0.36, y: size.height * 0.42), unit * 0.18)
        case .clouds:
            return (CGPoint(x: size.width * 0.32, y: size.height * 0.34), unit * 0.15)
        case .overcast, .rain, .thunder, .snow:
            return nil
        }
    }

    /// Cloud puffs (centre, radius), as fractions of the pane: one bank, two for overcast and
    /// the precipitating kinds.
    public var puffs: [(CGPoint, CGFloat)] {
        let w = size.width, h = size.height, u = unit
        func bank(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> [(CGPoint, CGFloat)] {
            [
                (CGPoint(x: x - 0.20 * u * s, y: y + 0.03 * u * s), 0.15 * u * s),
                (CGPoint(x: x, y: y - 0.06 * u * s), 0.21 * u * s),
                (CGPoint(x: x + 0.21 * u * s, y: y + 0.01 * u * s), 0.16 * u * s),
                (CGPoint(x: x + 0.36 * u * s, y: y + 0.07 * u * s), 0.10 * u * s),
                (CGPoint(x: x - 0.33 * u * s, y: y + 0.08 * u * s), 0.09 * u * s),
            ]
        }
        switch kind {
        case .clear, .mist: return []
        case .fewClouds: return bank(w * 0.62, h * 0.56, 0.9)
        case .clouds: return bank(w * 0.58, h * 0.52, 1.05)
        case .overcast:
            return bank(w * 0.32, h * 0.38, 0.9) + bank(w * 0.66, h * 0.58, 1.05)
        case .rain, .thunder, .snow:
            return bank(w * 0.32, h * 0.36, 0.85) + bank(w * 0.64, h * 0.43, 1.0)
        }
    }

    /// The sun's twelve rays, long and short in turn, as tapering wedges (none at night or
    /// with the sun hidden). Drawn as vectors: a halftone screen cannot hold a thin taper.
    public var rays: [[CGPoint]] {
        guard !night, let (c, r) = body else { return [] }
        return (0..<12).map { k in
            let angle = Double(k) * .pi / 6
            let outer = r * (k.isMultiple(of: 2) ? 1.9 : 1.5)
            let inner = r * 1.1
            let half = 0.16
            func at(_ radius: CGFloat, _ a: Double) -> CGPoint {
                CGPoint(x: c.x + radius * CGFloat(cos(a)), y: c.y + radius * CGFloat(sin(a)))
            }
            return [at(inner, angle - half), at(outer, angle), at(inner, angle + half)]
        }
    }

    /// The lowest point of the cloud banks, where rain and snow start.
    public var cloudBase: CGFloat {
        puffs.map { $0.0.y + $0.1 * 0.7 }.max() ?? size.height * 0.5
    }

    /// The lightning bolt's outline (thunder only).
    public var bolt: [CGPoint] {
        guard kind == .thunder else { return [] }
        let x = size.width * 0.54, y = cloudBase - unit * 0.02, u = unit
        return [
            CGPoint(x: x + 0.02 * u, y: y), CGPoint(x: x - 0.07 * u, y: y + 0.20 * u),
            CGPoint(x: x + 0.00 * u, y: y + 0.20 * u), CGPoint(x: x - 0.06 * u, y: y + 0.40 * u),
            CGPoint(x: x + 0.10 * u, y: y + 0.14 * u), CGPoint(x: x + 0.03 * u, y: y + 0.14 * u),
            CGPoint(x: x + 0.09 * u, y: y),
        ]
    }

    // MARK: Tone

    /// Ink coverage at *p* (pane coordinates, y down).
    public func tone(at p: CGPoint) -> Double {
        var t = sky(at: p)
        if let (c, r) = body {
            let d = hypot(p.x - c.x, p.y - c.y)
            if d < r {
                t = night ? moonDisc(p, c, r) : sunDisc(d, r)
            }
        }
        if let cloud = cloudTone(at: p) { t = cloud }
        if kind == .rain || kind == .thunder, p.y > cloudBase, rainStreak(p) {
            t = max(t, 0.82)
        }
        return min(max(t, 0), 1)
    }

    /// The sky: a graded mid-tone by day, near-black by night, heavier under weather.
    private func sky(at p: CGPoint) -> Double {
        let y = Double(p.y / max(size.height, 1))
        if night { return 0.86 - 0.16 * y }
        switch kind {
        case .clear, .fewClouds: return 0.40 - 0.28 * y
        case .clouds: return 0.36 - 0.14 * y
        case .mist:
            let band = 0.5 + 0.5 * sin(Double(p.y) / Double(unit) * 26)
            return 0.14 + 0.26 * band * (0.4 + 0.6 * y)
        case .overcast, .snow: return 0.48 - 0.12 * y
        case .rain: return 0.56 - 0.12 * y
        case .thunder: return 0.68 - 0.10 * y
        }
    }

    /// A lit disc: near paper at the centre, a little limb darkening.
    private func sunDisc(_ d: CGFloat, _ r: CGFloat) -> Double {
        let f = Double(d / r)
        return 0.03 + 0.17 * f * f
    }

    /// The moon: lit, with maria as soft darker patches.
    private func moonDisc(_ p: CGPoint, _ c: CGPoint, _ r: CGFloat) -> Double {
        let maria: [(CGFloat, CGFloat, CGFloat)] = [(-0.30, -0.25, 0.32), (0.18, -0.18, 0.26), (-0.05, 0.22, 0.30), (0.35, 0.30, 0.18)]
        var t = 0.06 + 0.14 * pow(Double(hypot(p.x - c.x, p.y - c.y) / r), 2)
        for (mx, my, mr) in maria {
            let d = hypot(p.x - (c.x + mx * r), p.y - (c.y + my * r)) / (mr * r)
            if d < 1 { t += 0.26 * Double(1 - d * d) }
        }
        return t
    }

    /// Inside a cloud: lit from above, darker underneath, and heavier for rain and storms.
    private func cloudTone(at p: CGPoint) -> Double? {
        var inside: (CGPoint, CGFloat)?
        for puff in puffs where hypot(p.x - puff.0.x, p.y - puff.0.y) < puff.1 {
            inside = puff
            break
        }
        guard let (c, r) = inside else { return nil }
        let base: Double
        switch kind {
        case .rain: base = 0.24
        case .thunder: base = 0.36
        case .overcast, .snow: base = 0.14
        default: base = night ? 0.30 : 0.04
        }
        let shade = Double(max(0, (p.y - (c.y - r)) / (2 * r)))
        return base + 0.40 * pow(shade, 1.6)
    }

    /// Slanting rain, in broken streaks.
    private func rainStreak(_ p: CGPoint) -> Bool {
        let u = Double(unit)
        let s = Double(p.x) + Double(p.y) * 0.32
        let lane = s.truncatingRemainder(dividingBy: u * 0.055)
        guard lane < u * 0.008 else { return false }
        let seg = (Double(p.y) + floor(s / (u * 0.055)) * u * 0.031).truncatingRemainder(dividingBy: u * 0.11)
        return seg < u * 0.07
    }
}
