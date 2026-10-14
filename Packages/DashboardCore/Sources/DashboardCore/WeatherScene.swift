import CoreGraphics
import Foundation

/// The weather illustration of the Agenda layout, as geometry: where the sun or moon sits,
/// its rays, the cloud banks, the lightning, and where rain and snow start. The view paints
/// it (gradients, glows, the moon photograph); this decides the composition, so it can be
/// tested and is the same at any screen size. Scenes follow the Pi's halftone themes: one per
/// OWM icon kind, by day and by night.
public struct WeatherScene: Sendable, Equatable {
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
    /// with the sun hidden).
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
}
