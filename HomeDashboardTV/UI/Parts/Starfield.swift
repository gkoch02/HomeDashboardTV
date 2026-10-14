import SwiftUI

/// A fixed field of white stars, the same every launch for a seed, kept faint so it never
/// competes with what is drawn over it.
struct Starfield: View {
    var seed: UInt64 = 0x4D6F_6F6E

    var body: some View {
        Canvas { context, size in
            var random = SplitMix(seed: seed)
            for _ in 0..<220 {
                let x = random.unit() * size.width
                let y = random.unit() * size.height
                let r = 0.6 + random.unit() * random.unit() * 2.2
                let alpha = 0.15 + random.unit() * 0.55
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .ignoresSafeArea()
    }
}
