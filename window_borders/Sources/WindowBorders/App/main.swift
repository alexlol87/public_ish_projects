import AppKit

// Manual entry point instead of @main: the app has no storyboard/nib and must become an accessory (menu bar only)
// app before it finishes launching. Top-level code is not guaranteed to be MainActor-isolated in Swift 5 mode, but
// it does run on the main thread, which assumeIsolated asserts.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    // NSApplication.delegate is weak; this static keeps the delegate (and everything it owns) alive.
    AppDelegate.shared = delegate
    app.delegate = delegate
    // LSUIElement in Info.plist already does this for the .app bundle; this covers running the bare binary.
    _ = app.setActivationPolicy(.accessory)
    app.run()
}
