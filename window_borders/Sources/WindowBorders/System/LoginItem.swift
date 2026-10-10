import ServiceManagement

/// Launch at login through `SMAppService.mainApp` (macOS 13+), which registers the running app bundle itself.
/// It only works when the app runs from a real .app bundle (ideally in /Applications); a bare `swift run` binary
/// has no bundle to register, and `register()` throws.
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    /// Registered, but the user switched it off in System Settings > General > Login Items (or has not approved it
    /// yet); only they can turn it back on there.
    static var requiresApproval: Bool {
        status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            // Unregistering something that was never registered throws; there is nothing to undo then.
            guard status == .enabled || status == .requiresApproval else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
