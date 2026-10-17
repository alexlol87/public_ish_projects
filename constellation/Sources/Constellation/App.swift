#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

struct ConstellationApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
            .commands { CommandGroup(after: .sidebar) { OpenGraphButton() } }
        Window("Graph", id: "graph") { GraphView() }
    }
}

struct OpenGraphButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Graph") { openWindow(id: "graph") }.keyboardShortcut("g", modifiers: .command) }
}

struct RootView: View {
    @State private var root: URL?
    @State private var tree: VaultNode?
    @State private var selection: String?
    @State private var tabs: NoteTabs?
    @State private var error: String?
    @State private var watcher: VaultWatcher?
    @State private var reveal: EditorView.Reveal?
    @State private var backlinks: [Backlink] = []
    @State private var query = ""
    @State private var cursor = 0
    @State private var relations: (title: String, rel: EndpointRelations)?
    @State private var search: SearchIndex?
    @State private var tags: TagIndex?
    @State private var sidebarTab = SidebarTab.files
    @State private var tagFilter: String?
    @State private var epoch = 0  // bumped after a rename so the editor reloads from the rewritten files
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            if let tree {
                Picker("", selection: $sidebarTab) { ForEach(SidebarTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 8)
                if sidebarTab == .tags, let tags { TagsView(index: tags, selected: $tagFilter, rename: { old in
                    if let new = promptText("Rename tag #\(old) to", initial: old) { perform("Rename Tag") { try Vault.renameTag(old, to: new.trimmingCharacters(in: CharacterSet(charactersIn: "#")), in: $0) } }
                }) { hit in go(hit.path, reveal: NSRange(location: hit.offset, length: 0)) } } else {
                TextField("Search", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 8)
                if !query.isEmpty, let search { SearchResultsView(results: search.search(query)) { m in
                    try? tabs?.open(m.path); reveal = .init(range: NSRange(location: m.offset, length: m.hit.length))
                } openNote: { path in try? tabs?.open(path) } } else {
                List(tree.children, children: \.optionalChildren, selection: $selection) { node in
                    Label(node.name, systemImage: node.isFolder ? "folder" : "doc.text")
                        .contextMenu { if !node.isFolder { noteMenu(node.relativePath) } }
                } } }
            } else {
                VStack {
                    Button("Create vault…") { chooseFolder(create: true) }
                    Button("Open vault…") { chooseFolder(create: false) }
                }.padding()
            }
        } detail: {
            if let error {
                Text(error).foregroundStyle(.red).padding()
            } else if let tabs, let active = tabs.active {
                VStack(spacing: 0) {
                    HStack {
                        ForEach(tabs.paths, id: \.self) { path in
                            HStack(spacing: 4) {
                                Button(path.split(separator: "/").last.map(String.init) ?? path) { try? self.tabs?.open(path) }
                                    .buttonStyle(.plain).fontWeight(path == active ? .bold : .regular)
                                Button("x") { try? self.tabs?.close(path) }.buttonStyle(.plain)
                            }
                        }
                        Spacer()
                    }.padding(6)
                    Divider()
                    if tabs.conflict(active) != nil {
                        HStack {
                            Text("This Note changed on disk.")
                            Button("Reload from disk") { try? self.tabs?.resolveConflict(active, reload: true) }
                            Button("Keep mine") { try? self.tabs?.resolveConflict(active, reload: false) }
                            Spacer()
                        }.padding(6).background(Color.yellow.opacity(0.25))
                    }
                    FormatToolbar()
                    Divider()
                    EditorView(initialText: tabs.text(active) ?? "", root: root!, notePath: active, reveal: reveal, onCursor: { cursor = $0; refreshRelations() },
                               onChange: { self.tabs?.edit(active, text: $0) }, onFollow: { follow($0) },
                               onTag: { tagFilter = $0.lowercased(); sidebarTab = .tags },
                               tagNames: { tags?.completions(for: $0) ?? [] })
                        .id("\(active)#\(tabs.revision(active))#\(epoch)")
                }
            } else {
                Text("Select a Note").foregroundStyle(.secondary)
            }
        }
        .inspector(isPresented: .constant(tabs?.active != nil)) { inspector }
        .onChange(of: tabs?.active) { _, _ in refreshBacklinks(); cursor = 0; refreshRelations() }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear {
            // Lets the CI launch test open a fixture Vault without the open panel.
            if let path = ProcessInfo.processInfo.environment["CONSTELLATION_VAULT"] { open(URL(fileURLWithPath: path)) }
            else if let url = Vault.reopenable(UserDefaults.standard.string(forKey: "lastVault")) { open(url) }
        }
        .onChange(of: selection) { _, path in show(path) }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in saveDue() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in try? tabs?.saveAll() }
    }

    private func chooseFolder(create: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = create
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if create {
            do { try Vault.create(at: url) } catch { self.error = "Choose an empty folder: \(error)"; return }
        }
        open(url)
    }

    private func open(_ url: URL) {
        do {
            tree = try Vault.load(root: url); search = try SearchIndex(root: url); tags = try TagIndex(root: url); root = url; tabs = NoteTabs(root: url); error = nil
            UserDefaults.standard.set(url.path, forKey: "lastVault")
            GraphModel.shared.onOpen = { go($0, reveal: nil) }
            GraphModel.shared.root = url
            watcher = VaultWatcher(root: url) { paths in
                GraphModel.shared.reload()
                if let t = tree, let fresh = try? t.refreshed(paths: paths, root: url) { tree = fresh }
                try? search?.update(paths: paths)
                try? tags?.update(paths: paths)
                tabs?.diskChanged(paths)
            }
        } catch { self.error = "\(error)" }
    }

    private func show(_ path: String?) {
        guard let tree, let path, let node = find(path, in: tree), !node.isFolder else { return }
        do { try tabs?.open(path); error = nil } catch { self.error = "\(error)" }
    }

    private var inspector: some View {
        let text = tabs?.active.flatMap { tabs?.text($0) } ?? ""
        return List {
            Section("Backlinks") {
                ForEach(Array(backlinks.enumerated()), id: \.offset) { _, b in
                    Button(b.path) { go(b.path, reveal: b.link.range) }.buttonStyle(.plain)
                }
            }
            if let (title, rel) = relations {
                ForEach([("Calls out", rel.callsOut), ("Calls in", rel.callsIn), ("Used by", rel.usesIn)], id: \.0) { name, refs in
                    Section("\(title): \(name)") {
                        ForEach(Array(refs.enumerated()), id: \.offset) { _, r in
                            Button(r.heading.map { "\(r.path)#\($0)" } ?? r.path) { go(r.path, reveal: nil) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Section("Outline") {
                if let h = NoteParser.parse(text).headings.last(where: { $0.range.location <= cursor }) {
                    Button("Rename heading at cursor…") { renameHeading(h.title) }
                }
                ForEach(Array(NoteParser.parse(text).headings.enumerated()), id: \.offset) { _, h in
                    Button(h.title) { reveal = .init(range: h.range) }.buttonStyle(.plain).padding(.leading, CGFloat(h.level - 1) * 10)
                        .contextMenu { Button("Rename heading…") { renameHeading(h.title) } }
                }
            }
        }.inspectorColumnWidth(min: 160, ideal: 220, max: 320)
    }

    /// Inspector follows the cursor: shows relations for the Endpoint heading it sits under.
    private func refreshRelations() {
        guard let root, let active = tabs?.active, let text = tabs?.text(active),
              let h = NoteParser.parse(text).endpointHeading(at: cursor),
              let rel = try? Vault.endpointRelations(path: active, heading: h.title, in: root) else { relations = nil; return }
        relations = (h.title, rel)
    }

    private func refreshBacklinks() {
        guard let root, let active = tabs?.active else { backlinks = []; return }
        backlinks = (try? Vault.backlinks(to: active, in: root)) ?? []
    }

    private func go(_ path: String, reveal range: NSRange?) {
        do {
            try tabs?.open(path)
            reveal = range.map { .init(range: $0) }
            selection = path
        } catch { self.error = "\(error)" }
    }

    /// ⌘-click: open the target (creating it first when the Link is broken) and jump to its heading.
    private func follow(_ link: WikiLink) {
        guard let root else { return }
        do {
            let path = try Vault.createNote(forLink: link.target, in: root)
            tree = try Vault.load(root: root)
            try tabs?.open(path)
            let headings = NoteParser.parse(tabs?.text(path) ?? "").headings
            let range = link.heading.flatMap { h in headings.first { $0.title.caseInsensitiveCompare(h) == .orderedSame }?.range }
            reveal = range.map { .init(range: $0) }
        } catch { self.error = "\(error)" }
    }

    @ViewBuilder private func noteMenu(_ path: String) -> some View {
        Button("Rename…") {
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if let new = promptText("Rename Note to", initial: name) { perform("Rename Note") { try Vault.renameNote(path, to: new, in: $0) } }
        }
        Button("Move…") {
            if let dest = promptText("Move Note to folder (Vault-relative)", initial: (path as NSString).deletingLastPathComponent) {
                perform("Move Note") { try Vault.moveNote(path, toFolder: dest.trimmingCharacters(in: CharacterSet(charactersIn: "/")), in: $0) }
            }
        }
    }

    private func renameHeading(_ old: String) {
        guard let active = tabs?.active, let new = promptText("Rename heading", initial: old), new != old else { return }
        perform("Rename Heading") { try Vault.renameHeading(old, to: new, inNote: active, in: $0) }
    }

    /// Saves open Notes, asks the Vault for the edits, applies them as one undoable step and refreshes the UI.
    private func perform(_ name: String, _ make: (URL) throws -> [FileEdit]) {
        guard let root else { return }
        do {
            try tabs?.saveAll()
            let edits = try make(root)
            if !edits.isEmpty { try UndoableEdits.run(edits, root: root, undo: undoManager, name: name) { refreshAfter($0, root: root) } }
        } catch { self.error = "\(error)" }
    }

    /// Reloads tree, indexes and open tabs from disk (a moved Note's tab follows it to the new path).
    private func refreshAfter(_ edits: [FileEdit], root: URL) {
        let moved: [String: String] = Dictionary(uniqueKeysWithValues: zip(edits.filter(\.removesFile).map(\.path), edits.filter(\.createsFile).map(\.path)))
        let paths = Array(Set(edits.map(\.path)))
        tree = try? Vault.load(root: root)
        try? search?.update(paths: paths)
        try? tags?.update(paths: paths)
        GraphModel.shared.reload()
        var fresh = NoteTabs(root: root)
        for p in tabs?.paths ?? [] { try? fresh.open(moved[p] ?? p) }
        if let a = tabs?.active { try? fresh.open(moved[a] ?? a) }
        tabs = fresh
        epoch += 1
        refreshBacklinks()
    }

    private func saveDue() {
        do { try tabs?.saveDue() } catch { self.error = "Could not save: \(error)" }
    }

    private func find(_ path: String, in node: VaultNode) -> VaultNode? {
        if node.relativePath == path { return node }
        return node.children.lazy.compactMap { find(path, in: $0) }.first
    }
}

private extension VaultNode {
    var optionalChildren: [VaultNode]? { isFolder ? children : nil }
}

/// Folders / Notes / Text matches; clicking a text match opens the Note at the hit.
private struct SearchResultsView: View {
    let results: SearchIndex.Results
    let openMatch: (SearchIndex.TextMatch) -> Void
    let openNote: (String) -> Void

    var body: some View {
        List {
            if !results.folders.isEmpty {
                Section("Folders") { ForEach(results.folders, id: \.self) { Label($0, systemImage: "folder") } }
            }
            if !results.notes.isEmpty {
                Section("Notes") {
                    ForEach(results.notes, id: \.self) { p in Button(results.isArchived(p) ? "\(p)  (archived)" : p) { openNote(p) }.buttonStyle(.plain) }
                }
            }
            if !results.matches.isEmpty {
                Section("Text matches") {
                    ForEach(Array(results.matches.enumerated()), id: \.offset) { _, m in
                        Button { openMatch(m) } label: {
                            VStack(alignment: .leading) {
                                Text(highlighted(m)).lineLimit(3)
                                Text(results.isArchived(m.path) ? "\(m.path)  (archived)" : m.path).font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func highlighted(_ m: SearchIndex.TextMatch) -> AttributedString {
        var a = AttributedString(m.sentence)
        let s = m.sentence as NSString
        let lower = AttributedString(s.substring(to: m.hit.location)).characters.count
        let start = a.index(a.startIndex, offsetByCharacters: lower)
        let end = a.index(start, offsetByCharacters: AttributedString(s.substring(with: m.hit)).characters.count)
        a[start..<end].backgroundColor = .yellow.opacity(0.5)
        return a
    }
}
#endif
