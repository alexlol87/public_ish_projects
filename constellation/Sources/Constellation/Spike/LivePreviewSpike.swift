// THROWAWAY (ticket 03). Delete this folder and the env check in main.swift once ticket 14 lands.
#if canImport(AppKit)
import AppKit
import ConstellationCore

final class LivePreviewSpike: NSObject, NSTextViewDelegate, NSApplicationDelegate {
    private var window: NSWindow!
    private var textView: NSTextView!
    private let sample = """
    # Live preview spike

    Some **bold**, *italic*, `code` and a [link](notes/a.md) here.

    ## Fenced

    ```swift
    let x = **not bold**
    ```

    Type, select across lines, undo and redo. Markers should hide off the cursor line.
    """

    static func run() {
        let app = NSApplication.shared
        let spike = LivePreviewSpike()
        app.delegate = spike
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSTextView(frame:) is TextKit 2 by default on macOS 12+; touching `.layoutManager` would drop to TextKit 1.
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as? NSTextView
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.string = sample
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = scroll
        window.title = "Live preview spike"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        restyle()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func textViewDidChangeSelection(_ notification: Notification) { restyle() }
    func textDidChange(_ notification: Notification) { restyle() }

    private var restyling = false

    private func restyle() {
        guard !restyling, let storage = textView.textStorage else { return }
        restyling = true
        defer { restyling = false }
        let text = storage.string
        let cursor = MarkdownStyler.lineRange(containing: textView.selectedRange().location, in: text)
        let result = MarkdownStyler.style(text, cursorLine: cursor)
        let base = textView.font ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
        let all = NSRange(location: 0, length: storage.length)

        // Attribute-only edits: they must not touch characters, selection or the undo stack.
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: NSColor.textColor], range: all)
        for s in result.styled {
            switch s.role {
            case .heading(let level):
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 26 - CGFloat(level) * 3, weight: .bold), range: s.range)
            case .bold:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .bold), range: s.range)
            case .italic:
                storage.addAttribute(.obliqueness, value: 0.2, range: s.range)
            case .inlineCode, .codeBlock:
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: s.range)
            case .link:
                storage.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: s.range)
            }
        }
        // Hiding spike v1: collapse to a tiny, clear glyph. Alternatives are listed in the ticket comments.
        for h in result.hidden {
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear], range: h)
        }
        storage.endEditing()
    }
}
#endif
