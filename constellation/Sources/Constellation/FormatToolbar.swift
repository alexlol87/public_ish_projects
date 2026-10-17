#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

extension Notification.Name { static let formatAction = Notification.Name("constellation.formatAction") }

/// Fixed toolbar. Buttons carry the shortcuts, so a button click and its key press take the same path:
/// post `.formatAction`, which the active EditorView's Coordinator applies via MarkdownStyler.apply.
struct FormatToolbar: View {
    private static let items: [(FormatAction, String, KeyEquivalent?, EventModifiers)] = [
        (.bold, "B", "b", .command), (.italic, "I", "i", .command), (.underline, "U", "u", .command),
        (.strikethrough, "S", "x", [.command, .shift]), (.inlineCode, "`", "e", .command), (.codeBlock, "{}", "c", [.command, .option]),
        (.heading1, "H1", "1", .command), (.heading2, "H2", "2", .command), (.heading3, "H3", "3", .command),
        (.bulletList, "•", "8", [.command, .shift]), (.numberedList, "1.", "7", [.command, .shift]), (.taskList, "☐", "9", [.command, .shift]),
        (.quote, ">", ".", [.command, .shift]), (.link, "[[]]", "k", .command), (.table, "Table", nil, []),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.items.count, id: \.self) { i in
                let (action, label, key, mods) = Self.items[i]
                let button = Button(label) { NotificationCenter.default.post(name: .formatAction, object: action) }
                if let key { button.keyboardShortcut(key, modifiers: mods) } else { button }
            }
            Spacer()
        }.padding(6)
    }
}
#endif
