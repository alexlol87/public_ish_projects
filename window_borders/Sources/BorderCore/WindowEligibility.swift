import CoreGraphics

/// Which accessibility windows get a border. Dialogs, sheets, palettes, popovers and tiny helper windows are skipped:
/// a border around them is noise, and they come and go too fast for a per-window color to mean anything.
public enum WindowEligibility {
    /// Smallest window that still gets a border (filters out invisible 1×1 helper windows some apps create).
    static let minimumSize = CGSize(width: 60, height: 40)

    /// role == "AXWindow" && subrole == "AXStandardWindow" && width >= 60 && height >= 40
    /// && (layer == nil || layer == 0)
    public static func isStandardWindow(role: String?, subrole: String?, size: CGSize, layer: Int?) -> Bool {
        guard role == "AXWindow", subrole == "AXStandardWindow" else { return false }
        guard size.width >= minimumSize.width, size.height >= minimumSize.height else { return false }
        return layer == nil || layer == 0
    }
}
