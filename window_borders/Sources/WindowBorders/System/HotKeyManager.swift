import Carbon
import Foundation

/// Four-char code "WBHK" identifying our hot key in Carbon events (other code in the process could register its own).
private let hotKeySignature: OSType = 0x5742_484B

/// Carbon event handler. A file-level function, not a closure, so it converts to a C function pointer without
/// capturing anything (and without inheriting actor isolation); the manager comes back through `userData`.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == OSStatus(noErr), hotKeyID.signature == hotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    // Application-target Carbon events are dispatched on the main thread's run loop.
    MainActor.assumeIsolated {
        manager.handlePress()
    }
    return OSStatus(noErr)
}

/// The global ⌃⌥⌘B shortcut. Carbon's RegisterEventHotKey is still the only public API for a system-wide hot key
/// that needs neither Accessibility nor Input Monitoring, and it consumes the key press so the front app never sees it.
@MainActor
final class HotKeyManager {
    /// Called on the main thread each time the shortcut is pressed.
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// False when registration failed, e.g. another app already owns ⌃⌥⌘B.
    var isRegistered: Bool {
        hotKeyRef != nil
    }

    func register() {
        guard hotKeyRef == nil else { return }
        if handlerRef == nil {
            let eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            ]
            var handler: EventHandlerRef?
            // passUnretained: the AppDelegate owns this manager for the app's lifetime, and unregister() removes the
            // handler before it could go away.
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyEventHandler,
                eventTypes.count,
                eventTypes,
                Unmanaged.passUnretained(self).toOpaque(),
                &handler
            )
            guard status == OSStatus(noErr) else {
                NSLog("Window Borders: InstallEventHandler failed (%d)", status)
                return
            }
            handlerRef = handler
        }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(controlKey | optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == OSStatus(noErr), let ref else {
            NSLog("Window Borders: could not register ⌃⌥⌘B (%d); another app may be using it", status)
            return
        }
        hotKeyRef = ref
    }

    func unregister() {
        if let hotKeyRef {
            _ = UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            _ = RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    fileprivate func handlePress() {
        onPress?()
    }
}
