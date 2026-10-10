import AppKit
import QuartzCore

/// Content view of a `BorderWindow`: one rounded-rectangle stroke drawn by a `CAShapeLayer`.
///
/// A shape layer is rendered by Core Animation, so a resize only swaps the path: there is no `draw(_:)` pass, no
/// bitmap to invalidate and nothing for AppKit to redraw while a window is being dragged.
@MainActor
final class BorderView: NSView {
    private let shapeLayer: CAShapeLayer
    /// Masks out covered parts of the stroke (floating layering); nil when the whole border is visible.
    private var maskLayer: CAShapeLayer?
    private var coveredRects: [CGRect] = []

    override init(frame frameRect: NSRect) {
        shapeLayer = CAShapeLayer()
        super.init(frame: frameRect)
        // Layer-backed (AppKit owns the root layer and keeps it sized to the view); the stroke is our own sublayer.
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = nil
        // Belt and braces next to `CATransaction.setDisableActions(true)`: no property of the stroke ever
        // animates, otherwise a moved/resized border would visibly slide after its window.
        let noAnimation: [String: CAAction] = [
            "bounds": NSNull(), "position": NSNull(), "path": NSNull(), "lineWidth": NSNull(),
            "strokeColor": NSNull(), "contentsScale": NSNull(), "hidden": NSNull(),
        ]
        shapeLayer.actions = noAnimation
        layer?.addSublayer(shapeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BorderView is created in code only")
    }

    /// Updates the stroke. Callers wrap this in a CATransaction with actions disabled.
    /// - Parameters:
    ///   - size: overlay window size; the shape layer is sized explicitly because it is our sublayer.
    ///   - scale: backing scale factor; a shape layer rasterizes at `contentsScale`, so 1.0 would look blurry on
    ///     Retina displays.
    func update(size: CGSize, strokeRect: CGRect, cornerRadius: CGFloat, lineWidth: CGFloat,
                color: CGColor, scale: CGFloat) {
        if shapeLayer.superlayer == nil {
            // AppKit had not created the backing layer yet when init ran.
            layer?.addSublayer(shapeLayer)
        }
        shapeLayer.frame = CGRect(origin: .zero, size: size)
        shapeLayer.path = Self.roundedPath(in: strokeRect, radius: cornerRadius)
        shapeLayer.lineWidth = lineWidth
        shapeLayer.strokeColor = color
        shapeLayer.contentsScale = scale
        updateMask()
    }

    /// See `BorderWindow.setCoveredRects`. Callers wrap this in a CATransaction with actions disabled.
    func setCoveredRects(_ rects: [CGRect]) {
        coveredRects = rects
        updateMask()
    }

    /// The mask is the overlay minus the union of the covered rects (the winding rule merges overlapping rects).
    private func updateMask() {
        let bounds = shapeLayer.frame
        let covered = coveredRects.filter { $0.intersects(bounds) }
        guard !covered.isEmpty else {
            shapeLayer.mask = nil
            maskLayer = nil
            return
        }
        let mask = maskLayer ?? CAShapeLayer()
        mask.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
        mask.frame = CGRect(origin: .zero, size: bounds.size)
        let coveredPath = CGMutablePath()
        coveredPath.addRects(covered)
        mask.path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil).subtracting(coveredPath)
        mask.fillColor = CGColor(gray: 0, alpha: 1)
        maskLayer = mask
        shapeLayer.mask = mask
    }

    /// Moving the overlay to a screen with a different scale re-rasterizes the stroke at the new resolution.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let scale = window?.backingScaleFactor else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.contentsScale = scale
        CATransaction.commit()
    }

    /// `CGPath(roundedRect:)` traps when a corner radius exceeds half the rect's side, so the radius is clamped;
    /// a degenerate rect (tiny window, huge line width) draws nothing instead.
    private static func roundedPath(in rect: CGRect, radius: CGFloat) -> CGPath? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let clamped = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: nil)
    }
}
