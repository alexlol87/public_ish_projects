#!/usr/bin/env python3
"""Local agent memory in SQLite. Every command prints JSON; see README.md."""
import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import urllib.parse
from datetime import datetime, timedelta, timezone

DEFAULT_DB = os.path.expanduser("~/.local_memory_sqlite/memory.db")
CLI = "python3 ~/.local_memory_sqlite/mem.py"
CONTEXT_LIMIT = 40 * 1024
TOOL_CONTEXT_LIMIT = 8 * 1024  # PostToolUse context from all hooks is capped at 10 KB
SESSION_DAYS = 30  # forget which repositories a session loaded after this
SCAN_DEPTH = 2  # how deep SessionStart looks for repositories under a workspace folder
SKIP_DIRS = {"node_modules", "venv", "build", "dist", "target"}
FIELDS = "id, title, content, scope, repo, load, expires_at, created_at, updated_at"

SCHEMA = """
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    scope TEXT NOT NULL CHECK (scope IN ('global', 'repo')),
    repo TEXT,
    load TEXT NOT NULL CHECK (load IN ('always', 'on_demand')),
    expires_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK ((scope = 'global') = (repo IS NULL))
);
CREATE INDEX IF NOT EXISTS memories_repo ON memories (repo);
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5 (
    title, content, content = 'memories', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2'
);
CREATE TABLE IF NOT EXISTS session_loads (
    session_id TEXT NOT NULL,
    repo TEXT NOT NULL,
    loaded_at TEXT NOT NULL,
    PRIMARY KEY (session_id, repo)
);
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts (rowid, title, content) VALUES (new.id, new.title, new.content);
END;
CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts (memories_fts, rowid, title, content) VALUES ('delete', old.id, old.title, old.content);
END;
CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts (memories_fts, rowid, title, content) VALUES ('delete', old.id, old.title, old.content);
    INSERT INTO memories_fts (rowid, title, content) VALUES (new.id, new.title, new.content);
END;
"""


class UserError(Exception):
    pass


def now_utc():
    return datetime.now(timezone.utc)


def stamp(dt, precise=False):
    # microseconds on created/updated so "newest first" holds within one second
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ" if precise else "%Y-%m-%dT%H:%M:%SZ")


def parse_expiry(value, now):
    """'never' -> None; '30d' / '2w' / '6m' / '1y' -> relative; 'YYYY-MM-DD' -> valid through that day (UTC)."""
    if value == "never":
        return None
    m = re.fullmatch(r"([1-9]\d*)([dwmy])", value)
    if m:
        # shortcut: a month is 30 days and a year 365, fine for memory lifetimes
        days = int(m.group(1)) * {"d": 1, "w": 7, "m": 30, "y": 365}[m.group(2)]
        return stamp(now + timedelta(days=days))
    try:
        day = datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError:
        raise UserError("--expires must be never, <n>d/w/m/y or YYYY-MM-DD, got %r" % value)
    end = day + timedelta(days=1)
    if end <= now:
        raise UserError("--expires date %s is in the past" % value)
    return stamp(end)


def key_from_url(url):
    parts = [p for p in re.split(r"[/:]", re.sub(r"\.git$", "", url.strip().rstrip("/"))) if p and p != "_git"]
    return "/".join(parts[-2:]) if len(parts) >= 2 else None


def git(cwd, *args):
    try:
        p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return ""
    return p.stdout.strip() if p.returncode == 0 else ""


def repo_key(cwd):
    """landing_zone/repo_name from origin; local/<folder> without one; local/chat with no folder open."""
    if not cwd:
        return "local/chat"
    if os.path.isdir(cwd):
        key = key_from_url(git(cwd, "remote", "get-url", "origin"))
        if key:
            return key
        cwd = git(cwd, "rev-parse", "--show-toplevel") or cwd
    return "local/" + os.path.basename(os.path.normpath(cwd))


def connect():
    path = os.environ.get("LOCAL_MEMORY_DB") or DEFAULT_DB
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    con = sqlite3.connect(path, timeout=5)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    with con:
        con.executescript(SCHEMA)
        con.execute("DELETE FROM memories WHERE expires_at IS NOT NULL AND expires_at <= ?", (stamp(now_utc()),))
        con.execute("DELETE FROM session_loads WHERE loaded_at < ?", (stamp(now_utc() - timedelta(days=SESSION_DAYS)),))
    return con


def fetch(con, mid):
    row = con.execute("SELECT %s FROM memories WHERE id = ?" % FIELDS, (mid,)).fetchone()
    if row is None:
        raise UserError("no memory with id %d" % mid)
    return dict(row)


def clean_title(title):
    title = title.strip()
    if not title or "\n" in title:
        raise UserError("--title must be one non-empty line")
    return title


def clean_content(content):
    content = (sys.stdin.read() if content == "-" else content).strip()
    if not content:
        raise UserError("--content must not be empty")
    return content


def place(scope, repo):
    """The repo column for a scope: None for global, the given or current key for repo."""
    if scope == "global":
        if repo:
            raise UserError("--repo only applies to --scope repo")
        return None
    return repo or repo_key(os.getcwd())


def scope_filter(args):
    """WHERE clause for global plus one repository, or everything with --all-repos."""
    if args.all_repos:
        return "1", []
    return "(m.repo IS NULL OR m.repo = ?)", [args.repo or repo_key(os.getcwd())]


def cmd_add(con, args):
    ts = stamp(now_utc(), precise=True)
    row = (clean_title(args.title), clean_content(args.content), args.scope, place(args.scope, args.repo),
           args.load, parse_expiry(args.expires, now_utc()), ts, ts)
    with con:
        cur = con.execute("INSERT INTO memories (title, content, scope, repo, load, expires_at, created_at, updated_at)"
                          " VALUES (?, ?, ?, ?, ?, ?, ?, ?)", row)
    return {"memory": fetch(con, cur.lastrowid)}


def cmd_get(con, args):
    return {"memory": fetch(con, args.id)}


def cmd_update(con, args):
    m = fetch(con, args.id)
    changes = {}
    if args.title is not None:
        changes["title"] = clean_title(args.title)
    if args.content is not None:
        changes["content"] = clean_content(args.content)
    if args.load is not None:
        changes["load"] = args.load
    if args.expires is not None:
        changes["expires_at"] = parse_expiry(args.expires, now_utc())
    if args.scope is not None or args.repo is not None:
        changes["scope"] = args.scope or m["scope"]
        changes["repo"] = place(changes["scope"], args.repo or (m["repo"] if args.scope is None else None))
    if not changes:
        raise UserError("nothing to update: pass at least one of --title --content --scope --repo --load --expires")
    changes["updated_at"] = stamp(now_utc(), precise=True)
    with con:
        con.execute("UPDATE memories SET %s WHERE id = ?" % ", ".join(k + " = ?" for k in changes),
                    (*changes.values(), args.id))
    return {"memory": fetch(con, args.id)}


def cmd_delete(con, args):
    m = fetch(con, args.id)
    with con:
        con.execute("DELETE FROM memories WHERE id = ?", (args.id,))
    return {"memory": m}


def fts_query(text):
    """User terms -> safe FTS5 query: every word must match as a prefix, "quoted phrases" match exactly."""
    parts = []
    for phrase, word in re.findall(r'"([^"]*)"|(\S+)', text):
        tokens = re.findall(r"[^\W_]+", phrase or word)
        if phrase and tokens:
            parts.append('"%s"' % " ".join(tokens))
        else:
            parts.extend('"%s"*' % t for t in tokens)
    if not parts:
        raise UserError("search needs at least one word")
    return " ".join(parts)


def cmd_search(con, args):
    where, params = scope_filter(args)
    rows = con.execute("SELECT %s FROM memories_fts f JOIN memories m ON m.id = f.rowid"
                       " WHERE memories_fts MATCH ? AND %s ORDER BY f.rank LIMIT ?"
                       % (", ".join("m." + c.strip() for c in FIELDS.split(",")), where),
                       [fts_query(" ".join(args.terms))] + params + [args.limit]).fetchall()
    return {"memories": [dict(r) for r in rows]}


def cmd_list(con, args):
    where, params = scope_filter(args)
    for col in ("scope", "load"):
        if getattr(args, col):
            where += " AND m.%s = ?" % col
            params.append(getattr(args, col))
    rows = con.execute("SELECT %s FROM memories m WHERE %s ORDER BY m.updated_at DESC, m.id DESC" % (FIELDS, where),
                       params).fetchall()
    memories = [dict(r) for r in rows]
    if args.titles:
        for m in memories:
            del m["content"]
    return {"memories": memories}


def git_root(path):
    """The nearest folder at or above path with a .git entry, or None. No subprocess: this runs on every tool call."""
    path = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(path, ".git")):
            return path
        parent = os.path.dirname(path)
        if parent == path:
            return None
        path = parent


def find_repos(root, depth=SCAN_DEPTH):
    """Git repositories up to depth levels below root, without looking inside a repository."""
    try:
        entries = sorted(os.scandir(root), key=lambda e: e.name)
    except OSError:
        return []
    found = []
    for e in entries:
        if not e.is_dir(follow_symlinks=False) or e.name.startswith(".") or e.name in SKIP_DIRS:
            continue
        if os.path.exists(os.path.join(e.path, ".git")):
            found.append(e.path)
        elif depth > 1:
            found.extend(find_repos(e.path, depth - 1))
    return found


def render(header, rows, limit, key):
    """header, then always memories in full and on_demand titles, cut to limit bytes."""
    out, size, section = [header], len(header.encode("utf-8")), None
    for i, r in enumerate(rows):
        title = "\n## %s\n" % ("Always" if r["load"] == "always" else "On demand (titles only, fetch with get <id>)")
        entry = (title if r["load"] != section else "") + "- #%d [%s] %s%s" % (
            r["id"], r["scope"], r["title"], " (expires %s)" % r["expires_at"] if r["expires_at"] else "")
        if r["load"] == "always":
            entry += "\n" + r["content"]
        n = len(entry.encode("utf-8")) + 1
        if size + n > limit - 200:  # keep room for the footer
            out.append("\n... %d more memories not shown: run %s list --repo %s" % (len(rows) - i, CLI, key))
            break
        out.append(entry)
        size += n
        section = r["load"]
    return "\n".join(out)


def mark_loaded(con, session, key):
    """Record that this session has key's memories; False if it already had them."""
    with con:
        return con.execute("INSERT OR IGNORE INTO session_loads (session_id, repo, loaded_at) VALUES (?, ?, ?)",
                           (session, key, stamp(now_utc()))).rowcount == 1


SKILLS_LINE = "Use the alx-recall, alx-remember, alx-forget, alx-memories-list and alx-reflect skills to work with memories."
ORDER = " ORDER BY load = 'on_demand', updated_at DESC, id DESC"


def session_context(con, cwd, session):
    """One repository (or plain folder): global plus its memories. A folder holding several repositories:
    global memories plus the list of repositories; each one's memories arrive with the first tool call that touches it."""
    repos = find_repos(cwd) if cwd and os.path.isdir(cwd) and not git_root(cwd) else []
    if not repos:
        key = repo_key(cwd)
        if session:
            mark_loaded(con, session, key)
        header = ("Local memory for repository key %s (global memories apply everywhere).\n"
                  "Fetch an on_demand memory: %s get <id>. Search: %s search <terms> --repo %s.\n%s"
                  % (key, CLI, CLI, key, SKILLS_LINE))
        rows = con.execute("SELECT %s FROM memories WHERE repo IS NULL OR repo = ?%s" % (FIELDS, ORDER), (key,)).fetchall()
        return render(header, rows, CONTEXT_LIMIT, key)
    counts = dict(con.execute("SELECT repo, count(*) FROM memories WHERE repo IS NOT NULL GROUP BY repo").fetchall())
    listing = []
    for path in repos:
        key = repo_key(path)
        listing.append("- %s: key %s, %d memories" % (os.path.relpath(path, cwd), key, counts.get(key, 0)))
    header = ("Local memory: this workspace holds several repositories, so only global memories are loaded now.\n"
              "A repository's memories are added to your context the first time you read or edit a file in it. "
              "To load them earlier, for example when the user asks about a repository, run: %s list --repo <key>.\n"
              "For repository memories use the key of the repository the user means, from this list. "
              "Never use the workspace folder, and never fall back to global. "
              "For a repository not listed, pass --path <its folder> instead of --repo.\n"
              "Repositories (folder: key, memory count):\n%s\n"
              "Fetch an on_demand memory: %s get <id>. Search: %s search <terms> --repo <key>.\n%s"
              % (CLI, "\n".join(listing), CLI, CLI, SKILLS_LINE))
    rows = con.execute("SELECT %s FROM memories WHERE repo IS NULL%s" % (FIELDS, ORDER)).fetchall()
    return render(header, rows, CONTEXT_LIMIT, "<key>")


def tool_paths(value, key=""):
    """Single-line strings under keys that name a file or folder (filePath, file_path, path, dirPath, ...)."""
    if isinstance(value, dict):
        for k, v in value.items():
            yield from tool_paths(v, k)
    elif isinstance(value, list):
        for v in value:
            yield from tool_paths(v, key)
    elif (isinstance(value, str) and value.strip() and "\n" not in value
          and re.search(r"path|file|dir", key, re.I) and not re.search(r"content|text", key, re.I)):
        yield urllib.parse.unquote(value[7:]) if value.startswith("file://") else value


def tool_context(con, data, session):
    """PostToolUse: memories of each repository the tool touched that this session has not loaded yet."""
    args = data.get("tool_input", data.get("toolArgs"))
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except ValueError:
            args = None
    if not session or not args:
        return None
    cwd = data.get("cwd") or os.getcwd()
    roots = []
    for p in tool_paths(args):
        root = git_root(os.path.join(cwd, os.path.expanduser(p)))
        if root and root not in roots:
            roots.append(root)
    parts = []
    for root in roots[:5]:
        key = repo_key(root)
        if not mark_loaded(con, session, key):
            continue
        rows = con.execute("SELECT %s FROM memories WHERE repo = ?%s" % (FIELDS, ORDER), (key,)).fetchall()
        header = ("Local memory: you are now working in repository key %s (folder %s). "
                  "For its memories use --repo %s.%s" % (key, root, key, "" if rows else " It has no memories yet."))
        parts.append(render(header, rows, TOOL_CONTEXT_LIMIT // len(roots[:5]), key))
    return "\n\n".join(parts) or None


def cmd_context():
    """Hook entry point for SessionStart and PostToolUse. It must always print hook JSON, so a broken memory never
    blocks a session."""
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        data = {}
    if not isinstance(data, dict):
        data = {}
    event = data.get("hook_event_name") or data.get("hookEventName") or "SessionStart"
    session = data.get("session_id") or data.get("sessionId")
    if event.lower() == "posttooluse":
        try:
            con = connect()
            try:
                text = tool_context(con, data, session)
            finally:
                con.close()
        except Exception:  # noqa: BLE001  stay quiet: this runs on every tool call
            text = None
        return {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": text}} if text else {}
    try:
        con = connect()
        try:
            text = session_context(con, data.get("cwd"), session)
        finally:
            con.close()
    except Exception as e:  # noqa: BLE001
        text = "Local memory unavailable: %s" % e
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UserError(message)


def parser():
    p = Parser(prog="mem.py", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    def repo_opts(sp, all_repos=True):
        g = sp.add_mutually_exclusive_group()
        g.add_argument("--repo", help="repository key, default: the current folder's")
        g.add_argument("--path", help="a folder; use the key of the repository it is in")
        if all_repos:
            g.add_argument("--all-repos", action="store_true")

    a = sub.add_parser("add", help="store a memory")
    a.add_argument("--title", required=True)
    a.add_argument("--content", required=True, help="text, or - to read stdin")
    a.add_argument("--scope", required=True, choices=["global", "repo"])
    a.add_argument("--load", required=True, choices=["always", "on_demand"])
    a.add_argument("--expires", required=True, help="never, 30d, 2w, 6m, 1y or YYYY-MM-DD")
    repo_opts(a, all_repos=False)

    for name in ("get", "delete"):
        sub.add_parser(name).add_argument("id", type=int)

    u = sub.add_parser("update", help="change the given fields of a memory")
    u.add_argument("id", type=int)
    u.add_argument("--title")
    u.add_argument("--content", help="text, or - to read stdin")
    u.add_argument("--scope", choices=["global", "repo"])
    u.add_argument("--load", choices=["always", "on_demand"])
    u.add_argument("--expires")
    repo_opts(u, all_repos=False)

    s = sub.add_parser("search", help="memories containing every term, best match first")
    s.add_argument("terms", nargs="+")
    s.add_argument("--limit", type=int, default=20)
    repo_opts(s)

    ls = sub.add_parser("list", help="memories, newest first")
    ls.add_argument("--scope", choices=["global", "repo"])
    ls.add_argument("--load", choices=["always", "on_demand"])
    ls.add_argument("--titles", action="store_true", help="leave out the content")
    repo_opts(ls)

    sub.add_parser("context", help="SessionStart hook: reads hook JSON on stdin, prints hook JSON")
    return p


def main(argv=None):
    try:
        args = parser().parse_args(argv)
        if getattr(args, "path", None):
            if not os.path.isdir(args.path):
                raise UserError("--path %r is not a folder" % args.path)
            args.repo = repo_key(os.path.abspath(args.path))
        if args.cmd == "context":
            result = cmd_context()
        else:
            con = connect()
            try:
                result = globals()["cmd_" + args.cmd](con, args)
            finally:
                con.close()
    except UserError as e:
        print(json.dumps({"error": str(e)}))
        return 1
    except sqlite3.Error as e:
        print(json.dumps({"error": "database: %s" % e}))
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
