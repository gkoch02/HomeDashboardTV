import DashboardCore
import SwiftUI

/// One disc: the photograph where the sun lights it, a faint (earthshine) copy elsewhere.
struct MoonDisc: View {
    let fraction: Double
    let radius: CGFloat
    var halo = false

    /// How bright the unlit side's texture stays, as on the panel (`_EARTHSHINE_FACTOR`).
    private static let earthshine = 0.12

    var body: some View {
        ZStack {
            Color.black  // the disc is opaque: no star shows through the dark limb
            photo.opacity(Self.earthshine)
            photo.mask(LitShape(fraction: fraction))
        }
        .frame(width: radius * 2, height: radius * 2)
        .clipShape(Circle())
        .shadow(color: .white.opacity(halo ? 0.22 * MoonGeometry.litShare(fraction: fraction) : 0), radius: radius * 0.22)
    }

    private var photo: some View {
        Image("MoonPhoto", bundle: PlatformBundle.resources)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
    }
}

/// The sunlit region of a disc filling the rect (`MoonGeometry.litOutline`).
struct LitShape: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        let points = MoonGeometry.litOutline(fraction: fraction)
        guard let first = points.first else { return Path() }
        let r = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        func place(_ p: CGPoint) -> CGPoint { CGPoint(x: centre.x + p.x * r, y: centre.y + p.y * r) }
        var path = Path()
        path.move(to: place(first))
        for point in points.dropFirst() { path.addLine(to: place(point)) }
        path.closeSubpath()
        return path
    }
}
