#!/usr/bin/env python3
"""Local memory and instincts for GitHub Copilot (VS Code Copilot sessions and Copilot CLI).

A stand-in for Copilot Memory and VS Code's memory tool when they are turned off. Everything stays in plain files on
this machine; only Python's standard library is used.

    mem.py remember [--repo|--user] [--stdin] TEXT   save a fact or preference (--stdin: read TEXT from stdin)
    mem.py forget [--repo|--user] [--all] [--dry-run] TEXT   remove the lines that contain TEXT (at least 4 characters)
    mem.py recall                            print this repository's memory, instincts and your memory
    mem.py instinct ID --trigger T --action A [--repo|--user] [--evidence E]   create or reinforce an instinct
    mem.py instinct ID --stdin [--repo|--user] [--evidence E]   same; stdin's first line is the trigger, the rest the action
    mem.py weaken ID [--repo|--user] [--evidence E]   lower an instinct's confidence (deleted below 0.2)
    mem.py forget-instinct ID [--repo|--user]  delete an instinct outright
    mem.py instincts                         list every instinct for this repository and the global ones
    mem.py promote ID                        move a repository instinct to the global ones
    mem.py observations                      print what the hooks logged since the last reflection
    mem.py mark-reflected                    mark those observations as reviewed
    mem.py sync                              rewrite the personal instructions file from user memory
    mem.py disable                           pause: move the hooks and instructions file aside, skills user-only
    mem.py enable                            resume: put them back, skills usable by the agent again
    mem.py where                             print the paths in use
    mem.py status                            counts, log sizes, estimated tokens and recent hook errors
    mem.py clear --obs|--instincts|--repo|--all --yes   delete logs, instincts, this repository or everything
    mem.py export FILE                       write user memory, instincts and repositories to one JSON file
    mem.py import FILE                       merge a file written by export (existing duplicates are skipped)
    mem.py hook EVENT                        called by the Copilot hooks (session-start, user-prompt, tool-failure,
                                             agent-stop); reads the hook's JSON on stdin and never fails the session
"""
from __future__ import annotations

import argparse
import datetime as dt
import functools
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

MIN_CONFIDENCE = 0.2  # below this an instinct is deleted
MAX_HOOK_LOG_BYTES = 100_000  # hook-errors.log is rotated to hook-errors.1.log past this size
EXPORT_VERSION = 1
START_CONFIDENCE = 0.5
STEP_UP = 0.1
STEP_DOWN = 0.2
MAX_CONFIDENCE = 0.9
DECAY_PER_30_DAYS = 0.1  # unused instincts fade, like ECC's "not observed for extended periods"
MAX_INSTINCTS_PER_SCOPE = 100  # the lowest-confidence instinct is dropped to make room
MAX_MEMORY_LINES = 200  # same budget VS Code's memory tool loads from user memory
MAX_MEMORY_CHARS = 4000  # cap on the facts loaded into a session; keeps the token cost bounded
MAX_FACT_CHARS = 300  # remember rejects longer facts; loaded instinct lines are clipped to this too
MAX_EVIDENCE = 5
MAX_OBSERVATION_BYTES = 1_000_000
KEEP_ROTATED = 3  # observations.1.jsonl .. observations.3.jsonl
MAX_PROMPT_CHARS = 1000
MIN_FORGET_CHARS = 4
ACTIVE_MIN_CONFIDENCE = 0.7  # instincts below this are not loaded into a session
ACTIVE_MAX_INSTINCTS = 10  # per scope: how many are loaded
GIT_TIMEOUT_SECONDS = 2  # the hooks give up after 5 s, and up to two git calls run per hook
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
# Tools whose toolArgs are a shell command; only the first word of the command is logged.
TERMINAL_TOOLS = {"run_in_terminal", "bash", "powershell", "shell", "terminal"}

# Prompts that look like the user correcting the agent; flagged so /alx-reflect looks at them first.
CORRECTION_RE = re.compile(
    r"^\s*(no\b|nope\b|wrong\b|stop\b|don'?t\b|do not\b|never\b|always\b|actually\b|instead\b|i said\b|i told you\b"
    r"|that'?s not\b|not like that\b|please don'?t\b|why did you\b)"
    r"|\b(instead of|from now on|next time|you should have|you forgot)\b",
    re.IGNORECASE,
)

SECRET_PATTERNS = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.DOTALL),
    re.compile(r"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"),
    re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{16,}"),
    re.compile(r"\b(?:npm_[A-Za-z0-9]{36}|glpat-[A-Za-z0-9_-]{20,}|(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"
               r"|AIza[0-9A-Za-z_-]{35}|ya29\.[A-Za-z0-9_-]{20,})\b"),
    re.compile(r"(?i)\bauthorization\s*:\s*basic\s+\S+"),
    re.compile(r"(?i)(?<=://)[^\s:/@]+:[^\s@/]+(?=@)"),  # scheme://user:pass@host
    re.compile(r"(?i)--(?:password|passwd|token|secret|api[_-]?key)\s+\S+"),
    # ponytail: high-entropy fallback; ceiling is 32+ char mixed-case+digit runs only (misses hex/base64-free secrets)
    re.compile(r"\b(?=[A-Za-z0-9_-]*[a-z])(?=[A-Za-z0-9_-]*[A-Z])(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{32,}\b"),
]
SECRET_KEYWORD = r"(?:password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)"
# ponytail: "key: rest of line" redacts the whole rest of the line (catches "password: my secret pass");
# over-redacts prose after the colon. "key=value" stays one token so "password = hunter2 ok" keeps "ok".
SECRET_PHRASE = re.compile(rf"(?i)(\b[\w-]{{0,40}}{SECRET_KEYWORD}[\w-]{{0,40}}\s*:\s*)[^\n]+")
SECRET_ASSIGNMENT = re.compile(
    rf"(?i)(\b[\w-]{{0,40}}{SECRET_KEYWORD}[\w-]{{0,40}})(\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|\S+)"
)


class MemError(Exception):
    pass


# ---------- paths ----------


def copilot_home() -> Path:
    return Path(os.environ.get("COPILOT_HOME") or Path.home() / ".copilot")


def memory_root() -> Path:
    return Path(os.environ.get("LOCAL_MEMORY_HOME") or copilot_home() / "local-memory")


def instructions_file() -> Path:
    return copilot_home() / "instructions" / "local-memory.instructions.md"


# ---------- configuration ----------

# Every limit above that config.json may override, by its lower-case name ("max_memory_lines": 300).
CONFIG_KEYS = (
    "MIN_CONFIDENCE", "START_CONFIDENCE", "STEP_UP", "STEP_DOWN", "MAX_CONFIDENCE", "DECAY_PER_30_DAYS",
    "ACTIVE_MIN_CONFIDENCE", "ACTIVE_MAX_INSTINCTS", "MAX_INSTINCTS_PER_SCOPE", "MAX_EVIDENCE",
    "MAX_MEMORY_LINES", "MAX_MEMORY_CHARS", "MAX_FACT_CHARS", "MIN_FORGET_CHARS", "MAX_PROMPT_CHARS",
    "MAX_OBSERVATION_BYTES", "KEEP_ROTATED", "MAX_HOOK_LOG_BYTES", "GIT_TIMEOUT_SECONDS",
)
_DEFAULTS = {k: globals()[k] for k in CONFIG_KEYS}
CONFIG_PROBLEMS: list[str] = []  # what load_config ignored, shown by `status`


def config_path() -> Path:
    return memory_root() / "config.json"


def load_config() -> None:
    """Applies config.json over the defaults (once per process). Never raises: a missing file, bad JSON or a bad
    value leaves the default in place (a hook must not fail a session) and is listed in CONFIG_PROBLEMS."""
    problems: list[str] = []
    try:
        data = json.loads(config_path().read_text(encoding="utf-8"))
    except FileNotFoundError:
        data = {}
    except (OSError, ValueError) as exc:
        data = {}
        problems.append(f"cannot read {config_path()}: {exc}")
    if not isinstance(data, dict):
        data = {}
        problems.append(f"{config_path()} must hold a JSON object")
    values: dict = {}
    for key, value in data.items():
        name = str(key).upper()
        default = _DEFAULTS.get(name)
        number = isinstance(value, (int, float)) and not isinstance(value, bool)
        if default is None:
            problems.append(f"unknown setting {key!r}")
        elif not number or (isinstance(default, int) and not isinstance(value, int)):
            problems.append(f"{key}: expected a {'whole ' if isinstance(default, int) else ''}number, got {value!r}")
        elif not (0 <= value <= (1 if isinstance(default, float) else 10**12)) or (
                isinstance(default, int) and value < (name != "ACTIVE_MAX_INSTINCTS")):
            problems.append(f"{key}: {value!r} is out of range")
        else:
            values[name] = value
    globals().update(values)
    CONFIG_PROBLEMS[:] = problems


def today() -> str:
    return dt.date.today().isoformat()


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def private_mkdir(d: Path) -> None:
    # Path.mkdir(mode=...) only applies the mode to the leaf, so every missing ancestor is created 0700 here too.
    for p in reversed([d, *d.parents]):
        if not p.is_dir():
            p.mkdir(mode=0o700, exist_ok=True)


def write_atomic(path: Path, text: str) -> None:
    private_mkdir(path.parent)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


@contextmanager
def file_lock():
    """Exclusive lock on <memory root>/.lock. Hooks and commands run as separate processes, so this is what keeps
    their read-modify-write cycles from losing each other's changes. Not reentrant: never nest it."""
    root = memory_root()
    private_mkdir(root)
    with (root / ".lock").open("a+b") as f:
        if os.name == "nt":
            import msvcrt
            while True:  # ponytail: LK_LOCK only retries for about 10 s, so loop until it gets the lock
                f.seek(0)
                try:
                    msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1)
                    break
                except OSError:
                    time.sleep(0.05)
            try:
                yield
            finally:
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)


# ---------- repository identity ----------


@functools.lru_cache(maxsize=None)  # one process is one hook call or one command: the answer cannot change under it
def _git(cwd: Path, *args: str) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(cwd), *args], capture_output=True, text=True, timeout=GIT_TIMEOUT_SECONDS, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def normalize_remote(url: str) -> str:
    """git@github.com:me/x.git, https://user:tok@github.com/me/x, ssh://git@github.com:22/me/x and
    git+ssh://git@github.com/me/x all become github.com/me/x, so the same repository gets the same memory in every
    clone. Paths are lower-cased (GitHub paths are case-insensitive), and Windows paths become c:/users/me/x."""
    url = url.strip()
    m = re.match(r"^(?:file://)?/?([A-Za-z]:[\\/].*)$", url)  # local path, e.g. C:\Repos\x.git or file:///C:/Repos/x
    if m:
        return m.group(1).replace("\\", "/").rstrip("/").removesuffix(".git").lower()
    m = re.match(r"^[\w.-]+@([^:/]+):(.+)$", url)  # scp-like ssh
    if m:
        host, path = m.group(1), m.group(2)
    else:
        m = re.match(r"^[a-z][a-z0-9+.-]*://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+)$", url, re.IGNORECASE)
        if not m:
            return url.rstrip("/").removesuffix(".git").lower()
        host, path = m.group(1), m.group(2)
    return f"{host.lower()}/{path.strip('/').removesuffix('.git')}".lower()


def _identity(key: str) -> tuple[str, str]:
    name = key.rstrip("/").split("/")[-1] or "repo"
    slug = re.sub(r"[^a-z0-9-]+", "-", name.lower()).strip("-")[:40] or "repo"
    return f"{slug}-{hashlib.sha256(key.encode()).hexdigest()[:8]}", key


def _holds_repos(cwd: Path) -> bool:
    try:
        return any((d / ".git").exists() for d in cwd.iterdir() if d.is_dir())
    except OSError:
        return False


def repo_identity(cwd: Path) -> tuple[str, str] | None:
    """(id, display name) of the git repository containing cwd, or None outside a repository. A folder that is not
    in a repository but directly holds some (a multi-repository workspace) is identified by its path.
    LOCAL_MEMORY_REPO (a remote URL or any name) overrides the detection, e.g. for a moved folder or no origin."""
    override = os.environ.get("LOCAL_MEMORY_REPO", "").strip()
    if override:
        return _identity(normalize_remote(override))
    top = _git(cwd, "rev-parse", "--show-toplevel")
    if not top:
        return _identity(str(cwd.resolve())) if _holds_repos(cwd) else None
    remote =_git(cwd, "config", "--get", "remote.origin.url")
    return _identity(normalize_remote(remote) if remote else str(Path(top).resolve()))


def repo_dir(cwd: Path, required: bool = True, create: bool = False) -> Path | None:
    """The repository's memory directory. Only created when create is True (writes), so read commands leave no
    empty directories behind."""
    ident = repo_identity(cwd)
    if ident is None:
        if required:
            raise MemError(f"{cwd} is not inside a git repository; use --user for memory that applies everywhere")
        return None
    d = memory_root() / "repos" / ident[0]
    if create:
        private_mkdir(d)
        meta = d / "repo.json"
        if not meta.exists():
            write_atomic(meta, json.dumps({"id": ident[0], "source": ident[1]}, indent=2) + "\n")
    return d


def scope_dir(scope: str, cwd: Path) -> Path:
    if scope == "user":
        d = memory_root()
        private_mkdir(d)
        return d
    return repo_dir(cwd, create=True)  # type: ignore[return-value]


# ---------- redaction ----------


def redact(text: str) -> str:
    for pattern in SECRET_PATTERNS:
        text = pattern.sub("[REDACTED]", text)
    text = SECRET_PHRASE.sub(lambda m: f"{m.group(1)}[REDACTED]", text)
    return SECRET_ASSIGNMENT.sub(lambda m: f"{m.group(1)}{m.group(2)}[REDACTED]", text)


# ---------- memory (one fact per line) ----------


def memory_path(d: Path) -> Path:
    return d / ("user.md" if d == memory_root() else "memory.md")


def read_facts(d: Path) -> list[str]:
    p = memory_path(d)
    if not p.exists():
        return []
    return [line.rstrip("\n") for line in p.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]


def write_facts(d: Path, facts: list[str]) -> None:
    write_atomic(memory_path(d), "\n".join(facts) + ("\n" if facts else ""))


def _norm(text: str) -> str:
    text = re.sub(r"\s*\(\d{4}-\d{2}-\d{2}\)\s*$", "", text.strip().lstrip("-* ").strip())
    return re.sub(r"\s+", " ", text).lower().rstrip(".")


def _one_line(text: str) -> str:
    return " ".join(text.split())


def _safe_line(line: str) -> str:
    """Escape a leading # or --- so a saved fact renders as text, not as a heading or front matter, in the instructions file."""
    return re.sub(r"^(\s*(?:[-*+]\s+)?)(#|---)", r"\1\\\2", line)


def remember(scope: str, text: str, cwd: Path) -> str:
    text = redact(_one_line(text))
    if not text:
        raise MemError("nothing to remember")
    if len(text) > MAX_FACT_CHARS:
        raise MemError(f"that is {len(text)} characters; keep one fact under {MAX_FACT_CHARS} "
                       "(save it as several shorter facts)")
    d = scope_dir(scope, cwd)
    with file_lock():
        facts = read_facts(d)
        if any(_norm(f) == _norm(text) for f in facts):
            return f"already in {scope} memory: {text}"
        facts.append(f"- {text} ({today()})")
        write_facts(d, facts)
    if scope == "user":
        sync()
    return f"saved to {scope} memory: {text}"


def forget(scope: str, text: str, cwd: Path, all_matches: bool, dry_run: bool = False) -> str:
    needle = text.lower().strip()
    if len(needle) < MIN_FORGET_CHARS:  # a short needle matches almost every line
        raise MemError(f"forget needs at least {MIN_FORGET_CHARS} characters of {text!r} to match")
    d = scope_dir(scope, cwd)
    with file_lock():
        facts = read_facts(d)
        hits = [f for f in facts if needle in f.lower()]
        if not hits:
            raise MemError(f"no line in {scope} memory contains {text!r}")
        if dry_run:
            return "would remove:\n" + "\n".join(hits)
        if len(hits) > 1 and not all_matches:
            raise MemError("several lines match; be more specific or pass --all:\n" + "\n".join(hits))
        write_facts(d, [f for f in facts if f not in hits])
    if scope == "user":
        sync()
    return "removed:\n" + "\n".join(hits)


# ---------- instincts ----------


def instincts_dir(d: Path) -> Path:
    return d / "instincts"


def parse_instinct(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.DOTALL)
    if not m:
        raise MemError(f"{path} has no front matter")
    meta: dict = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        value = value.strip()
        if value.startswith('"'):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                value = value.strip('"')
        meta[key.strip()] = value
    body = m.group(2)
    # format_instinct always writes its Evidence heading last, and evidence is one line, so the last heading is the real one
    # even when the action itself contains "## Evidence".
    heads = list(re.finditer(r"^## Evidence[ \t]*$", body, re.MULTILINE))
    action, evidence = (body[: heads[-1].start()], body[heads[-1].end():]) if heads else (body, "")
    meta["action"] = action.strip()
    meta["evidence"] = [e[2:].strip() for e in evidence.strip().splitlines() if e.startswith("- ")]
    try:
        meta["confidence"] = float(meta.get("confidence", START_CONFIDENCE))
    except ValueError:
        meta["confidence"] = START_CONFIDENCE
    meta["seen"] = int(meta.get("seen", 1)) if str(meta.get("seen", "1")).isdigit() else 1
    meta.setdefault("id", path.stem)
    meta.setdefault("trigger", "")
    meta.setdefault("created", today())
    meta.setdefault("last_seen", meta["created"])
    meta["path"] = path
    return meta


def format_instinct(i: dict) -> str:
    lines = [
        "---",
        f"id: {i['id']}",
        f"trigger: {json.dumps(i['trigger'], ensure_ascii=False)}",
        f"confidence: {i['confidence']:.2f}",
        f"seen: {i['seen']}",
        f"created: {i['created']}",
        f"last_seen: {i['last_seen']}",
        "---",
        "",
        i["action"],
        "",
    ]
    lines += ["## Evidence", *[f"- {_one_line(e)}" for e in i["evidence"][-MAX_EVIDENCE:]], ""]
    return "\n".join(lines)


def load_instincts(d: Path | None) -> list[dict]:
    if d is None or not instincts_dir(d).is_dir():
        return []
    out = []
    for p in sorted(instincts_dir(d).glob("*.md")):
        try:
            out.append(parse_instinct(p))
        except (MemError, OSError):
            continue
    return out


def effective_confidence(i: dict, on: dt.date | None = None) -> float:
    on = on or dt.date.today()
    try:
        last = dt.date.fromisoformat(str(i.get("last_seen")))
    except ValueError:
        return i["confidence"]
    days = max(0, (on - last).days)
    return round(max(0.0, i["confidence"] - DECAY_PER_30_DAYS * days / 30), 2)


def check_id(instinct_id: str) -> str:
    if not ID_RE.match(instinct_id):
        raise MemError(f"instinct id {instinct_id!r} must be lowercase letters, digits and hyphens (max 64)")
    return instinct_id


def add_instinct(scope: str, instinct_id: str, trigger: str | None, action: str | None, evidence: str | None,
                 cwd: Path) -> str:
    d = scope_dir(scope, cwd)
    path = instincts_dir(d) / f"{check_id(instinct_id)}.md"
    with file_lock():
        if path.exists():
            i = parse_instinct(path)
            i["confidence"] = min(MAX_CONFIDENCE, round(effective_confidence(i) + STEP_UP, 2))
            i["seen"] += 1
            if trigger:
                i["trigger"] = redact(trigger)
            if action:
                i["action"] = redact(action)
            verb = "reinforced"
        else:
            if not trigger or not action:
                raise MemError("a new instinct needs --trigger and --action")
            drop_lowest(d, MAX_INSTINCTS_PER_SCOPE - 1)
            i = {"id": instinct_id, "trigger": redact(trigger), "action": redact(action), "confidence": START_CONFIDENCE,
                 "seen": 1, "created": today(), "evidence": []}
            verb = "created"
        i["last_seen"] = today()
        if evidence:
            i["evidence"].append(f"{today()}: {_one_line(redact(evidence))}")
        write_atomic(path, format_instinct(i))
    if scope == "user":
        sync()
    return f"{verb} {scope} instinct {instinct_id} ({i['confidence']:.0%})"


def weaken_instinct(scope: str, instinct_id: str, evidence: str | None, cwd: Path) -> str:
    d = scope_dir(scope, cwd)
    path = instincts_dir(d) / f"{check_id(instinct_id)}.md"
    with file_lock():
        if not path.exists():
            raise MemError(f"no {scope} instinct named {instinct_id}")
        i = parse_instinct(path)
        # Stored confidence is the value as of last_seen, so the step is taken off the stored value and last_seen stays
        # put: decay keeps running and is not reset. The threshold is checked on the effective value.
        i["confidence"] = round(i["confidence"] - STEP_DOWN, 2)
        now = effective_confidence(i)
        if now < MIN_CONFIDENCE:
            path.unlink()
            msg = f"deleted {scope} instinct {instinct_id}"
        else:
            if evidence:
                i["evidence"].append(f"{today()}: contradicted: {_one_line(redact(evidence))}")
            write_atomic(path, format_instinct(i))
            msg = f"weakened {scope} instinct {instinct_id} ({now:.0%})"
    if scope == "user":
        sync()
    return msg


def forget_instinct(scope: str, instinct_id: str, cwd: Path) -> str:
    path = instincts_dir(scope_dir(scope, cwd)) / f"{check_id(instinct_id)}.md"
    with file_lock():  # same lock as add_instinct, so a concurrent add cannot land between the check and the delete
        if not path.exists():
            raise MemError(f"no {scope} instinct named {instinct_id}")
        path.unlink()
    if scope == "user":
        sync()
    return f"forgot {scope} instinct {instinct_id}"


def promote(instinct_id: str, cwd: Path) -> str:
    src = instincts_dir(repo_dir(cwd)) / f"{check_id(instinct_id)}.md"  # type: ignore[arg-type]
    with file_lock():
        if not src.exists():
            raise MemError(f"no repository instinct named {instinct_id}")
        i = parse_instinct(src)
        dst = instincts_dir(memory_root()) / src.name
        if dst.exists():
            g = parse_instinct(dst)
            g["confidence"] = min(MAX_CONFIDENCE, round(max(effective_confidence(g), effective_confidence(i)) + STEP_UP, 2))
            g["seen"] += i["seen"]
            g["last_seen"] = today()
            g["evidence"] += i["evidence"]
            i = g
        else:
            drop_lowest(memory_root(), MAX_INSTINCTS_PER_SCOPE - 1)
        i["evidence"].append(f"{today()}: promoted from {repo_identity(cwd)[1]}")  # type: ignore[index]
        write_atomic(dst, format_instinct(i))
        src.unlink()
    sync()
    return f"promoted {instinct_id} to global ({i['confidence']:.0%})"


def drop_lowest(d: Path, keep: int) -> None:
    """Delete the lowest-confidence instincts in d until at most `keep` are left."""
    items = sorted(load_instincts(d), key=effective_confidence)
    for i in items[: max(0, len(items) - keep)]:
        i["path"].unlink(missing_ok=True)


PRUNE_STAMP = ".pruned_at"  # holds the date of the last prune, so session starts prune at most once a day


def _still_stale(path: Path) -> bool:
    """Re-reads the file right before it is deleted: it may have been reinforced, or removed, since it was loaded."""
    try:
        return effective_confidence(parse_instinct(path)) < MIN_CONFIDENCE
    except (MemError, OSError):
        return False


def prune(force: bool = True) -> int:
    """Delete instincts that have decayed below the minimum. Returns how many were removed.
    Without force it does nothing when it already ran today. Callers must not hold file_lock()."""
    stamp = memory_root() / PRUNE_STAMP
    if not force and stamp.exists() and stamp.read_text(encoding="utf-8", errors="replace").strip() == today():
        return 0
    removed = 0
    with file_lock():  # same lock as add_instinct and weaken_instinct, so no delete lands between their read and write
        for d in [memory_root(), *(memory_root() / "repos").glob("*")]:
            for i in load_instincts(d):
                if effective_confidence(i) < MIN_CONFIDENCE and _still_stale(i["path"]):
                    i["path"].unlink(missing_ok=True)
                    removed += 1
        write_atomic(stamp, today())
    return removed


def promotion_candidates() -> list[str]:
    """Instinct ids live in two or more different repositories, averaging at least 0.8 effective confidence (ECC's
    rule). One repository reinforcing an instinct many times still counts once."""
    by_id: dict[str, dict[str, float]] = {}
    for d in (memory_root() / "repos").glob("*"):
        for i in load_instincts(d):
            c = effective_confidence(i)
            if c >= MIN_CONFIDENCE:
                by_id.setdefault(i["id"], {})[d.name] = c
    return sorted(k for k, v in by_id.items() if len(v) >= 2 and sum(v.values()) / len(v) >= 0.8)


def min_confidence() -> float:
    try:
        return float(os.environ["LOCAL_MEMORY_MIN_CONFIDENCE"])
    except (KeyError, ValueError):
        return ACTIVE_MIN_CONFIDENCE


def max_instincts() -> int:
    try:
        return max(0, int(os.environ["LOCAL_MEMORY_MAX_INSTINCTS"]))
    except (KeyError, ValueError):
        return ACTIVE_MAX_INSTINCTS


def active_instincts(d: Path | None) -> list[tuple[float, dict]]:
    ranked = [(effective_confidence(i), i) for i in load_instincts(d)]
    ranked = [(c, i) for c, i in ranked if c >= min_confidence() and i["action"]]
    ranked.sort(key=lambda ci: (-ci[0], ci[1]["id"]))
    return ranked[: max_instincts()]


def _clip(text: str, limit: int | None = None) -> str:
    limit = limit or MAX_FACT_CHARS
    return text if len(text) <= limit else text[: limit - 1] + "…"


def instinct_lines(ranked: list[tuple[float, dict]]) -> list[str]:
    return [f"- [{c:.0%}] {_clip(i['trigger'])}: {_clip(_one_line(i['action']))}" for c, i in ranked]


# ---------- context blocks ----------


def capped(lines: list[str], limit: int | None = None, budget: int | None = None) -> list[str]:
    """The newest lines that fit in the line and character budget, in their original order. The tail says how many
    older lines were left out."""
    limit, budget = limit or MAX_MEMORY_LINES, budget or MAX_MEMORY_CHARS
    lines = [_safe_line(line) for line in lines]
    kept: list[str] = []
    used = 0
    for line in reversed(lines):
        if len(kept) >= limit or used + len(line) + 1 > budget:
            break
        kept.append(line)
        used += len(line) + 1
    skipped = len(lines) - len(kept)
    if skipped == 0:
        return lines
    kept.reverse()
    return kept + [f"- {skipped} more not loaded (older facts); run `mem.py recall`"]


def repo_context(cwd: Path) -> str:
    ident = repo_identity(cwd)
    if ident is None:
        return ""
    d = memory_root() / "repos" / ident[0]
    facts = read_facts(d) if d.is_dir() else []
    ranked = active_instincts(d if d.is_dir() else None)
    pending = count_unreviewed(d) if d.is_dir() else 0
    if not facts and not ranked and pending < 20:
        return ""
    parts = [f"# Local memory for this repository ({ident[1]})",
             "Notes saved in earlier sessions. Check a fact against the code before relying on it."]
    if facts:
        parts += ["", "## Facts", *capped(facts)]
    if ranked:
        parts += ["", "## Learned habits (instincts, with confidence)", *instinct_lines(ranked)]
    if pending >= 20:
        parts += ["", f"{pending} prompts and tool failures were logged since the last reflection. When the current "
                      "task is done, suggest the user runs /alx-reflect."]
    return "\n".join(parts)


def ps_quote(text: str) -> str:
    # PowerShell single-quoted strings end at any of these quote characters, so double each one.
    for ch in "'‘’‚‛":
        text = text.replace(ch, ch * 2)
    return "'" + text + "'"


def command_prefix(shell: str, python: str, mem: str) -> str:
    """The start of a mem.py command, quoted for the given shell. install.py uses this too."""
    if shell == "powershell":
        return f"& {ps_quote(python)} {ps_quote(mem)}"  # PowerShell needs the call operator before a quoted name
    return f"{shlex.quote(python)} {shlex.quote(mem)}"


def instructions_text() -> str:
    root = memory_root()
    facts = read_facts(root)
    ranked = active_instincts(root)
    shell = "powershell" if os.name == "nt" else "bash"
    mem = command_prefix(shell, sys.executable, str(Path(__file__).resolve()))  # the interpreter running this mem.py
    parts = [
        "---",
        'applyTo: "**"',
        "---",
        "# Local memory",
        "",
        "Generated by local_memory's mem.py from your saved memory. Don't edit this file: use the remember skill, or "
        f"edit {root / 'user.md'} and run `{mem} sync`.",
        "",
        "## About the user",
        *(capped(facts) or ["- (nothing saved yet)"]),
    ]
    if ranked:
        parts += ["", "## Learned habits (instincts, with confidence)", *instinct_lines(ranked)]
    parts += [
        "",
        "## Using memory",
        "- Repository memory is added at the start of each session when the hooks run. If no \"Local memory for this "
        f"repository\" block is in your context and you are working in a git repository, run `{mem} recall` first.",
        "- When the user states a lasting preference, corrects you in a way that will matter again, or says "
        "\"remember\" or \"forget\", use the remember skill.",
        "- Never save secrets, tokens or personal data about other people.",
        "",
    ]
    return "\n".join(parts)


def paused_dir() -> Path:
    return memory_root() / "paused"  # exists only while Local Memory is disabled


def sync(force: bool = True) -> str:
    if paused_dir().exists():
        return "paused (run enable first)"  # keeps the instructions file from coming back while disabled
    prune(force=force)  # session start passes force=False: stale instincts go at most once a day
    path = instructions_file()
    text = instructions_text()
    if not path.exists() or path.read_text(encoding="utf-8", errors="replace") != text:
        write_atomic(path, text)
    return f"wrote {path}"


AGENT_SKILLS = ("alx-remember", "alx-reflect")  # the skills the toggle hides from the agent
MODEL_FLAG = re.compile(r"^disable-model-invocation:.*\n", re.M)


def _set_model_invocation(skill: Path, disabled: bool) -> None:
    text = skill.read_text(encoding="utf-8")
    flag = f"disable-model-invocation: {'true' if disabled else 'false'}\n"
    if MODEL_FLAG.search(text):
        text = MODEL_FLAG.sub(flag, text, count=1)
    else:  # insert right after the opening front matter line
        text = re.sub(r"\A---\r?\n", lambda m: m.group(0) + flag, text, count=1)
    skill.write_text(text, encoding="utf-8")


def _move_pair(src: Path, dst: Path) -> None:
    if src.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        os.replace(src, dst)


def disable() -> str:
    """Pause Local Memory without losing anything: hooks and instructions file move into paused/, skills turn user-only."""
    stash = paused_dir()
    if stash.exists():
        return "already disabled"
    home = copilot_home()
    private_mkdir(stash)
    _move_pair(home / "hooks" / "local-memory.json", stash / "local-memory.json")
    _move_pair(instructions_file(), stash / "local-memory.instructions.md")
    for name in AGENT_SKILLS:
        skill = home / "skills" / name / "SKILL.md"
        if skill.exists():
            _set_model_invocation(skill, True)
    return "disabled: hooks and instructions moved to " + str(stash) + ", skills user-only. Start a new session. Run /alx-enable-memory to resume."


def enable() -> str:
    stash = paused_dir()
    if not stash.exists():
        return "already enabled"
    home = copilot_home()
    _move_pair(stash / "local-memory.json", home / "hooks" / "local-memory.json")
    _move_pair(stash / "local-memory.instructions.md", instructions_file())
    shutil.rmtree(stash)
    for name in AGENT_SKILLS:
        skill = home / "skills" / name / "SKILL.md"
        if skill.exists():
            _set_model_invocation(skill, False)
    sync()  # refresh the instructions file in case memory changed while paused
    return "enabled: hooks, instructions and skills restored. Start a new session."


def recall(cwd: Path) -> str:
    root = memory_root()
    out = []
    ident = repo_identity(cwd)
    if ident:
        d = root / "repos" / ident[0]
        out += [f"# Repository memory ({ident[1]})", *(read_facts(d) or ["- (none)"]), "",
                "# Repository instincts", *(instinct_lines([(effective_confidence(i), i) for i in load_instincts(d)])
                                            or ["- (none)"]), ""]
    else:
        out += ["(not in a git repository: showing user memory only)", ""]
    out += ["# User memory", *(read_facts(root) or ["- (none)"]), "",
            "# Global instincts", *(instinct_lines([(effective_confidence(i), i) for i in load_instincts(root)])
                                    or ["- (none)"])]
    return "\n".join(out)


def list_instincts(cwd: Path) -> str:
    rows = []
    d = repo_dir(cwd, required=False)
    for scope, where in (("repo", d), ("user", memory_root())):
        for i in load_instincts(where):
            c = effective_confidence(i)
            flag = "active" if c >= min_confidence() else "tentative"
            rows.append(f"{scope:4} {c:4.0%} {flag:9} {i['id']}: {i['trigger']} -> {_one_line(i['action'])}")
    candidates = promotion_candidates()
    if candidates:
        rows += ["", "Ready to promote to global (2+ repositories, average 80%+): " + ", ".join(candidates)]
    return "\n".join(rows) or "no instincts yet"


# ---------- observations (written by hooks, read by /alx-reflect) ----------


def observations_path(d: Path) -> Path:
    return d / "observations.jsonl"


def rotated_path(d: Path, n: int) -> Path:
    return d / f"observations.{n}.jsonl"


def rotate_observations(d: Path) -> bool:
    """observations.jsonl -> .1, .1 -> .2, ... ; the oldest beyond KEEP_ROTATED is dropped. True if that dropped records."""
    dropped = rotated_path(d, KEEP_ROTATED).exists()
    rotated_path(d, KEEP_ROTATED).unlink(missing_ok=True)
    for n in range(KEEP_ROTATED - 1, 0, -1):
        if rotated_path(d, n).exists():
            os.replace(rotated_path(d, n), rotated_path(d, n + 1))
    os.replace(observations_path(d), rotated_path(d, 1))
    return dropped


def counter_path(d: Path) -> Path:
    return d / "observations.count"  # sidecar: unreviewed non-stop records in observations.jsonl


def _obs_files(d: Path) -> list[Path]:
    return [observations_path(d), *(rotated_path(d, n) for n in range(1, KEEP_ROTATED + 1))]


def _remove_obs(d: Path) -> None:
    """Unlocked: the log, all rotated copies and the count sidecar (callers hold file_lock())."""
    for p in [*_obs_files(d), counter_path(d)]:
        p.unlink(missing_ok=True)


def _bump_count(d: Path, delta: int) -> None:
    p = counter_path(d)
    try:
        n = int(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        _rescan_count(d)  # no sidecar yet: one scan, which already includes the record just written
        return
    write_atomic(p, f"{max(0, n + delta)}\n")


def logging_off() -> bool:
    return os.environ.get("LOCAL_MEMORY_LOG", "").strip().lower() == "off"


def log_observation(d: Path, record: dict) -> None:
    if logging_off():
        return
    private_mkdir(d)
    line = (json.dumps(record, ensure_ascii=False) + "\n").encode("utf-8")
    with file_lock():
        p = observations_path(d)
        if not p.exists():  # no active log, so the sidecar cannot be trusted: the next bump rescans
            counter_path(d).unlink(missing_ok=True)
        dropped = False
        if p.exists() and p.stat().st_size > MAX_OBSERVATION_BYTES:
            dropped = rotate_observations(d)  # rotation keeps every record in .1-.3, so the count only changes if one was dropped
        fd = os.open(p, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            if os.write(fd, line) != len(line):
                raise OSError(f"short write to {p}")
        finally:
            os.close(fd)
        if dropped:  # the oldest file is gone: rescan, which includes this record
            _rescan_count(d)
        elif record.get("kind") != "stop" and _after(record, parse_ts(reflected_at(d))):
            _bump_count(d, 1)


def reflected_at(d: Path) -> str:
    p = d / "reflected_at"
    return p.read_text(encoding="utf-8", errors="replace").strip() if p.exists() else ""


def parse_ts(value) -> dt.datetime | None:
    """Timestamps as aware datetimes. Naive or 'Z' forms are accepted; anything else is None."""
    if not isinstance(value, str):
        return None
    try:
        t = dt.datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def _after(rec, since: dt.datetime | None) -> bool:
    ts = parse_ts(rec.get("ts")) if isinstance(rec, dict) else None
    return ts is not None and (since is None or ts > since)


def _scan_unreviewed(d: Path) -> list[dict]:
    """Unlocked: callers that already hold file_lock() use this (the lock is not reentrant)."""
    since = parse_ts(reflected_at(d))
    paths = [rotated_path(d, n) for n in range(KEEP_ROTATED, 0, -1)] + [observations_path(d)]
    text = "".join(p.read_text(encoding="utf-8", errors="replace") for p in paths if p.exists())
    out = []
    for line in text.splitlines():
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if _after(rec, since):
            out.append(rec)
    return out


def unreviewed(d: Path) -> list[dict]:
    with file_lock():  # one consistent snapshot, so no rotation happens mid-read
        return _scan_unreviewed(d)


def _rescan_count(d: Path) -> int:
    n = sum(1 for r in _scan_unreviewed(d) if r.get("kind") != "stop")
    write_atomic(counter_path(d), f"{n}\n")
    return n


def count_unreviewed(d: Path) -> int:
    """Used at every session start, so it reads the sidecar instead of parsing the whole log."""
    if not observations_path(d).exists():
        return 0
    try:
        return int(counter_path(d).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    with file_lock():
        return _rescan_count(d)


def show_observations(cwd: Path, limit: int = 200) -> str:
    d = repo_dir(cwd, required=False) or memory_root() / "no-repo"
    recs = unreviewed(d)[-limit:]
    if not recs:
        return "nothing logged since the last reflection"
    lines = []
    for r in recs:
        kind = r.get("kind")
        if kind == "prompt":
            mark = " [correction?]" if r.get("correction") else ""
            lines.append(f"{r['ts']} prompt{mark}: {r.get('text', '')}")
        elif kind == "tool_failure":
            lines.append(f"{r['ts']} {r.get('tool')} failed: {r.get('error', '')} | args: {r.get('args', '')}")
        elif kind == "stop":
            lines.append(f"{r['ts']} turn ended (transcript: {r.get('transcript', '')})")
    return "\n".join(lines)


def mark_reflected(cwd: Path) -> str:
    d = repo_dir(cwd, required=False, create=True) or memory_root() / "no-repo"
    with file_lock():  # same lock as log_observation, which reads reflected_at and bumps the count
        private_mkdir(d)
        write_atomic(d / "reflected_at", now_iso() + "\n")
        write_atomic(counter_path(d), "0\n")
    return "observations marked as reviewed"


# ---------- status, clear, export, import ----------


def _size(p: Path) -> int:
    return p.stat().st_size if p.exists() else 0


def hook_log_path() -> Path:
    return memory_root() / "hook-errors.log"


def log_hook_error(line: str) -> None:
    p = hook_log_path()
    private_mkdir(p.parent)
    if _size(p) > MAX_HOOK_LOG_BYTES:
        os.replace(p, p.with_name("hook-errors.1.log"))  # keeps one old copy, so the disk use stays bounded
    with p.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def status(cwd: Path) -> str:
    root = memory_root()
    ident = repo_identity(cwd)
    repo = root / "repos" / ident[0] if ident else None
    obs_dir = repo or root / "no-repo"
    obs_bytes = sum(_size(p) for p in _obs_files(obs_dir))
    context = (repo_context(cwd) if ident else "") + instructions_text()
    lines = [
        f"memory:                {root}",
        f"user memory:           {len(read_facts(root))} facts, {len(load_instincts(root))} global instincts",
    ]
    if ident:
        lines += [
            f"repository:            {ident[1]}",
            f"repository memory:     {len(read_facts(repo))} facts, {len(load_instincts(repo))} instincts",
            f"unreviewed log lines:  {count_unreviewed(repo)}",
        ]
    else:
        lines.append("repository:            (not in a git repository)")
    lines += [
        f"observation log:       {obs_bytes} bytes (rotated at {MAX_OBSERVATION_BYTES})",
        f"hook-errors.log:       {_size(hook_log_path())} bytes (rotated at {MAX_HOOK_LOG_BYTES})",
        f"estimated context:     ~{len(context) // 4} tokens per session",
        f"config:                {config_path()}" + ("" if config_path().exists() else " (not found, defaults used)"),
        *(f"  ignored: {p}" for p in CONFIG_PROBLEMS),
    ]
    if hook_log_path().exists():
        tail = hook_log_path().read_text(encoding="utf-8", errors="replace").splitlines()[-5:]
        if tail:
            lines += ["", "last hook errors:", *(f"  {t}" for t in tail)]
    return "\n".join(lines)


def clear(target: str, cwd: Path) -> str:
    """target: obs, instincts or repo (the repository of cwd), or all (everything under the memory root)."""
    root = memory_root()
    if target == "all":
        # Only data: the installed mem.py and .lock share this folder, so they are never listed here.
        with file_lock():
            for name in ("user.md", "instincts", "repos", "no-repo", "reflected_at"):
                p = root / name
                if p.is_dir():
                    shutil.rmtree(p)
                else:
                    p.unlink(missing_ok=True)
            _remove_obs(root)
            for p in root.glob("hook-errors*.log"):
                p.unlink(missing_ok=True)
        sync()  # after the lock: sync is not run under file_lock
        return f"cleared all local memory in {root}"
    ident = repo_identity(cwd)
    if ident is None:
        raise MemError(f"{cwd} is not inside a git repository; --all clears everything")
    d = root / "repos" / ident[0]
    with file_lock():
        if target == "repo":
            shutil.rmtree(d, ignore_errors=True)
        elif target == "instincts":
            shutil.rmtree(instincts_dir(d), ignore_errors=True)
        else:  # obs
            _remove_obs(d)
            (d / "reflected_at").unlink(missing_ok=True)
    return f"cleared {target} for {ident[1]}"


def _instinct_record(i: dict) -> dict:
    keys = ("id", "trigger", "action", "confidence", "seen", "created", "last_seen", "evidence")
    return {k: i[k] for k in keys if i.get(k) is not None}


def export_memory(path: Path) -> str:
    root = memory_root()
    with file_lock():  # one consistent snapshot: no write lands halfway through the read
        data = {"version": EXPORT_VERSION, "user_memory": read_facts(root),
                "global_instincts": [_instinct_record(i) for i in load_instincts(root)], "repositories": {}}
        for d in sorted((root / "repos").glob("*")) if (root / "repos").is_dir() else []:
            try:  # a missing or corrupt repo.json is treated as no metadata: the export must not fail on it
                meta = json.loads((d / "repo.json").read_text(encoding="utf-8"))
            except (OSError, ValueError):
                meta = {}
            if not isinstance(meta, dict):
                meta = {}
            data["repositories"][d.name] = {"source": meta.get("source") or d.name, "memory": read_facts(d),
                                            "instincts": [_instinct_record(i) for i in load_instincts(d)]}
        write_atomic(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return f"exported {len(data['user_memory'])} user facts, {len(data['global_instincts'])} global instincts and " \
           f"{len(data['repositories'])} repositories to {path}"


def import_memory(path: Path) -> str:
    """Merges an export into this memory: existing facts are kept (duplicates skipped) and existing instincts with
    the same id are left alone. Everything is validated before the first write."""
    root = memory_root()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or data.get("version") != EXPORT_VERSION:
            raise ValueError(f"not a version {EXPORT_VERSION} local memory export")
        plan = [(root, None, _checked_facts(data.get("user_memory", [])),
                 [_checked_instinct(r) for r in data.get("global_instincts", [])])]
        for repo_id, body in data.get("repositories", {}).items():
            if not ID_RE.match(repo_id):
                raise ValueError(f"bad repository id {repo_id!r}")
            plan.append((root / "repos" / repo_id, body.get("source", ""), _checked_facts(body.get("memory", [])),
                         [_checked_instinct(r) for r in body.get("instincts", [])]))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError, AttributeError,
            OverflowError, MemError) as exc:
        raise MemError(f"cannot import {path}: {exc}") from exc

    facts_added = instincts_added = instincts_skipped = 0
    with file_lock():  # read-modify-write of memory files: must not interleave with remember/add_instinct
        for d, source, facts, instincts in plan:
            private_mkdir(d)
            if source is not None and not (d / "repo.json").exists():
                write_atomic(d / "repo.json", json.dumps({"id": d.name, "source": source}, indent=2) + "\n")
            current = read_facts(d)
            known = {_norm(f) for f in current}
            added = 0
            for line in facts:  # already redacted and checked by _checked_facts
                if _norm(line) not in known:
                    known.add(_norm(line))
                    current.append(line if line.startswith("- ") else f"- {line}")
                    added += 1
            if added:
                write_facts(d, current)
            facts_added += added
            for i in instincts:
                if (instincts_dir(d) / f"{i['id']}.md").exists():
                    instincts_skipped += 1
                    continue
                write_atomic(instincts_dir(d) / f"{i['id']}.md", format_instinct(i))
                instincts_added += 1
    sync()  # after the lock: sync is not run under file_lock
    return (f"imported {facts_added} facts and {instincts_added} instincts from {path}"
            f" ({instincts_skipped} instincts skipped because the id already exists)")


def _checked_facts(value) -> list[str]:
    """Imported facts get the same treatment as remember: one line, secrets redacted, at most MAX_FACT_CHARS."""
    if not isinstance(value, list) or not all(isinstance(f, str) for f in value):
        raise MemError("facts must be a list of strings")
    out = []
    for f in value:
        text = redact(_one_line(f))
        if len(text) > MAX_FACT_CHARS:
            raise MemError(f"a fact is {len(text)} characters; keep one fact under {MAX_FACT_CHARS}")
        if text:
            out.append(text)
    return out


def _iso_date(value) -> str:
    if isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        try:
            return dt.date.fromisoformat(value).isoformat()
        except ValueError:
            pass
    return today()  # a bad date would make effective_confidence ignore decay, so fall back to today


def _checked_instinct(rec: dict) -> dict:
    if not isinstance(rec, dict):
        raise MemError("each instinct must be an object")
    i = {"created": today(), "last_seen": today(), "seen": 1, "evidence": [], "confidence": START_CONFIDENCE, **rec}
    i["id"] = check_id(str(i["id"]))
    conf = i["confidence"]
    if isinstance(conf, bool) or not isinstance(conf, (int, float)):
        raise MemError(f"instinct {i['id']} has a non-numeric confidence {conf!r}")
    i["confidence"] = min(MAX_CONFIDENCE, max(0.0, float(conf)))  # NaN falls to 0.0 here
    i["seen"] = int(i["seen"])
    i["created"] = _iso_date(i["created"])
    i["last_seen"] = _iso_date(i["last_seen"])
    i["trigger"] = redact(str(i["trigger"]))
    i["action"] = redact(str(i["action"]))
    if not isinstance(i["evidence"], list):
        raise MemError(f"instinct {i['id']} evidence must be a list")
    i["evidence"] = [redact(str(e)) for e in i["evidence"]]
    return i


# ---------- hooks ----------


def _get(payload: dict, *keys: str, default=None):
    for k in keys:
        if k in payload and payload[k] is not None:
            return payload[k]
    return default


def _short(value, limit: int) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, default=str)
    text = redact(" ".join(text.split()))
    return text if len(text) <= limit else text[:limit] + "…"


def _tool_args(tool: str, raw) -> str:
    if tool in TERMINAL_TOOLS:
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except json.JSONDecodeError:
                pass
        command = raw.get("command", "") if isinstance(raw, dict) else raw
        words = str(command).split()
        raw = words[0] if words else ""  # the rest of a shell command can carry paths, tokens and output
    return _short(raw, 300)


def run_hook(event: str, raw: str) -> str:
    """Returns what to print on stdout. Accepts both the camelCase payloads and the VS Code compatible ones."""
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    cwd = Path(_get(payload, "cwd", default=os.getcwd()))
    if event in ("user-prompt", "tool-failure", "agent-stop") and logging_off():
        return ""  # before repo_dir, so no repos/<id>/ or repo.json gets created
    obs_dir = repo_dir(cwd, required=False, create=event != "session-start") or memory_root() / "no-repo"
    ts = now_iso()

    if event == "session-start":
        sync(force=False)  # picks up hand edits of user.md
        context = repo_context(cwd)
        return json.dumps({"additionalContext": context}) if context else ""
    if event == "user-prompt":
        text = str(_get(payload, "prompt", default=""))
        if text.strip():
            log_observation(obs_dir, {"ts": ts, "kind": "prompt", "text": _short(text, MAX_PROMPT_CHARS),
                                      "correction": bool(CORRECTION_RE.search(text))})
        return ""
    if event == "tool-failure":
        tool = str(_get(payload, "toolName", "tool_name", default="?"))
        log_observation(obs_dir, {
            "ts": ts, "kind": "tool_failure",
            "tool": tool,
            "args": _tool_args(tool, _get(payload, "toolArgs", "tool_input", default="")),
            "error": _short(_get(payload, "error", default=""), 500),
        })
        return ""
    if event == "agent-stop":
        log_observation(obs_dir, {"ts": ts, "kind": "stop",
                                  "transcript": str(_get(payload, "transcriptPath", "transcript_path", default=""))})
        return ""
    raise MemError(f"unknown hook event {event!r}")


# ---------- CLI ----------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="mem.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("--cwd", default=os.getcwd(), help="the repository to use (default: current directory)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    def scoped(p, default="repo"):
        g = p.add_mutually_exclusive_group()
        g.add_argument("--repo", dest="scope", action="store_const", const="repo")
        g.add_argument("--user", dest="scope", action="store_const", const="user")
        p.set_defaults(scope=default)

    p = sub.add_parser("remember")
    scoped(p)
    p.add_argument("--stdin", action="store_true")
    p.add_argument("text", nargs="*")
    p = sub.add_parser("forget")
    scoped(p)
    p.add_argument("--all", action="store_true")
    p.add_argument("--dry-run", action="store_true", help="print the lines that would be removed and change nothing")
    p.add_argument("text", nargs="+")
    sub.add_parser("recall")
    p = sub.add_parser("instinct")
    scoped(p)
    p.add_argument("id")
    p.add_argument("--stdin", action="store_true")
    p.add_argument("--trigger")
    p.add_argument("--action")
    p.add_argument("--evidence")
    p = sub.add_parser("weaken")
    scoped(p)
    p.add_argument("id")
    p.add_argument("--evidence")
    sub.add_parser("instincts")
    p = sub.add_parser("promote")
    p.add_argument("id")
    sub.add_parser("observations")
    sub.add_parser("mark-reflected")
    sub.add_parser("sync")
    sub.add_parser("disable")
    sub.add_parser("enable")
    sub.add_parser("where")
    p = sub.add_parser("hook")
    p.add_argument("event")
    p = sub.add_parser("forget-instinct")
    scoped(p)
    p.add_argument("id")
    sub.add_parser("status")
    p = sub.add_parser("clear")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--obs", dest="target", action="store_const", const="obs")
    g.add_argument("--instincts", dest="target", action="store_const", const="instincts")
    g.add_argument("--repo", dest="target", action="store_const", const="repo")
    g.add_argument("--all", dest="target", action="store_const", const="all")
    p.add_argument("--yes", action="store_true", help="required: clear deletes data")
    p = sub.add_parser("export")
    p.add_argument("file")
    p = sub.add_parser("import")
    p.add_argument("file")

    args = parser.parse_args(argv)
    cwd = Path(args.cwd)
    load_config()

    if args.cmd == "hook":
        # A hook must never break the session: log the error and exit 0 with no output.
        try:
            out = run_hook(args.event, sys.stdin.read())
            if out:
                print(out)
        except Exception as exc:  # noqa: BLE001
            try:
                log_hook_error(f"{now_iso()} {args.event}: {exc!r}")
            except OSError:
                pass
        return 0

    # --stdin takes user text through a quoted heredoc, so the shell never expands it.
    stdin_text = sys.stdin.read() if getattr(args, "stdin", False) else ""
    trigger, action = getattr(args, "trigger", None), getattr(args, "action", None)
    if args.cmd == "instinct" and args.stdin:
        head, _, rest = stdin_text.strip("\n").partition("\n")
        trigger, action = head.strip() or None, rest.strip() or None

    try:
        if args.cmd == "remember":
            out = remember(args.scope, stdin_text if args.stdin else " ".join(args.text), cwd)
        elif args.cmd == "forget":
            out = forget(args.scope, " ".join(args.text), cwd, args.all, args.dry_run)
        elif args.cmd == "recall":
            out = recall(cwd)
        elif args.cmd == "instinct":
            out = add_instinct(args.scope, args.id, trigger, action, args.evidence, cwd)
        elif args.cmd == "weaken":
            out = weaken_instinct(args.scope, args.id, args.evidence, cwd)
        elif args.cmd == "instincts":
            out = list_instincts(cwd)
        elif args.cmd == "promote":
            out = promote(args.id, cwd)
        elif args.cmd == "observations":
            out = show_observations(cwd)
        elif args.cmd == "mark-reflected":
            out = mark_reflected(cwd)
        elif args.cmd == "sync":
            out = sync()
        elif args.cmd == "disable":
            out = disable()
        elif args.cmd == "enable":
            out = enable()
        elif args.cmd == "forget-instinct":
            out = forget_instinct(args.scope, args.id, cwd)
        elif args.cmd == "status":
            out = status(cwd)
        elif args.cmd == "clear":
            if not args.yes:
                raise MemError(f"refusing to clear without --yes (this deletes data: --{args.target})")
            out = clear(args.target, cwd)
        elif args.cmd == "export":
            out = export_memory(Path(args.file))
        elif args.cmd == "import":
            out = import_memory(Path(args.file))
        else:  # where
            ident = repo_identity(cwd)
            out = "\n".join([
                f"memory:       {memory_root()}",
                f"instructions: {instructions_file()}",
                f"config:       {config_path()}",
                f"repository:   {ident[1] + ' -> repos/' + ident[0] if ident else '(not in a git repository)'}",
            ])
    except (MemError, OSError, ValueError) as exc:  # ValueError: JSONDecodeError and UnicodeDecodeError too
        print(f"mem.py: {exc}", file=sys.stderr)
        return 1
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
