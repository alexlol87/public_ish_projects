#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

/// Plain-text editor with live preview stage 2. MarkdownStyler decides formatting; this only maps roles to attributes.
/// Use `.id(notePath)` so each Note gets a fresh view (and undo stack).
struct EditorView: NSViewRepresentable {
    let initialText: String
    let root: URL
    var notePath = ""
    var reveal: Reveal?
    var onCursor: (Int) -> Void = { _ in }
    let onChange: (String) -> Void
    let onFollow: (WikiLink) -> Void
    var onTag: (String) -> Void = { _ in }              // ⌘-click on a #tag
    var tagNames: (String) -> [String] = { _ in [] }    // `#` autocomplete source

    /// Asks the editor to select and scroll to a range once (`id` makes repeats of the same range fire again).
    struct Reveal: Equatable { let id = UUID(); let range: NSRange }

    func makeCoordinator() -> Coordinator { Coordinator(root: root, notePath: notePath, onChange: onChange, onFollow: onFollow) }

    func makeNSView(context: Context) -> NSScrollView {
        // Default NSTextView is TextKit 2; never touch `.layoutManager` (drops to TextKit 1).
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let tv = LinkTextView(frame: .zero)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        tv.onPlainClick = { [weak c = context.coordinator] tv, offset in c?.tickIfBox(tv, at: offset) ?? false }
        tv.onCommandClick = { [weak c = context.coordinator] tv, offset in c?.follow(tv, at: offset) }
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

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onCursor = onCursor
        context.coordinator.onFollow = onFollow
        context.coordinator.onTag = onTag
        context.coordinator.tagNames = tagNames
        if let reveal, reveal.id != context.coordinator.lastReveal, let tv = nsView.documentView as? NSTextView {
            context.coordinator.lastReveal = reveal.id
            let r = NSIntersectionRange(reveal.range, NSRange(location: 0, length: (tv.string as NSString).length))
            DispatchQueue.main.async { tv.setSelectedRange(r); tv.scrollRangeToVisible(r); tv.window?.makeFirstResponder(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        static let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let root: URL
        var onChange: (String) -> Void
        let notePath: String
        var onFollow: (WikiLink) -> Void
        var onTag: (String) -> Void = { _ in }
        var tagNames: (String) -> [String] = { _ in [] }
        var lastReveal: UUID?
        var onCursor: (Int) -> Void = { _ in }
        init(root: URL, notePath: String, onChange: @escaping (String) -> Void, onFollow: @escaping (WikiLink) -> Void) {
            self.root = root; self.notePath = notePath; self.onChange = onChange; self.onFollow = onFollow
        }

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
            onCursor(tv.selectedRange().location)
            restyle(tv)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            restyle(tv)
            onChange(tv.string)
            if LinkTextView.typedLinkPrefix(in: tv) != nil || LinkTextView.typedTagPrefix(in: tv) != nil { tv.complete(nil) }  // typing after `[[` opens autocomplete
        }

        /// Click on a task checkbox: ask the Vault for the edits (archive move, or a plain toggle) and apply them as one undo step.
        /// Edits to this Note go through the text view (so ⌘Z undoes them); edits to other files are written and their inverse is registered on the same undo group.
        func tickIfBox(_ tv: NSTextView, at offset: Int) -> Bool {
            let boxes = MarkdownStyler.style(tv.string).styled.filter { if case .taskBox = $0.role { return true }; return false }
            guard boxes.contains(where: { NSLocationInRange(offset, $0.range) }),
                  let edits = try? Vault.tick(taskAt: offset, in: tv.string, path: notePath, root: root), !edits.isEmpty else { return false }
            let others = edits.filter { $0.path != notePath }
            if let inverse = try? FileEdit.apply(others, root: root), !others.isEmpty {
                tv.undoManager?.registerUndo(withTarget: self) { _ in _ = try? FileEdit.apply(inverse, root: self.root) }
            }
            for e in edits where e.path == notePath {
                tv.insertText(e.text, replacementRange: e.range)
            }
            return true
        }

        func follow(_ tv: NSTextView, at offset: Int) {

            let parsed = NoteParser.parse(tv.string)
            if let l = parsed.links.first(where: { NSLocationInRange(offset, $0.range) }) { onFollow(l) }
            else if let t = parsed.tags.first(where: { NSLocationInRange(offset, NSRange(location: $0.range.location, length: $0.range.length + 1)) }) { onTag(t.name) }

        }

        func textView(_ tv: NSTextView, completions words: [String], forPartialWordRange range: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            if LinkTextView.typedLinkPrefix(in: tv) == nil, let t = LinkTextView.typedTagPrefix(in: tv) { return tagNames(t.text) }
            guard let typed = LinkTextView.typedLinkPrefix(in: tv) else { return [] }
            return (try? Vault.completions(for: typed.text, in: root)) ?? []
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
                case .taskBox(let checked):
                    // Checkbox widget on the `[ ]` range's first character (unverified on macOS; fallback: leave raw `[ ]`).
                    storage.addAttribute(.attachment, value: Self.attachment(text: checked ? "☑" : "☐"), range: NSRange(location: s.range.location, length: 1))
                case .tag:
                    storage.addAttributes([.foregroundColor: NSColor.systemTeal, .backgroundColor: NSColor.systemTeal.withAlphaComponent(0.12)], range: s.range)
                case .link:
                    storage.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: s.range)
                }
            }
            // Broken Links (missing or ambiguous) are red. shortcut: resolves per Link on every restyle; cache when Vaults get big.
            for l in NoteParser.parse(storage.string).links {
                if case .broken = (try? Vault.resolve(l.target, in: root)) ?? .broken(createPath: "") {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: l.range)
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

/// NSTextView that reports ⌘-clicks and completes only the text typed after `[[`.
final class LinkTextView: NSTextView {
    var onCommandClick: ((NSTextView, Int) -> Void)?
    /// Plain click; return true when it was handled (a task checkbox) so the cursor is not moved.
    var onPlainClick: ((NSTextView, Int) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        let offset = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard event.modifierFlags.contains(.command) else {
            if onPlainClick?(self, offset) == true { return }
            return super.mouseDown(with: event)
        }
        onCommandClick?(self, offset)
    }

    /// Text between an unclosed `[[` and the cursor on the current line, with its range.
    static func typedLinkPrefix(in tv: NSTextView) -> (text: String, range: NSRange)? {
        let ns = tv.string as NSString
        let cursor = tv.selectedRange().location
        let line = ns.lineRange(for: NSRange(location: min(cursor, ns.length), length: 0))
        let before = ns.substring(with: NSRange(location: line.location, length: cursor - line.location))
        guard let open = before.range(of: "[[", options: .backwards), !before[open.upperBound...].contains("]") else { return nil }
        let start = line.location + before.utf16.distance(from: before.startIndex, to: open.upperBound)
        return (ns.substring(with: NSRange(location: start, length: cursor - start)), NSRange(location: start, length: cursor - start))
    }


    /// Text typed after a `#` that would start a Tag (excluding the `#`), with its range.
    static func typedTagPrefix(in tv: NSTextView) -> (text: String, range: NSRange)? {
        let ns = tv.string as NSString
        let cursor = tv.selectedRange().location
        let line = ns.lineRange(for: NSRange(location: min(cursor, ns.length), length: 0))
        guard let text = TagIndex.typedPrefix(inLineBeforeCursor: ns.substring(with: NSRange(location: line.location, length: cursor - line.location))) else { return nil }
        return (text, NSRange(location: cursor - (text as NSString).length, length: (text as NSString).length))
    }

    override var rangeForUserCompletion: NSRange { Self.typedLinkPrefix(in: self)?.range ?? Self.typedTagPrefix(in: self)?.range ?? super.rangeForUserCompletion }

}
#endif
