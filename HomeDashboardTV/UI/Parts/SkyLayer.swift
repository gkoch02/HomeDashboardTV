import MetalKit
import SwiftUI

/// A sky drawn by a Metal fragment shader, for the layouts whose backdrop is live: Skylight,
/// Aurora and Window.
///
/// The shader draws into a 16-bit float layer in extended sRGB rather than SwiftUI's 8-bit
/// one, so its long dark gradients keep their precision, and on tvOS 26 or later the layer
/// asks for extended dynamic range: where the Apple TV is putting out HDR, the shader's values
/// above 1 show brighter than the text's white, with no bloom around them, which is what an
/// OLED's pixels are for. The shader gets the screen's current headroom (1 where there is none,
/// so the SDR picture is exactly what it was) and spends it only on its brightest things: the
/// sun, lightning, the brightest folds of the aurora, the lights beyond the glass. `Sky.peak`
/// caps how far it goes.
///
/// *uniforms* is asked for the shader's inputs on every frame; the sky's own motion (summed
/// frame by frame in the layouts' clocks) lives in the closure's captures. Under Reduce Motion
/// (*paused*) the sky draws once per change of its inputs instead of thirty times a second.
/// The shaders' inputs are structs of `SIMD4<Float>` only, matching their Metal `float4`s field
/// for field, so the two layouts agree without a bridging header.
struct SkyLayer<Uniforms>: UIViewRepresentable {
    let fragment: String
    let paused: Bool
    let uniforms: (SkyFrame) -> Uniforms

    func makeUIView(context: Context) -> SkyView<Uniforms> {
        SkyView(fragment: fragment)
    }

    func updateUIView(_ view: SkyView<Uniforms>, context: Context) {
        view.uniforms = uniforms
        view.setPaused(paused)
    }
}

/// One frame of a sky: when, how big in points, the layer's scale, and the headroom to use.
struct SkyFrame {
    let date: Date
    let size: CGSize
    let scale: Float
    /// How bright the shader may go, as a multiple of the text's white: 1 to `Sky.peak`.
    let headroom: Float

    /// Every sky's first uniform: the size, the scale, and the sky's own *time*.
    func header(time: Float) -> SIMD4<Float> {
        SIMD4(Float(size.width), Float(size.height), scale, time)
    }
}

enum Sky {
    /// The most of the screen's headroom a sky uses: the brightest highlight is this many
    /// times the text's white. More would make a wall display a lamp.
    static let peak: Float = 2.5

    /// A colour's components in extended sRGB, as the shaders take them.
    static func rgb(_ color: Color) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}

/// The Metal view: one full-screen triangle, the sky's uniforms in a fragment buffer.
final class SkyView<Uniforms>: MTKView, MTKViewDelegate {
    var uniforms: ((SkyFrame) -> Uniforms)?

    private let pipeline: MTLRenderPipelineState?
    private let queue: MTLCommandQueue?

    init(fragment: String) {
        let device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        if let device, let library = device.makeDefaultLibrary() {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "skyVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        } else {
            pipeline = nil
        }
        super.init(frame: .zero, device: device)
        colorPixelFormat = .rgba16Float
        framebufferOnly = true
        isOpaque = true
        backgroundColor = .black
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        preferredFramesPerSecond = 30
        if let layer = layer as? CAMetalLayer {
            // The shaders' numbers are sRGB-encoded, as SwiftUI's were; extended, so that
            // values above 1 reach the compositor.
            layer.colorspace = CGColorSpace(name: CGColorSpace.extendedSRGB)
            if #available(tvOS 26, *) {
                layer.preferredDynamicRange = .high
            }
        }
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("SkyView is made in code") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let screen = window?.screen else { return }
        if #available(tvOS 26, *) {
            // How much of the screen's range the drawables use, so the compositor plans for it.
            layer.contentsHeadroom = CGFloat(min(Float(screen.potentialEDRHeadroom), Sky.peak))
        }
    }

    /// Under Reduce Motion the sky draws only when its inputs change.
    func setPaused(_ paused: Bool) {
        isPaused = paused
        enableSetNeedsDisplay = paused
        if paused { setNeedsDisplay() }
    }

    /// The headroom the shader may use: the screen's, up to `Sky.peak`; 1 (none) before tvOS 26,
    /// where the layer cannot ask for extended range and anything above 1 would only clip.
    private var headroom: Float {
        guard #available(tvOS 26, *), let screen = window?.screen else { return 1 }
        return max(1, min(Float(screen.currentEDRHeadroom), Sky.peak))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let uniforms, let pipeline, let queue, bounds.width > 0,
              let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let frame = SkyFrame(date: Date(), size: bounds.size,
                             scale: Float(drawableSize.width / bounds.width), headroom: headroom)
        var values = uniforms(frame)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&values, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
