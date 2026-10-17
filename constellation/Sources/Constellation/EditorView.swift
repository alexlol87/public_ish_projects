#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

/// Plain-text editor with live preview stage 1. MarkdownStyler decides formatting; this only maps roles to attributes.
/// Use `.id(notePath)` so each Note gets a fresh view (and undo stack).
struct EditorView: NSViewRepresentable {
    let initialText: String
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        // Default NSTextView is TextKit 2; never touch `.layoutManager` (drops to TextKit 1).
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = Coordinator.baseFont
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.string = initialText
        context.coordinator.restyle(tv)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.onChange = onChange }

    final class Coordinator: NSObject, NSTextViewDelegate {
        static let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        var onChange: (String) -> Void
        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            restyle(tv)
            onChange(tv.string)
        }

        /// Attribute-only edits: they never touch characters, selection or the undo stack.
        func restyle(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let result = MarkdownStyler.style(storage.string)  // no cursorLine: stage 1 keeps every marker visible
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([.font: Self.baseFont, .foregroundColor: NSColor.textColor], range: all)
            for s in result.styled {
                switch s.role {
                case .heading(let level):
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 26 - CGFloat(level) * 3, weight: .bold), range: s.range)
                case .bold:
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: Self.baseFont.pointSize, weight: .bold), range: s.range)
                case .italic:
                    storage.addAttribute(.obliqueness, value: 0.2, range: s.range)
                case .inlineCode, .codeBlock:
                    storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: s.range)
                case .link:
                    storage.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: s.range)
                }
            }
            // Stage 1: markers dimmed, not hidden (ticket 14 hides them off the cursor line).
            for h in result.hidden { storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: h) }
            storage.endEditing()
        }
    }
}
#endif
