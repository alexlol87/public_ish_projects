import AppKit
import SwiftUI

/// What the onboarding view shows; flipped by the app delegate's trust polling.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var isTrusted = false
}

/// Explains why Accessibility access is needed and links to the right System Settings pane. The app delegate polls
/// for trust while this window is open and calls `showGranted()`, which shows a check mark and closes the window.
@MainActor
final class OnboardingWindowController {
    /// Called when the window closes, whether the user closed it or access was granted.
    var onClose: (() -> Void)?

    private let model = OnboardingModel()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        model.isTrusted = false
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        // Accessory apps are not activated by showing a window; without this it would open behind other apps.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows the "granted" state briefly so the user sees it worked, then closes.
    func showGranted() {
        guard let window, window.isVisible else { return }
        model.isTrusted = true
        _ = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.close()
            }
        }
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(
            model: model,
            openSettings: {
                // The prompt adds Window Borders to the Accessibility list (switched off), so the user only has to
                // flip its switch in the pane we open next.
                Permissions.promptForAccessibility()
                Permissions.openAccessibilitySettings()
            },
            quit: { NSApp.terminate(nil) }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Window Borders"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onClose?()
            }
        }
        return window
    }
}

/// The onboarding content.
@MainActor
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: model.isTrusted ? "checkmark.circle.fill" : "square.dashed")
                    .font(.system(size: 40))
                    .foregroundStyle(model.isTrusted ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isTrusted ? "You're all set" : "Window Borders needs Accessibility access")
                        .font(.title2.bold())
                    Text(model.isTrusted
                         ? "Accessibility access granted. Borders are on."
                         : "It draws a colored border around each window, so it has to know where your windows are.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.isTrusted {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("macwindow.on.rectangle",
                           "Accessibility lets Window Borders see where windows are and follow them as they move "
                           + "and resize.")
                    bullet("lock.shield",
                           "Nothing is recorded or sent anywhere. Everything stays on this Mac.")
                    bullet("eye.slash",
                           "No Screen Recording permission is needed: window titles come from Accessibility.")
                }

                Text("Click Open System Settings, then turn on Window Borders under Privacy & Security > "
                     + "Accessibility. This window closes by itself once access is granted.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Quit") { quit() }
                    Spacer()
                    Button("Open System Settings") { openSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
        }
    }
}
