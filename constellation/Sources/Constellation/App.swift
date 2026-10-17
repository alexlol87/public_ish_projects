#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

struct ConstellationApp: App {
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup { RootView().tint(Color(hex: settings.palette.accent)).onAppear { AppSettings.shared.applyAppearance() } }
            .commands { CommandGroup(after: .sidebar) { OpenGraphButton() } }
        Window("Graph", id: "graph") { GraphView().tint(Color(hex: settings.palette.accent)) }
        Settings { SettingsView() }
    }
}

/// Raised instead of saving or applying edits while a Note's "changed on disk" choice is still open.
private struct ConflictPending: Error, CustomStringConvertible {
    var description: String { "A Note changed on disk: choose Reload from disk or Keep mine first." }
}

struct OpenGraphButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Graph") { openWindow(id: "graph") }.keyboardShortcut("g", modifiers: .command) }
}

struct RootView: View {
    @State private var index: VaultIndex?
    @State private var tree: VaultNode?
    @State private var generation = 0  // bumped whenever the index changes, so views that read it redraw
    @State private var selection: String?
    @State private var tabs: NoteTabs?
    @State private var error: String?
    @State private var watcher: VaultWatcher?
    @State private var reveal: EditorView.Reveal?
    @State private var backlinks: [Backlink] = []
    @State private var query = ""
    @State private var cursor = 0
    @State private var relations: (title: String, rel: EndpointRelations)?
    @State private var sidebarTab = SidebarTab.files
    @State private var tagFilter: String?
    @ObservedObject private var settings = AppSettings.shared
    @State private var repos: [String: Staleness] = [:]
    @Environment(\.undoManager) private var undoManager
    private var root: URL? { index?.root }

    var body: some View {
        NavigationSplitView {
            if let tree {
                sidebar(tree)
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
                    if let index {
                        EditorView(initialText: tabs.text(active) ?? "", index: index, notePath: active, reveal: reveal, onRevealed: { reveal = nil },
                                   onCursor: { cursor = $0; refreshRelations() },
                                   onChange: { self.tabs?.edit(active, text: $0) }, onFollow: { follow($0) },
                                   onTag: { tagFilter = $0.lowercased(); sidebarTab = .tags })
                            .id("\(active)#\(tabs.revision(active))#\(settings.theme.rawValue)")
                    }
                }
            } else {
                Text("Select a Note").foregroundStyle(.secondary)
            }
        }
        .inspector(isPresented: .constant(tabs?.active != nil)) { inspector }
        .onChange(of: tabs?.active) { _, _ in GraphModel.shared.currentNote = tabs?.active; refreshBacklinks(); cursor = 0; refreshRelations() }
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

    /// Files / Tags tabs of the sidebar: search box and results, or the Vault tree.
    @ViewBuilder private func sidebar(_ tree: VaultNode) -> some View {
        Picker("", selection: $sidebarTab) { ForEach(SidebarTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 8)
        if sidebarTab == .tags, let index {
            TagsView(index: index, generation: generation, selected: $tagFilter, rename: { old in
                if let new = promptText("Rename tag #\(old) to", initial: old) {
                    perform("Rename Tag") { try Vault.renameTag(old, to: new.trimmingCharacters(in: CharacterSet(charactersIn: "#")), in: $0) }
                }
            }) { hit in go(hit.path, reveal: NSRange(location: hit.offset, length: 0)) }
        } else {
            TextField("Search", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 8)
            if !query.isEmpty, let index {
                SearchResultsView(results: index.search(query)) { match in
                    go(match.path, reveal: NSRange(location: match.offset, length: match.hit.length))
                } openNote: { path in go(path, reveal: nil) }
            } else {
                fileTree(tree)
            }
        }
    }

    private func fileTree(_ tree: VaultNode) -> some View {
        List(tree.children, children: \.optionalChildren, selection: $selection) { node in
            let stale = repos[node.relativePath]?.isStale(threshold: settings.thresholdDays) == true
            HStack {
                Label(node.name, systemImage: node.isFolder ? "folder" : "doc.text")
                if let status = repos[node.relativePath] {
                    Text(status.label).font(.caption2).foregroundStyle(stale ? Color(hex: settings.palette.stale) : Color.secondary)
                }
            }
            .contextMenu {
                if !node.isFolder { noteMenu(node.relativePath) }
                if node.isFolder && AgentFiles.isRepoFolder(node.relativePath) {
                    Button("Copy ingest prompt") { copy(AgentFiles.ingestPrompt(repo: node.name)) }
                    Button("Copy refresh prompt") { copy(AgentFiles.refreshPrompt(repo: node.name)) }
                }
            }
            .foregroundStyle(stale ? Color(hex: settings.palette.stale) : Color.primary)
        }
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
            let opened = try VaultIndex(root: url)
            index = opened; tabs = NoteTabs(root: url); error = nil
            UserDefaults.standard.set(url.path, forKey: "lastVault")
            GraphModel.shared.onOpen = { go($0, reveal: nil) }
            GraphModel.shared.index = opened
            indexChanged()
            watcher = VaultWatcher(root: url) { paths in
                try? opened.ingest(paths: paths)
                indexChanged()
                tabs?.diskChanged(paths)
            }
        } catch { self.error = "\(error)" }
    }

    /// After the index changed (open, external edit, rename): redraw what reads it and refresh everything derived from it.
    private func indexChanged() {
        guard let index else { return }
        tree = index.tree
        generation += 1
        repos = index.repoStaleness()
        GraphModel.shared.repos = repos
        GraphModel.shared.reload()
        refreshBacklinks()
    }

    private func show(_ path: String?) {
        guard let tree, let path, let node = find(path, in: tree), !node.isFolder else { return }
        do { try tabs?.open(path); error = nil } catch { self.error = "\(error)" }
    }

    private var inspector: some View {
        let active = tabs?.active
        let headings = Vault.parse(active.flatMap { tabs?.text($0) } ?? "").headings
        return List {
            Section("Backlinks") {
                ForEach(Array(backlinks.enumerated()), id: \.offset) { _, b in
                    Button(b.path) { go(b.path, reveal: b.link.range) }.buttonStyle(.plain)
                }
            }
            if let r = relations {
                ForEach([("Calls out", r.rel.callsOut), ("Calls in", r.rel.callsIn), ("Used by", r.rel.usesIn)], id: \.0) { name, refs in
                    Section("\(r.title): \(name)") {
                        ForEach(Array(refs.enumerated()), id: \.offset) { _, r in
                            Button(r.heading.map { "\(r.path)#\($0)" } ?? r.path) { go(r.path, reveal: nil) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Section("Outline") {
                if let current = headings.last(where: { $0.range.location <= cursor }) {
                    Button("Rename heading at cursor…") { renameHeading(current.title) }
                }
                ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                    Button(heading.title) { if let active { reveal = .init(path: active, range: heading.range) } }
                        .buttonStyle(.plain).padding(.leading, CGFloat(heading.level - 1) * 10)
                        .contextMenu { Button("Rename heading…") { renameHeading(heading.title) } }
                }
            }
        }.inspectorColumnWidth(min: 160, ideal: 220, max: 320)
    }

    /// Inspector follows the cursor: shows relations for the Endpoint heading it sits under.
    private func refreshRelations() {
        guard let root, let active = tabs?.active, let text = tabs?.text(active),
              let endpoint = Vault.parse(text).endpointHeading(at: cursor),
              let rel = try? Vault.endpointRelations(path: active, heading: endpoint.title, in: root) else { relations = nil; return }
        relations = (endpoint.title, rel)
    }

    private func refreshBacklinks() {
        guard let index, let active = tabs?.active else { backlinks = []; return }
        backlinks = index.backlinks(to: active)
    }

    private func go(_ path: String, reveal range: NSRange?) {
        do {
            try tabs?.open(path)
            reveal = range.map { .init(path: path, range: $0) }
            selection = path
        } catch { self.error = "\(error)" }
    }

    /// Click on a Link: open the target (creating it first when the Link is broken) and jump to its heading.
    private func follow(_ link: WikiLink) {
        guard let index else { return }
        do {
            let edits = try Vault.createNote(forLink: link.target, in: index.root)
            if !edits.isEmpty {
                try FileEdit.apply(edits, root: index.root)
                try index.ingest(paths: edits.map(\.path))
                indexChanged()
            }
            guard case .note(let path) = try Vault.resolve(link.target, in: index.root) else { return }
            try tabs?.open(path)
            let headings = Vault.parse(tabs?.text(path) ?? "").headings
            let range = link.heading.flatMap { wanted in headings.first { $0.title.caseInsensitiveCompare(wanted) == .orderedSame }?.range }
            go(path, reveal: range)
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
            try flush()
            let edits = try make(root)
            if !edits.isEmpty {
                try UndoableEdits.run(edits, root: root, undo: undoManager, name: name, before: flush, after: refreshAfter)
            }
        } catch { self.error = "\(error)" }
    }

    /// Writes unsaved editor text before files are rewritten (also before every undo and redo of a rewrite).
    private func flush() throws {
        guard tabs?.hasConflicts != true else { throw ConflictPending() }
        try tabs?.saveAll()
    }

    /// Re-reads what the edits touched; open tabs are rebuilt from disk (a moved Note's tab follows it).
    private func refreshAfter(_ edits: [FileEdit]) {
        try? index?.ingest(paths: Array(Set(edits.map(\.path))))
        tabs?.reloadAfter(edits)
        indexChanged()
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

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
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
