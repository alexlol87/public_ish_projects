import CoreGraphics

/// Where the border sits relative to the window: around it (normal windows) or within it (fullscreen windows,
/// where there is no room outside the screen edge).
public enum BorderPlacement: Sendable {
    case outside, inside
}

/// Everything the overlay needs to draw one border.
public struct BorderLayout: Equatable, Sendable {
    /// Same coordinate space as the windowFrame passed in.
    public let overlayFrame: CGRect
    /// In overlay-local coordinates (origin .zero); the stroke is CENTERED on this.
    public let strokeRect: CGRect
    /// Radius of strokeRect's rounded corners.
    public let cornerRadius: CGFloat
    public let lineWidth: CGFloat

    public init(overlayFrame: CGRect, strokeRect: CGRect, cornerRadius: CGFloat, lineWidth: CGFloat) {
        self.overlayFrame = overlayFrame
        self.strokeRect = strokeRect
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
    }
}

public enum BorderGeometry {
    /// .outside: overlayFrame = windowFrame grown by lineWidth on each side; the stroke band covers from `overlap`
    ///   points inside the window edge to (lineWidth - overlap) outside it, overlap = min(1, lineWidth / 2) (hides
    ///   anti-aliasing gaps); cornerRadius concentric = windowCornerRadius + lineWidth / 2 - overlap.
    /// .inside: overlayFrame = windowFrame, strokeRect = bounds inset by lineWidth / 2,
    ///   cornerRadius = max(0, windowCornerRadius - lineWidth / 2).
    public static func layout(
        windowFrame: CGRect, lineWidth: CGFloat, windowCornerRadius: CGFloat, placement: BorderPlacement
    ) -> BorderLayout {
        let width = max(0, lineWidth)
        let radius = max(0, windowCornerRadius)
        switch placement {
        case .outside:
            let overlap = min(1, width / 2)
            let overlayFrame = windowFrame.insetBy(dx: -width, dy: -width)
            let bounds = CGRect(origin: .zero, size: overlayFrame.size)
            // The window edge is `width` in from the overlay edge; the stroke's center line sits
            // (width / 2 - overlap) outside the window edge, so the curve stays concentric with the window's corner.
            let inset = width / 2 + overlap
            return BorderLayout(
                overlayFrame: overlayFrame,
                strokeRect: bounds.insetBy(dx: inset, dy: inset),
                cornerRadius: radius + width / 2 - overlap,
                lineWidth: width
            )
        case .inside:
            let bounds = CGRect(origin: .zero, size: windowFrame.size)
            return BorderLayout(
                overlayFrame: windowFrame,
                strokeRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                cornerRadius: max(0, radius - width / 2),
                lineWidth: width
            )
        }
    }

    /// Heuristic window corner radius: macOS 14/15 -> 10, macOS 26+ -> 16. Apps can't query the real radius, and
    /// it differs per window style, so settings also offer a custom value.
    public static func defaultWindowCornerRadius(osMajorVersion: Int) -> CGFloat {
        osMajorVersion >= 26 ? 16 : 10
    }

    /// Index of the screen with the largest intersection with `rect` (all frames in the same space), nil if none.
    /// Ties go to the lower index.
    public static func indexOfBestScreen(for rect: CGRect, screenFrames: [CGRect]) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, frame) in screenFrames.enumerated() {
            let overlap = rect.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Rounds to the nearest device pixel for a backing scale factor (e.g. 2.0), minimum one pixel.
    /// A non-positive scale is treated as 1.
    public static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        let factor = scale > 0 ? scale : 1
        return max(1 / factor, (value * factor).rounded() / factor)
    }
}
