#if canImport(AppKit)
import CoreServices
import Foundation

/// FSEvents watcher: reports Vault-relative paths that changed (any kind of change; Core re-reads from disk).
final class VaultWatcher {
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init(root: URL, handler: @escaping ([String]) -> Void) {
        self.handler = handler
        // FSEvents reports resolved real paths (/private/var...), so compare against the resolved root.
        let base = root.resolvingSymlinksInPath().path
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            let me = Unmanaged<VaultWatcher>.fromOpaque(info!).takeUnretainedValue()
            let all = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            me.handler(all.prefix(count).compactMap { p in
                p.hasPrefix(base + "/") ? String(p.dropFirst(base.count + 1)) : nil
            })
        }
        stream = FSEventStreamCreate(nil, callback, &ctx, [base] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
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
