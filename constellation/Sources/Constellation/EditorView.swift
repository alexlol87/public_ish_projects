#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

/// Plain-text editor with live preview stage 2. MarkdownStyler decides formatting; this only maps roles to attributes.
/// Use `.id(notePath)` so each Note gets a fresh view (and undo stack).
struct EditorView: NSViewRepresentable {
    let initialText: String
    var root: URL? = nil  // with notePath: resolves image paths
    var notePath = ""
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange, root: root, notePath: notePath) }

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
        context.coordinator.observeFormatActions(tv)
        context.coordinator.restyle(tv)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.onChange = onChange }

    final class Coordinator: NSObject, NSTextViewDelegate {
        static let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        var onChange: (String) -> Void
        let root: URL?
        let notePath: String
        init(onChange: @escaping (String) -> Void, root: URL?, notePath: String) { self.onChange = onChange; self.root = root; self.notePath = notePath }

        private var token: NSObjectProtocol?
        func observeFormatActions(_ tv: NSTextView) {
            token = NotificationCenter.default.addObserver(forName: .formatAction, object: nil, queue: .main) { [weak tv] n in
                guard let tv, tv.window?.firstResponder === tv, let a = n.object as? FormatAction else { return }
                let e = MarkdownStyler.apply(a, to: tv.string, selection: tv.selectedRange())
                // One replacement over the changed span = one undo step.
                let old = tv.string as NSString, new = e.text as NSString
                var p = 0
                while p < min(old.length, new.length), old.character(at: p) == new.character(at: p) { p += 1 }
                var q = 0
                while q < min(old.length, new.length) - p, old.character(at: old.length - 1 - q) == new.character(at: new.length - 1 - q) { q += 1 }
                tv.insertText(new.substring(with: NSRange(location: p, length: new.length - p - q)),
                              replacementRange: NSRange(location: p, length: old.length - p - q))
                tv.setSelectedRange(e.selection)
            }
        }
        deinit { token.map(NotificationCenter.default.removeObserver) }

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

        static func attachment(image path: String, alt: String, root: URL?, note: String) -> NSTextAttachment {
            if let root, let url = ImagePaths.resolve(path, note: note, root: root), let img = NSImage(contentsOf: url) {
                let a = NSTextAttachment()
                let w = min(img.size.width, 480)
                a.image = img
                a.bounds = CGRect(x: 0, y: 0, width: w, height: img.size.height * w / max(img.size.width, 1))
                return a
            }
            return attachment(text: "[missing image: \(alt.isEmpty ? path : alt)]")
        }

        /// Monospace text drawn into an image (tables, placeholders).
        static func attachment(text: String) -> NSTextAttachment {
            let str = NSAttributedString(string: text, attributes: [.font: baseFont, .foregroundColor: NSColor.textColor])
            let size = str.size()
            let a = NSTextAttachment()
            a.image = NSImage(size: size, flipped: false) { rect in str.draw(in: rect); return true }
            a.bounds = CGRect(origin: .zero, size: size)
            return a
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
                case .image(let path, let alt):
                    // Widget: draw the image (or a placeholder) on the range's first character; the rest is hidden below.
                    // Unverified on macOS: .attachment on a non-U+FFFC character. Fallback: dim the raw text only.
                    storage.addAttribute(.attachment, value: Self.attachment(image: path, alt: alt, root: root, note: notePath), range: NSRange(location: s.range.location, length: 1))
                case .table(let rendered):
                    storage.addAttribute(.attachment, value: Self.attachment(text: rendered), range: NSRange(location: s.range.location, length: 1))
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
