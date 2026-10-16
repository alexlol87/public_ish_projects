import AppKit
import WebKit
import PostItCore

final class NotePanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() { super.resignKey(); onResignKey?() }
    // The app is never active (non-activating panel), so route shortcuts to the main menu ourselves.
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        super.performKeyEquivalent(with: e)
            || (e.modifierFlags.contains(.command) && NSApp.mainMenu?.performKeyEquivalent(with: e) == true)
    }
}

final class EditView: NSTextView {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class DragView: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class NoteController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSTextViewDelegate {
    let store = Store()
    let panel = NotePanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                          styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                          backing: .buffered, defer: false)
    let container = NSView()
    let scroll = NSScrollView()
    let textView = EditView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    let bar = DragView()
    let strip = DragView()
    let counter = NSTextField(labelWithString: "")
    var buttons: [NSButton] = []
    var pinButton: NSButton!, prevButton: NSButton!, nextButton: NSButton!
    var editing = false
    var pageReady = false
    var interactiveHit = false
    var dragStart: (mouse: NSPoint, origin: NSPoint)?
    var fg = "#1d1d1f"

    var pinned: Bool {
        get { UserDefaults.standard.object(forKey: "pinned") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pinned"); applyPin() }
    }

    override init() {
        super.init()
        setupPanel()
        setupEditor()
        setupWebView()
        setupBar()
        applyPin()
        refresh()
        if !panel.setFrameUsingName("PostItNote") { panel.center() }
        panel.setFrameAutosaveName("PostItNote")
        panel.onResignKey = { [weak self] in if self?.editing == true { self?.setEditing(false) } }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] e in
            self?.dragWindow(e)
            return e
        }
    }

    // MARK: setup

    func setupPanel() {
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .aqua)
        panel.minSize = NSSize(width: 190, height: 120)
        panel.isReleasedWhenClosed = false
        container.wantsLayer = true
        panel.contentView = container
        container.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    func pin(_ v: NSView, in parent: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: parent.leadingAnchor), v.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            v.topAnchor.constraint(equalTo: parent.topAnchor), v.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    func setupEditor() {
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 26)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.setEditing(false) }
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        pin(scroll, in: container)
        scroll.isHidden = true
    }

    func setupWebView() {
        webView.configuration.userContentController.add(self, name: "note")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground") // avoids a white flash before the page paints
        pin(webView, in: container)
        let html = Bundle.main.resourceURL!.appendingPathComponent("note.html")
        webView.loadFileURL(html, allowingReadAccessTo: URL(fileURLWithPath: "/")) // "/" so notes can show local images anywhere
    }

    func button(_ symbol: String, _ tip: String, _ sel: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: sel)
        b.isBordered = false
        b.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        buttons.append(b)
        return b
    }

    func setupBar() {
        pinButton = button("pin", "Pin on top", #selector(togglePin))
        prevButton = button("chevron.left", "Previous note", #selector(prev))
        nextButton = button("chevron.right", "Next note", #selector(next))
        counter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let views: [NSView] = [pinButton, prevButton, counter, nextButton,
                               button("plus", "New note", #selector(newNote)),
                               button("trash", "Delete note", #selector(deleteNote)),
                               button("paintpalette", "Note color", #selector(pickColor)),
                               button("arrow.counterclockwise", "Reset color to yellow", #selector(resetColor))]
        let stack = NSStackView(views: views)
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0, alpha: 0.08).cgColor
        bar.isHidden = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        strip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(strip)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor), bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor), bar.heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8), stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            strip.leadingAnchor.constraint(equalTo: container.leadingAnchor), strip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            strip.topAnchor.constraint(equalTo: container.topAnchor), strip.heightAnchor.constraint(equalToConstant: 12),
        ])
        strip.isHidden = true
    }

    // MARK: state

    func applyPin() {
        panel.level = pinned ? .floating : .normal
        panel.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        pinButton?.image = NSImage(systemSymbolName: pinned ? "pin" : "pin.slash", accessibilityDescription: "Pin on top")
    }

    /// Re-syncs every view with the store (note switch, color change, startup).
    func refresh() {
        let c = NSColor(hex: store.colorHex) ?? NSColor(hex: yellowHex)!
        let fgColor = NSColor(hex: c.isLight ? "#1D1D1F" : "#F5F5F7")!
        fg = fgColor.hex
        container.layer?.backgroundColor = c.cgColor
        textView.backgroundColor = c
        textView.insertionPointColor = fgColor
        textView.string = store.text
        textView.textColor = fgColor
        textView.typingAttributes[.foregroundColor] = fgColor
        textView.undoManager?.removeAllActions()
        webView.underPageBackgroundColor = c
        buttons.forEach { $0.contentTintColor = fgColor.withAlphaComponent(0.7) }
        counter.textColor = fgColor.withAlphaComponent(0.7)
        counter.stringValue = "\(store.index + 1)/\(store.files.count)"
        prevButton.isEnabled = store.index > 0
        nextButton.isEnabled = store.index < store.files.count - 1
        render()
    }

    func render() {
        guard pageReady else { return }
        let args = try! JSONSerialization.data(withJSONObject: [store.text, store.colorHex, fg])
        webView.evaluateJavaScript("render(...\(String(decoding: args, as: UTF8.self)))")
    }

    func setEditing(_ on: Bool) {
        guard on != editing else { return }
        editing = on
        scroll.isHidden = !on
        webView.isHidden = on
        strip.isHidden = !on
        if on { panel.makeFirstResponder(textView) } else { render() }
    }

    func show() { panel.orderFrontRegardless(); panel.makeKey() }

    // MARK: actions

    @objc func toggleVisible() { panel.isVisible ? panel.orderOut(nil) : show() }
    @objc func toggleEdit() { setEditing(!editing) }
    @objc func togglePin() { pinned.toggle() }
    @objc func prev() { store.move(by: -1); refresh() }
    @objc func next() { store.move(by: 1); refresh() }

    @objc func newNote() {
        store.newNote()
        refresh()
        show()
        setEditing(true)
    }

    @objc func deleteNote() {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Delete this note?"
        a.informativeText = "The file is moved to the Trash."
        a.alertStyle = .warning
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        store.deleteCurrent()
        refresh()
    }

    @objc func pickColor() {
        let p = NSColorPanel.shared
        p.hidesOnDeactivate = false // the app is never active
        p.level = .popUpMenu // above the floating note, or it opens behind it
        p.color = NSColor(hex: store.colorHex) ?? .yellow
        p.setTarget(self)
        p.setAction(#selector(colorChanged))
        p.orderFront(nil)
    }

    @objc func colorChanged() {
        store.colorHex = NSColorPanel.shared.color.hex
        refresh()
    }

    @objc func resetColor() { store.resetColor(); refresh() }

    // MARK: editor, hover, drag

    func textDidChange(_ n: Notification) {
        store.text = textView.string
        store.save()
    }

    @objc func mouseEntered(with event: NSEvent) { bar.isHidden = false }
    @objc func mouseExited(with event: NSEvent) { bar.isHidden = true }

    /// WKWebView ignores isMovableByWindowBackground, so view mode moves the window by hand.
    func dragWindow(_ e: NSEvent) {
        guard e.window === panel, !editing else { return }
        if e.type == .leftMouseDown {
            interactiveHit = false
            let inner = container.bounds.insetBy(dx: 6, dy: 6) // leave the resize edges alone
            let hit = panel.contentView?.superview?.hitTest(e.locationInWindow)
            let onWeb = inner.contains(container.convert(e.locationInWindow, from: nil)) && hit?.isDescendant(of: webView) == true
            dragStart = onWeb ? (NSEvent.mouseLocation, panel.frame.origin) : nil
        } else if let s = dragStart, !interactiveHit {
            let m = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: s.origin.x + m.x - s.mouse.x, y: s.origin.y + m.y - s.mouse.y))
        }
    }

    // MARK: web

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let t = body["t"] as? String else { return }
        switch t {
        case "down": interactiveHit = body["interactive"] as? Bool ?? false
        case "edit": setEditing(true)
        case "task":
            guard let i = body["i"] as? Int else { return }
            store.text = toggleTask(store.text, index: i)
            store.save()
            render()
        default: break
        }
    }

    func webView(_ w: WKWebView, didFinish _: WKNavigation!) {
        pageReady = true
        w.evaluateJavaScript("document.getElementById('base').href = \(Store.dir.absoluteString.debugDescription)")
        render()
    }

    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.navigationType == .linkActivated else { return .allow }
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return .cancel
    }
}
