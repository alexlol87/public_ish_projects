import ApplicationServices
import CoreGraphics

/// Tells whether Mission Control is open by looking for it in the Dock's Accessibility tree.
///
/// While Mission Control is open the Dock's application element has a child group with identifier "mc" (the group
/// Hammerspoon's hs.spaces works with); otherwise it does not. On some Macs the Dock's AXExpose notifications never
/// arrive, so this is also how Mission Control is noticed at all (polled once a second by MissionControlObserver).
@MainActor
enum MissionControlTree {
    /// A Dock that stopped answering must not stall the main thread for long.
    private static let messagingTimeout: Float = 0.25

    /// The "mc" group, or nil when Mission Control is not showing.
    static func missionControlGroup(dockPID: pid_t) -> AXUIElement? {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, messagingTimeout)
        return children(of: dock).first { AXAccess.string($0, kAXIdentifierAttribute) == "mc" }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = AXAccess.copyValue(element, kAXChildrenAttribute), let items = value as? [AnyObject] else {
            return []
        }
        return items.compactMap { item -> AXUIElement? in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }
}
