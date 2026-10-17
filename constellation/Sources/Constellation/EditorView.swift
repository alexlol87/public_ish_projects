#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

/// Plain-text editor with live preview stage 1. MarkdownStyler decides formatting; this only maps roles to attributes.
/// Use `.id(notePath)` so each Note gets a fresh view (and undo stack).
struct EditorView: NSViewRepresentable {
    let initialText: String
    let root: URL
    var reveal: Reveal?
    let onChange: (String) -> Void
    let onFollow: (WikiLink) -> Void

    /// Asks the editor to select and scroll to a range once (`id` makes repeats of the same range fire again).
    struct Reveal: Equatable { let id = UUID(); let range: NSRange }

    func makeCoordinator() -> Coordinator { Coordinator(root: root, onChange: onChange, onFollow: onFollow) }

    func makeNSView(context: Context) -> NSScrollView {
        // Default NSTextView is TextKit 2; never touch `.layoutManager` (drops to TextKit 1).
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let tv = LinkTextView(frame: .zero)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        tv.onCommandClick = { [weak c = context.coordinator] tv, offset in c?.follow(tv, at: offset) }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = Coordinator.baseFont
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.string = initialText
        context.coordinator.restyle(tv)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onFollow = onFollow
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
        var onFollow: (WikiLink) -> Void
        var lastReveal: UUID?
        init(root: URL, onChange: @escaping (String) -> Void, onFollow: @escaping (WikiLink) -> Void) {
            self.root = root; self.onChange = onChange; self.onFollow = onFollow
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            restyle(tv)
            onChange(tv.string)
            if LinkTextView.typedLinkPrefix(in: tv) != nil { tv.complete(nil) }  // typing after `[[` opens autocomplete
        }

        func follow(_ tv: NSTextView, at offset: Int) {
            if let l = NoteParser.parse(tv.string).links.first(where: { NSLocationInRange(offset, $0.range) }) { onFollow(l) }
        }

        func textView(_ tv: NSTextView, completions words: [String], forPartialWordRange range: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            guard let typed = LinkTextView.typedLinkPrefix(in: tv) else { return [] }
            return (try? Vault.completions(for: typed.text, in: root)) ?? []
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
            // Broken Links (missing or ambiguous) are red. shortcut: resolves per Link on every restyle; cache when Vaults get big.
            for l in NoteParser.parse(storage.string).links {
                if case .broken = (try? Vault.resolve(l.target, in: root)) ?? .broken(createPath: "") {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: l.range)
                }
            }
            storage.endEditing()
        }
    }
}

/// NSTextView that reports ⌘-clicks and completes only the text typed after `[[`.
final class LinkTextView: NSTextView {
    var onCommandClick: ((NSTextView, Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return super.mouseDown(with: event) }
        let offset = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
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

    override var rangeForUserCompletion: NSRange { Self.typedLinkPrefix(in: self)?.range ?? super.rangeForUserCompletion }
}
#endif
