#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

/// Plain-text editor with live preview stage 2. MarkdownStyler decides formatting; this only maps roles to attributes.
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

        private var restyling = false

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !restyling, let tv = notification.object as? NSTextView else { return }
            restyle(tv)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            restyle(tv)
            onChange(tv.string)
        }

        /// Attribute-only edits: they never touch characters, selection or the undo stack.
        func restyle(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            restyling = true
            defer { restyling = false }
            let cursor = MarkdownStyler.lineRange(covering: tv.selectedRange(), in: storage.string)
            let result = MarkdownStyler.style(storage.string, cursorLine: cursor)
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
            // Stage 2: markers off the cursor/selection lines are hidden (clear, ~0 width); the text itself is untouched.
            // Fallback if this misbehaves on macOS: dim instead (.foregroundColor tertiaryLabelColor).
            for h in result.hidden {
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.1)], range: h)
            }
            storage.endEditing()
        }
    }
}
#endif
