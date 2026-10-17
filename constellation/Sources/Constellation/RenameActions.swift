#if canImport(AppKit)
import AppKit
import ConstellationCore

/// Modal one-line text prompt; nil when cancelled or empty.
func promptText(_ title: String, initial: String = "") -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.stringValue = initial
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let s = field.stringValue.trimmingCharacters(in: .whitespaces)
    return s.isEmpty ? nil : s
}

/// Applies a command's `[FileEdit]` and registers the inverse with the window's UndoManager, so one ⌘Z (and one redo,
/// registered while undoing) covers every file touched. `after` runs after each application (refresh tree, indexes, tabs).
enum UndoableEdits {
    private final class Target {}
    private static let target = Target()

    static func run(_ edits: [FileEdit], root: URL, undo: UndoManager?, name: String, after: @escaping ([FileEdit]) -> Void) throws {
        let inverse = try FileEdit.apply(edits, root: root)
        after(edits)
        undo?.registerUndo(withTarget: target) { _ in try? run(inverse, root: root, undo: undo, name: name, after: after) }
        undo?.setActionName(name)
    }
}
#endif
