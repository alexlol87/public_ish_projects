#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

/// Plain-text editor with live preview stage 2. MarkdownStyler decides formatting; this only maps roles to attributes.
/// Use `.id(notePath)` so each Note gets a fresh view (and undo stack).
struct EditorView: NSViewRepresentable {
    let initialText: String
    let index: VaultIndex
    var notePath = ""
    var reveal: Reveal?
    var onRevealed: () -> Void = {}                     // called once `reveal` was applied, so the owner can clear it
    var onCursor: (Int) -> Void = { _ in }
    let onChange: (String) -> Void
    let onFollow: (WikiLink) -> Void
    var onTag: (String) -> Void = { _ in }              // ⌘-click on a #tag

    /// Asks the editor of Note `path` (and only that one) to select and scroll to a range once. `id` makes repeats of the
    /// same range fire again; the owner clears it from `onRevealed`, so it cannot fire again on a tab switch.
    struct Reveal: Equatable { let id = UUID(); let path: String; let range: NSRange }

    func makeCoordinator() -> Coordinator { Coordinator(index: index, notePath: notePath, onChange: onChange, onFollow: onFollow) }

    func makeNSView(context: Context) -> NSScrollView {
        // Default NSTextView is TextKit 2; never touch `.layoutManager` (drops to TextKit 1).
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let tv = LinkTextView(frame: .zero)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        tv.onPlainClick = { [weak c = context.coordinator] tv, offset in c?.plainClick(tv, at: offset) ?? false }
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
        if let reveal, reveal.path == notePath, reveal.id != context.coordinator.lastReveal, let tv = nsView.documentView as? NSTextView {
            context.coordinator.lastReveal = reveal.id
            let range = NSIntersectionRange(reveal.range, NSRange(location: 0, length: (tv.string as NSString).length))
            let done = onRevealed
            DispatchQueue.main.async { tv.setSelectedRange(range); tv.scrollRangeToVisible(range); tv.window?.makeFirstResponder(tv); done() }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        static let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let index: VaultIndex
        var root: URL { index.root }
        var onChange: (String) -> Void
        let notePath: String
        var onFollow: (WikiLink) -> Void
        var onTag: (String) -> Void = { _ in }
        var lastReveal: UUID?
        var onCursor: (Int) -> Void = { _ in }
        init(index: VaultIndex, notePath: String, onChange: @escaping (String) -> Void, onFollow: @escaping (WikiLink) -> Void) {
            self.index = index; self.notePath = notePath; self.onChange = onChange; self.onFollow = onFollow
        }

        private var token: NSObjectProtocol?
        func observeFormatActions(_ tv: NSTextView) {
            token = NotificationCenter.default.addObserver(forName: .formatAction, object: nil, queue: .main) { [weak tv] note in
                guard let tv, tv.window?.firstResponder === tv, let action = note.object as? FormatAction else { return }
                let edit = MarkdownStyler.apply(action, to: tv.string, selection: tv.selectedRange())
                // One replacement over the changed span = one undo step.
                let old = tv.string as NSString, new = edit.text as NSString
                var prefix = 0
                while prefix < min(old.length, new.length), old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
                var suffix = 0
                while suffix < min(old.length, new.length) - prefix, old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
                tv.insertText(new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix)),
                              replacementRange: NSRange(location: prefix, length: old.length - prefix - suffix))
                tv.setSelectedRange(edit.selection)
            }
        }
        deinit { token.map(NotificationCenter.default.removeObserver) }

        private var restyling = false

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !restyling, let tv = notification.object as? NSTextView else { return }
            onCursor(tv.selectedRange().location)
            restyle(tv)
        }

        private var inserted = false

        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            inserted = !(replacementString ?? "").isEmpty
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            restyle(tv)
            onChange(tv.string)
            // Typing after `[[` or `#` opens autocomplete; deleting must not, or the popup re-inserts what was just deleted.
            if inserted, LinkTextView.typedLinkPrefix(in: tv) != nil || LinkTextView.typedTagPrefix(in: tv) != nil { tv.complete(nil) }
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

        /// Plain click: a task checkbox ticks; a broken Link creates its missing Note (spec 42). Anything else is a normal click.
        func plainClick(_ tv: NSTextView, at offset: Int) -> Bool {
            if tickIfBox(tv, at: offset) { return true }
            guard let link = Vault.parse(tv.string).links.first(where: { NSLocationInRange(offset, $0.range) }),
                  index.brokenLinks(in: tv.string).contains(link) else { return false }
            onFollow(link)
            return true
        }

        func follow(_ tv: NSTextView, at offset: Int) {
            let parsed = Vault.parse(tv.string)
            if let link = parsed.links.first(where: { NSLocationInRange(offset, $0.range) }) { onFollow(link) }
            else if let tag = parsed.tags.first(where: { NSLocationInRange(offset, NSRange(location: $0.range.location, length: $0.range.length + 1)) }) { onTag(tag.name) }
        }

        func textView(_ tv: NSTextView, completions words: [String], forPartialWordRange range: NSRange, indexOfSelectedItem selected: UnsafeMutablePointer<Int>?) -> [String] {
            if LinkTextView.typedLinkPrefix(in: tv) == nil, let typedTag = LinkTextView.typedTagPrefix(in: tv) { return index.tagCompletions(for: typedTag.text) }
            guard let typed = LinkTextView.typedLinkPrefix(in: tv) else { return [] }
            return index.completions(for: typed.text)
        }

        static func attachment(image path: String, alt: String, root: URL?, note: String) -> NSTextAttachment {
            if let root, let url = Vault.resolveImage(path, note: note, root: root), let img = NSImage(contentsOf: url) {
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
            let pal = AppSettings.shared.palette
            tv.backgroundColor = NSColor(hex: pal.background)
            storage.setAttributes([.font: Self.baseFont, .foregroundColor: NSColor(hex: pal.text)], range: all)
            for span in result.styled {
                switch span.role {
                case .heading(let level):
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: 26 - CGFloat(level) * 3, weight: .bold), .foregroundColor: NSColor(hex: pal.heading)], range: span.range)
                case .bold:
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: Self.baseFont.pointSize, weight: .bold), range: span.range)
                case .italic:
                    storage.addAttribute(.obliqueness, value: 0.2, range: span.range)
                case .inlineCode, .codeBlock:
                    storage.addAttributes([.backgroundColor: NSColor.quaternaryLabelColor, .foregroundColor: NSColor(hex: pal.code)], range: span.range)
                case .image(let path, let alt):
                    // Widget: draw the image (or a placeholder) on the range's first character; the rest is hidden below.
                    // Unverified on macOS: .attachment on a non-U+FFFC character. Fallback: dim the raw text only.
                    storage.addAttribute(.attachment, value: Self.attachment(image: path, alt: alt, root: root, note: notePath), range: NSRange(location: span.range.location, length: 1))
                case .table(let rendered):
                    storage.addAttribute(.attachment, value: Self.attachment(text: rendered), range: NSRange(location: span.range.location, length: 1))
                case .taskBox(let checked):
                    // Checkbox widget on the `[ ]` range's first character (unverified on macOS; fallback: leave raw `[ ]`).
                    storage.addAttribute(.attachment, value: Self.attachment(text: checked ? "☑" : "☐"), range: NSRange(location: span.range.location, length: 1))
                case .tag:
                    storage.addAttributes([.foregroundColor: NSColor(hex: pal.tag), .backgroundColor: NSColor(hex: pal.tag).withAlphaComponent(0.12)], range: span.range)
                case .link:
                    storage.addAttributes([.foregroundColor: NSColor(hex: pal.link), .underlineStyle: NSUnderlineStyle.single.rawValue], range: span.range)
                }
            }
            // Broken Links (missing or ambiguous) are red.
            for link in index.brokenLinks(in: storage.string) {
                storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: link.range)
            }
            // Stage 2: markers off the cursor/selection lines are hidden (clear, ~0 width); the text itself is untouched.
            // Fallback if this misbehaves on macOS: dim instead (.foregroundColor tertiaryLabelColor).
            for marker in result.hidden {
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.1)], range: marker)
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
        guard let text = Vault.typedTagPrefix(inLineBeforeCursor: ns.substring(with: NSRange(location: line.location, length: cursor - line.location))) else { return nil }
        return (text, NSRange(location: cursor - (text as NSString).length, length: (text as NSString).length))
    }

    override var rangeForUserCompletion: NSRange { Self.typedLinkPrefix(in: self)?.range ?? Self.typedTagPrefix(in: self)?.range ?? super.rangeForUserCompletion }
}
#endif
