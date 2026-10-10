import ApplicationServices
import CoreGraphics
import Foundation

/// Private HIServices call returning the window server ID behind an AX window element. There is no public mapping
/// from AXUIElement to CGWindowID, and the ID is what overlays are ordered against; window managers (yabai,
/// Rectangle, AltTab, Hammerspoon) have relied on this symbol for a decade. If it ever fails, the tracker falls back
/// to matching pid + bounds against CGWindowList.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Small typed readers over AXUIElement. Every read is a synchronous IPC round trip to the target app, so all of them
/// return nil on any error (including the messaging timeout) instead of throwing; callers treat nil as "unknown".
enum AXAccess {
    /// Upper bound for one AX call. The default (6 s) lets a single hung app freeze our main thread for seconds.
    static let messagingTimeout: Float = 0.5
    /// For calls made to every app in a row (Mission Control's Space query), where a slow answer is better skipped.
    static let quickMessagingTimeout: Float = 0.1
    /// Not in the public header constants.
    static let fullScreenAttribute = "AXFullScreen"

    static func setMessagingTimeout(_ element: AXUIElement) {
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copyValue(element, attribute) as? NSNumber)?.boolValue
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    /// Window frame in global top-left coordinates (the same space CGWindowList uses).
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute),
              let size = size(element, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The app's windows on the active Space(s). Empty when the app has none; nil when the app did not answer
    /// (still launching, hung, or gone), which callers must not read as "all windows closed".
    static func windows(of app: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) {
        case .success:
            break
        case .noValue, .attributeUnsupported:
            return []
        default:
            return nil
        }
        guard let items = value as? [AnyObject] else { return [] }
        return items.compactMap { item -> AXUIElement? in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
