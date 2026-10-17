import Foundation

extension Vault {
    /// Archive Notes live in `<project>/archive/` (ADR 0002); hidden in the graph by default, marked in search.
    public static func isArchive(_ relativePath: String) -> Bool {
        let c = relativePath.split(separator: "/")
        return c.count >= 2 && c[1] == "archive"
    }

    /// A click on a task checkbox. `offset` is any UTF-16 offset on the task's line in `text` (the open buffer of `path`).
    /// Unticked item in a Repo's bugs.md / todo.md (`project/repo/bugs.md`): moves it to the Project's archive Note.
    /// Any other task: toggles the box. Not a task line: no edits.
    public static func tick(taskAt offset: Int, in text: String, path: String, root: URL, on date: Date = Date()) throws -> [FileEdit] {
        let ns = text as NSString
        guard offset >= 0, offset <= ns.length else { return [] }
        let first = ns.lineRange(for: NSRange(location: offset, length: 0))
        let line = ns.substring(with: first)
        guard let m = taskLine.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return [] }
        let box = NSRange(location: first.location + m.range(at: 2).location, length: 1)
        let checked = ns.substring(with: box) != " "
        let parts = path.split(separator: "/").map(String.init)
        let file = parts.last ?? ""
        guard !checked, parts.count >= 3, file == "bugs.md" || file == "todo.md" else {
            return [FileEdit(path: path, range: box, text: checked ? " " : "x")]
        }

        // The item: its line plus the more-indented lines after it.
        let indent = (line as NSString).substring(with: m.range(at: 1)).count
        var item = first
        while NSMaxRange(item) < ns.length {
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(item), length: 0))
            let s = ns.substring(with: next)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.prefix(while: { $0 == " " || $0 == "\t" }).count > indent else { break }
            item = NSUnionRange(item, next)
        }
        let body = (line as NSString).substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
        let title = body.components(separatedBy: " → ")[0].trimmingCharacters(in: .whitespaces)
        let rest = ns.substring(with: NSRange(location: NSMaxRange(first), length: NSMaxRange(item) - NSMaxRange(first)))
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")

        let repo = parts.dropLast().joined(separator: "/")
        let paths = try notePaths(in: root)
        var source = "[[\(repo)/README]]"
        if let l = NoteParser.parse(ns.substring(with: item)).links.first {
            // Resolve inside the Repo first: "endpoints" means this Repo's endpoints Note, not another Repo's.
            let local = repo + "/" + l.target + ".md"
            var target = l.target
            if paths.contains(local) { target = String(local.dropLast(3)) }
            else if case .note(let p) = resolve(l.target, among: paths) { target = String(p.dropLast(3)) }
            source = "[[" + target + (l.heading.map { "#" + $0 } ?? "") + "]]"
        }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let entry = "### \(title)\n- closed: \(f.string(from: date))\n- source: \(source)\n- what: \(rest.isEmpty ? title : rest)\n- fix: unknown\n"

        let bug = file == "bugs.md"
        let archive = "\(parts[0])/archive/" + (bug ? "fixed-bugs.md" : "done-todos.md")
        var edits = [FileEdit(path: path, range: item, text: "")]
        if let old = try? String(contentsOf: root.appendingPathComponent(archive), encoding: .utf8) {
            let sep = old.isEmpty ? "" : old.hasSuffix("\n") ? "\n" : "\n\n"
            edits.append(FileEdit(path: archive, range: NSRange(location: (old as NSString).length, length: 0), text: sep + entry))
        } else {
            let head = "---\ntype: archive\n---\n# \(bug ? "Fixed bugs" : "Done todos")\n\n"
            edits.append(FileEdit(path: archive, range: NSRange(location: 0, length: 0), text: head + entry, createsFile: true))
        }
        return edits
    }

    // groups: 1 indent, 2 box char, 3 rest of the line
    private static let taskLine = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+] \[([ xX])\] ?(.*?)\n?$"#)
}
