#if canImport(AppKit)
import CoreServices
import Foundation

/// FSEvents watcher: reports Vault-relative paths that changed (any kind of change; Core re-reads from disk).
final class VaultWatcher {
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void
    /// FSEvents reports resolved real paths (/private/var...), so compare against the resolved root.
    private let base: String

    init(root: URL, handler: @escaping ([String]) -> Void) {
        self.handler = handler
        base = root.resolvingSymlinksInPath().path
        // The C callback cannot capture anything, so it finds this watcher again through `info`.
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info!).takeUnretainedValue()
            let all = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handler(all.prefix(count).compactMap { path in
                path.hasPrefix(watcher.base + "/") ? String(path.dropFirst(watcher.base.count + 1)) : nil
            })
        }
        stream = FSEventStreamCreate(nil, callback, &context, [base] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     0.3, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)  // handler runs on main
            FSEventStreamStart(stream)
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
    }
}
#endif
