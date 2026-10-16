import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var note: NoteController!
    var pinItem: NSMenuItem!, loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        note = NoteController()
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "PostIt")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Show/Hide Note", #selector(NoteController.toggleVisible), target: note))
        menu.addItem(item("New Note", #selector(NoteController.newNote), target: note))
        pinItem = item("Pin on Top", #selector(NoteController.togglePin), target: note)
        loginItem = item("Launch at Login", #selector(toggleLogin), target: self)
        menu.addItem(pinItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(NSApplication.terminate(_:)), target: NSApp))
        statusItem.menu = menu
        note.show()
    }

    func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject?) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target
        return i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pinItem.state = note.pinned ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { alert("Launch at Login failed (it usually needs the app in /Applications): \(error.localizedDescription)") }
    }

    /// Accessory apps still need a main menu, otherwise Cmd+C/V/Z do nothing in the text view.
    func buildMainMenu() {
        let main = NSMenu()
        let app = NSMenu(title: "PostIt")
        app.addItem(item("Quit PostIt", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Toggle Edit Mode", #selector(NoteController.toggleEdit), key: "e", target: note))
        edit.addItem(.separator())
        edit.addItem(item("Undo", Selector(("undo:")), key: "z", target: nil))
        let redo = item("Redo", Selector(("redo:")), key: "z", target: nil)
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x", target: nil))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c", target: nil))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v", target: nil))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a", target: nil))
        for (title, menu) in [("PostIt", app), ("Edit", edit)] {
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.submenu = menu
            main.addItem(i)
        }
        NSApp.mainMenu = main
    }
}

let delegate = AppDelegate()
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
