import AppKit
import SwiftUI
import QuartzCore

/// A small layer-backed accent; all surrounding controls remain native SwiftUI.
struct AnimatedProjectIcon: NSViewRepresentable {
    @Environment(Preferences.self) private var preferences
    let symbol: String
    let color: ProjectColor
    var size: CGFloat = 44
    var image: NSImage? = nil
    func makeNSView(context: Context) -> ProjectIconView { ProjectIconView() }
    func updateNSView(_ view: ProjectIconView, context: Context) {
        view.configure(symbol: symbol, color: color.nsColor, size: size, suppliedImage: image)
        view.motionEnabled = preferences.layout.animateIcons
    }
}

final class ProjectIconView: NSView {
    private let glyph = CALayer()
    private var tracking: NSTrackingArea?
    private var didAnimate = false
    private var fullImage = false
    var motionEnabled = true { didSet { if !motionEnabled { layer?.removeAllAnimations() } } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(glyph)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(symbol: String, color: NSColor, size: CGFloat, suppliedImage: NSImage?) {
        fullImage = suppliedImage != nil
        if let suppliedImage {
            layer?.backgroundColor = NSColor.clear.cgColor
            glyph.contents = suppliedImage
            glyph.contentsGravity = .resizeAspect
            glyph.contentsScale = window?.backingScaleFactor ?? 2
            needsLayout = true
            return
        }
        layer?.cornerRadius = size * 0.23
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.48, weight: .medium)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?
            .withSymbolConfiguration(.init(paletteColors: [color])) {
            let pixels = Int(ceil(size * (window?.backingScaleFactor ?? 2)))
            if let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                let canvas = CGFloat(pixels)
                let scale = min(canvas / image.size.width, canvas / image.size.height)
                let width = image.size.width * scale
                let height = image.size.height * scale
                image.draw(in: NSRect(x: (canvas - width) / 2, y: (canvas - height) / 2, width: width, height: height))
                NSGraphicsContext.restoreGraphicsState()
                glyph.contents = bitmap.cgImage
            }
            glyph.contentsGravity = .resizeAspect
            glyph.contentsScale = window?.backingScaleFactor ?? 2
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyph.frame = fullImage ? bounds : bounds.insetBy(dx: bounds.width * 0.23, dy: bounds.height * 0.23)
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didAnimate, motionEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        didAnimate = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.35
        layer?.add(fade, forKey: "arrival")
        spring(from: 0.88, to: 1)
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { animateScale(to: 1.06) }
    override func mouseExited(with event: NSEvent) { animateScale(to: 1) }
    private func animateScale(to value: CGFloat) {
        guard motionEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let current = layer?.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.setValue(value, forKeyPath: "transform.scale")
        CATransaction.commit()
        spring(from: current, to: value)
    }
    private func spring(from: CGFloat, to: CGFloat) {
        let animation = CASpringAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = to
        animation.mass = 1
        animation.stiffness = 260
        animation.damping = 22
        animation.duration = animation.settlingDuration
        layer?.add(animation, forKey: "scale")
    }
}
