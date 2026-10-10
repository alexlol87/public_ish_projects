import AppKit
import ApplicationServices

/// Accessibility is the only permission the app needs: AX tells us where windows are, follows moves/resizes and
/// gives titles, so no Screen Recording permission is requested.
@MainActor
enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt and, as a side effect, adds the app to the Accessibility list (switched off), so the
    /// user only has to flip the switch instead of hunting for the app with "+".
    static func promptForAccessibility() {
        // String literal instead of kAXTrustedCheckOptionPrompt: that global is an unmanaged CFString var, which
        // Swift 6 compilers flag as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        _ = NSWorkspace.shared.open(url)
    }
}
