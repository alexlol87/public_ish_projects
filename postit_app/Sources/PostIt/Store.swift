import AppKit

let yellowHex = "#FFF59D"

func alert(_ message: String) {
    NSApp.activate() // accessory apps are never active, the alert could open behind other windows
    let a = NSAlert()
    a.messageText = "PostIt"
    a.informativeText = message
    a.runModal()
}

extension NSColor {
    convenience init?(hex: String) {
        guard let v = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    var hex: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }

    var isLight: Bool {
        let c = usingColorSpace(.sRGB) ?? self
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.55
    }
}

/// One markdown file per note; order is the sorted filename (a timestamp).
final class Store {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PostIt")
    private let defaults = UserDefaults.standard
    private(set) var files: [String] = []
    private(set) var index = 0
    var text = ""
    private var unreadable = false // never write over a file we failed to read
    private var writeAlerted = false

    var url: URL { Store.dir.appendingPathComponent(files[index]) }

    init() {
        do { try FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true) }
        catch { alert("Cannot create notes folder: \(error.localizedDescription)") }
        files = ((try? FileManager.default.contentsOfDirectory(atPath: Store.dir.path)) ?? []).filter { $0.hasSuffix(".md") }.sorted()
        if files.isEmpty { newNote() } else {
            index = min(max(defaults.integer(forKey: "index"), 0), files.count - 1)
            loadText()
        }
    }

    private func loadText() {
        defaults.set(index, forKey: "index")
        do { text = try String(contentsOf: url, encoding: .utf8); unreadable = false }
        catch {
            text = ""; unreadable = true
            alert("Cannot read \(files[index]): \(error.localizedDescription)\nEdits to this note will not be saved.")
        }
    }

    func save() {
        guard !unreadable else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8); writeAlerted = false }
        catch {
            NSLog("PostIt: save failed: \(error)")
            if !writeAlerted { writeAlerted = true; alert("Cannot save note: \(error.localizedDescription)") }
        }
    }

    func newNote() {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let name = f.string(from: Date()) + ".md"
        do { try "".write(to: Store.dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        catch { alert("Cannot create note: \(error.localizedDescription)"); return }
        files.append(name)
        index = files.count - 1
        loadText()
    }

    func move(by d: Int) {
        let i = min(max(index + d, 0), files.count - 1)
        guard i != index else { return }
        index = i
        loadText()
    }

    /// Moves to the Trash rather than deleting, so a misclick is recoverable.
    func deleteCurrent() {
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        catch { alert("Cannot delete note: \(error.localizedDescription)"); return }
        colors[files[index]] = nil
        files.remove(at: index)
        if files.isEmpty { newNote() } else { index = min(index, files.count - 1); loadText() }
    }

    private var colors: [String: String] {
        get { defaults.dictionary(forKey: "colors") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "colors") }
    }

    var colorHex: String {
        get { colors[files[index]] ?? yellowHex }
        set { colors[files[index]] = newValue }
    }

    func resetColor() { colors[files[index]] = nil }
}
