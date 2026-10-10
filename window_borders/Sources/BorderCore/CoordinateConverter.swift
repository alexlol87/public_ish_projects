import CoreGraphics

/// Converts between the two global coordinate spaces macOS uses.
///
/// Accessibility and CGWindowList put the origin at the top-left of the primary display with y growing downward;
/// AppKit (NSWindow/NSScreen frames) puts it at the bottom-left of the primary display with y growing upward. Both
/// share the x axis and the primary display's extent, so the conversion is a flip around the primary display's
/// height and works for displays above, below, left or right of it (their coordinates just go negative).
public enum CoordinateConverter {
    /// AX/CG global rect (top-left origin of the primary display, y down) -> AppKit global (bottom-left, y up).
    /// primaryScreenHeight = NSScreen.screens[0].frame.height (the screen whose AppKit frame origin is .zero).
    public static func appKitRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        flip(rect, primaryScreenHeight: primaryScreenHeight)
    }

    public static func axRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        flip(rect, primaryScreenHeight: primaryScreenHeight)
    }

    public static func appKitPoint(fromAX point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    public static func axPoint(fromAppKit point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// The flip is its own inverse: the rect's far edge in one space becomes its origin edge in the other.
    private static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let standard = rect.standardized
        return CGRect(
            x: standard.minX,
            y: primaryScreenHeight - standard.maxY,
            width: standard.width,
            height: standard.height
        )
    }
}
