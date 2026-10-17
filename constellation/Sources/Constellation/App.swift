#if canImport(AppKit)
import AppKit
import ConstellationCore
import SwiftUI

struct ConstellationApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @State private var root: URL?
    @State private var tree: VaultNode?
    @State private var selection: String?
    @State private var tabs: NoteTabs?
    @State private var error: String?
    @State private var watcher: VaultWatcher?

    var body: some View {
        NavigationSplitView {
            if let tree {
                List(tree.children, children: \.optionalChildren, selection: $selection) { node in
                    Label(node.name, systemImage: node.isFolder ? "folder" : "doc.text")
                }
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
                    EditorView(initialText: tabs.text(active) ?? "") { self.tabs?.edit(active, text: $0) }
                        .id("\(active)#\(tabs.revision(active))")
                }
            } else {
                Text("Select a Note").foregroundStyle(.secondary)
            }
        }
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
            tree = try Vault.load(root: url); root = url; tabs = NoteTabs(root: url); error = nil
            UserDefaults.standard.set(url.path, forKey: "lastVault")
            watcher = VaultWatcher(root: url) { paths in
                if let t = tree, let fresh = try? t.refreshed(paths: paths, root: url) { tree = fresh }
                tabs?.diskChanged(paths)
            }
        } catch { self.error = "\(error)" }
    }

    private func show(_ path: String?) {
        guard let tree, let path, let node = find(path, in: tree), !node.isFolder else { return }
        do { try tabs?.open(path); error = nil } catch { self.error = "\(error)" }
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
#endif
