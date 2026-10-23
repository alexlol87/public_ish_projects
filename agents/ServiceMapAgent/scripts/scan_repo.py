#!/usr/bin/env python3
"""Pulls the mechanical facts out of one repository so the Service Mapper agent doesn't have to search for them.

    python3 scan_repo.py <repo folder> [--name <repo name>] [--out <facts.json>]

Finds, with a path:line for each: Spring endpoints (class prefix + @Get/Post/Put/Patch/Delete/RequestMapping), FastAPI
and Flask routes, Feign and @HttpExchange clients with every place their methods are called (and in which method),
RestClient / WebClient / RestTemplate call sites, Kafka listeners and send() calls, @Scheduled jobs, JPA entities and
their tables, Spring Data repositories and @Query counts, URL-like config keys, OpenAPI files, GitHub Actions workflows
and Terraform resources. Writes JSON (stdout without --out). Reads files only; runs nothing but `git rev-parse HEAD`.

It is regex-based: it finds the common, annotation-driven patterns, not everything. The agent still reads the code for
what needs judgement (which endpoint triggers a call, what an endpoint is for, the step-by-step flows) and for anything
the scan missed. Python 3.9+, standard library only.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

SKIP_DIRS = {".git", "node_modules", "target", "build", "dist", ".gradle", ".idea", ".venv", "venv", "__pycache__", "test", "tests"}
HTTP = ("Get", "Post", "Put", "Patch", "Delete")
MAPPING = re.compile(r"@(Get|Post|Put|Patch|Delete|Request)Mapping\b(\((?P<args>[^)]*)\))?")
EXCHANGE = re.compile(r"@(Get|Post|Put|Patch|Delete|Http)Exchange\b(\((?P<args>[^)]*)\))?")
STRINGS = re.compile(r'"([^"]*)"')
VALUES = r'\{(?:\s*"[^"]*"\s*,?)*\s*\}|"[^"]*"'  # "x" or {"x", "y"}; paths contain braces, so not [^}]*
# A method declaration, abstract (Feign, @HttpExchange) or with a body; statements are filtered out by NOT_DECL.
METHOD_SIG = re.compile(r"^\s*(?:(?:public|protected|private|static|final|synchronized|default|abstract)\s+)*[\w<>\[\],?.]+(?:<[^=()]*>)?\s+(\w+)\s*\(")
NOT_DECL = ("return", "new ", "throw", "if", "for", "while", "switch", "catch", "else", "//", "*", "/*", "@")
TYPE_DECL = re.compile(r"\b(class|interface|record|enum)\s+(\w+)")
SECRET_KEY = re.compile(r"pass(word)?|secret|token|credential|private[-_.]?key|api[-_.]?key", re.I)


def files(root, *suffixes):
    for p in sorted(root.rglob("*")):
        if p.is_file() and p.suffix in suffixes and not (SKIP_DIRS & set(p.relative_to(root).parts[:-1])):
            yield p


def ref(root, name, path, line):
    return f"{name}/{path.relative_to(root).as_posix()}:{line}"


def attr(args, *names):
    """Strings of a named attribute (path = "/x" or path = {"/a", "/b"}); '' in names also takes the leading positional one."""
    args = args or ""
    for n in names:
        if n:
            m = re.search(rf'\b{n}\s*=\s*({VALUES})', args)
            if m:
                return STRINGS.findall(m.group(1))
    if "" in names:
        m = re.match(rf'\s*({VALUES})', args)
        if m:
            return STRINGS.findall(m.group(1))
    return []


def http_method(kind, args):
    if kind in HTTP:
        return kind.upper()
    m = re.search(r"(?:RequestMethod|HttpMethod)\.(\w+)", args or "")
    return m.group(1) if m else "ANY"


def join(*parts):
    path = "/".join(p.strip("/") for p in parts if p and p.strip("/"))
    return "/" + path


def scan_java(root, name):
    out = {k: [] for k in ("endpoints", "clients", "http_calls", "listeners", "producers", "scheduled", "entities", "repositories")}
    client_methods = {}  # java method name -> client entry, for finding call sites
    sources = list(files(root, ".java", ".kt"))
    for path in sources:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        pending, type_name, type_kind, prefix, feign, exchange_prefix, current = [], None, None, "", None, None, None
        for i, line in enumerate(lines, 1):
            s = line.strip()
            if s.startswith("@"):
                pending.append((i, s))
                continue
            decl = TYPE_DECL.search(s) if not s.startswith(("//", "*", "/*")) else None
            if decl and type_name is None:
                type_kind, type_name = decl.groups()
                text = " ".join(a for _, a in pending)
                m = re.search(r"@RequestMapping\((?P<args>[^)]*)\)", text)
                prefix = (attr(m.group("args"), "value", "path", "") or [""])[0] if m else ""
                f = re.search(r"@FeignClient\((?P<args>[^)]*)\)", text)
                if f:
                    a = f.group("args")
                    feign = {"kind": "feign", "interface": type_name, "name": (attr(a, "name", "value", "") or [None])[0],
                             "url": (attr(a, "url") or [None])[0], "path": (attr(a, "path") or [""])[0], "ref": ref(root, name, path, i), "methods": []}
                    out["clients"].append(feign)
                x = EXCHANGE.search(text)
                if x and x.group(1) == "Http":
                    exchange_prefix = (attr(x.group("args"), "value", "url", "") or [""])[0]
                if re.search(r"@Entity\b", text):
                    t = re.search(r"@Table\((?P<args>[^)]*)\)", text)
                    table = (attr(t.group("args"), "name", "") or [None])[0] if t else None
                    out["entities"].append({"class": type_name, "table": table or re.sub(r"(?<!^)(?=[A-Z])", "_", type_name).lower(),
                                            "ref": ref(root, name, path, i)})
                r = re.search(r"interface\s+(\w+)\s+extends\s+\w*(?:Jpa|Crud|PagingAndSorting|Mongo|Reactive\w*)Repository<\s*(\w+)", s)
                if r:
                    queries = sum("@Query" in l for l in lines)
                    out["repositories"].append({"name": r.group(1), "entity": r.group(2), "queries": queries, "ref": ref(root, name, path, i)})
                pending = []
                continue
            sig = METHOD_SIG.match(line) if type_name and not s.startswith(NOT_DECL) and " = " not in s.split("(")[0] else None
            if sig:
                method = sig.group(1)
                current = method
                text = " ".join(a for _, a in pending)
                at = ref(root, name, path, pending[0][0] if pending else i)
                handler = f"{type_name}.{method}"
                for m in MAPPING.finditer(text):
                    verb, args = http_method(m.group(1), m.group("args")), m.group("args")
                    paths = attr(args, "value", "path", "") or [""]
                    for p in paths:
                        entry = {"method": verb, "path": join(prefix, p), "handler": handler, "ref": at}
                        if feign is not None:
                            entry["path"] = join(feign["path"], p)
                            entry["java_method"] = method
                            feign["methods"].append(entry)
                            client_methods.setdefault(method, []).append((feign, entry))
                        else:
                            out["endpoints"].append(entry)
                for m in EXCHANGE.finditer(text):
                    if m.group(1) == "Http":
                        continue
                    entry = {"method": m.group(1).upper(), "path": join(exchange_prefix or "", (attr(m.group("args"), "value", "url", "") or [""])[0]),
                             "java_method": method, "ref": at}
                    client = next((c for c in out["clients"] if c.get("interface") == type_name), None)
                    if client is None:
                        client = {"kind": "http-interface", "interface": type_name, "name": None, "url": None, "path": exchange_prefix or "", "ref": at, "methods": []}
                        out["clients"].append(client)
                    client["methods"].append(entry)
                    client_methods.setdefault(method, []).append((client, entry))
                for m in re.finditer(r"@KafkaListener\((?P<args>[^)]*)\)", text):
                    out["listeners"].append({"kind": "kafka", "topics": attr(m.group("args"), "topics", "topicPattern", ""), "handler": handler, "ref": at})
                for m in re.finditer(r"@(Rabbit|Sqs|Jms)Listener\((?P<args>[^)]*)\)", text):
                    out["listeners"].append({"kind": m.group(1).lower(), "topics": attr(m.group("args"), "queues", "value", "destination", ""), "handler": handler, "ref": at})
                for m in re.finditer(r"@Scheduled\((?P<args>[^)]*)\)", text):
                    out["scheduled"].append({"handler": handler, "when": m.group("args").strip(), "ref": at})
                pending = []
                continue
            if s and not s.startswith(("//", "*", "/*")):
                pending = []
            where = {"in": f"{type_name}.{current}" if type_name and current else type_name, "ref": ref(root, name, path, i)}
            if re.search(r"\.(uri|getForObject|getForEntity|postForObject|postForEntity|exchange|put|delete)\(\s*\"", s) and "RestTemplate" not in s:
                out["http_calls"].append({**where, "code": s[:160]})
            if re.search(r"\b\w*[Kk]afkaTemplate\w*\.send\(|\.send\(\s*\"[\w.-]+\"\s*,|streamBridge\.send\(", s):
                out["producers"].append({**where, "code": s[:160]})
    # Where each client method is called, and from which method: what the agent turns into a call's `from`.
    for path in sources:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        type_name, current = None, None
        for i, line in enumerate(lines, 1):
            s = line.strip()
            decl = TYPE_DECL.search(s) if not s.startswith(("//", "*", "/*")) else None
            if decl and type_name is None:
                type_name = decl.group(2)
            sig = METHOD_SIG.match(line) if not s.startswith(NOT_DECL) and " = " not in s.split("(")[0] else None
            if sig and type_name:
                current = sig.group(1)
            for m in re.finditer(r"\.(\w+)\(", s):
                for client, entry in client_methods.get(m.group(1), []):
                    if type_name != client["interface"]:
                        entry.setdefault("called_from", []).append({"in": f"{type_name}.{current}", "ref": ref(root, name, path, i)})
    return out


def scan_python(root, name):
    endpoints, prefixes = [], {}
    for path in files(root, ".py"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r"(\w+)\s*=\s*APIRouter\((?P<args>[^)]*)\)", text):
            prefixes[m.group(1)] = (attr(m.group("args"), "prefix") or [""])[0]
        lines = text.splitlines()
        for i, line in enumerate(lines, 1):
            m = re.match(r"\s*@(\w+)\.(get|post|put|patch|delete|route)\(\s*['\"]([^'\"]*)['\"](?P<rest>.*)", line)
            if not m:
                continue
            fn = next((re.match(r"\s*(?:async\s+)?def\s+(\w+)", l).group(1) for l in lines[i:i + 5] if re.match(r"\s*(?:async\s+)?def\s+\w+", l)), "?")
            verbs = [m.group(2).upper()]
            if verbs == ["ROUTE"]:
                listed = re.search(r"methods\s*=\s*\[([^\]]*)\]", m.group("rest"))
                verbs = re.findall(r"['\"](\w+)['\"]", listed.group(1)) if listed else ["GET"]
            for v in verbs:
                endpoints.append({"method": v.upper(), "path": join(prefixes.get(m.group(1), ""), m.group(3)), "handler": fn, "ref": ref(root, name, path, i)})
    return endpoints


def scan_config(root, name):
    config = []
    for path in [p for p in files(root, ".properties", ".yml", ".yaml") if p.name.startswith(("application", "bootstrap"))]:
        stack = []
        for i, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if path.suffix == ".properties":
                key, _, value = line.partition("=")
            else:
                m = re.match(r"(\s*)([\w.\-\[\]]+):\s*(.*)", line)
                if not m:
                    continue
                depth = len(m.group(1)) // 2
                stack = stack[:depth] + [m.group(2)]
                key, value = ".".join(stack), m.group(3)
            key, value = key.strip(), value.strip().strip("'\"")
            if not value or SECRET_KEY.search(key):
                continue
            if re.search(r"url|uri|host|context-path|base-path|topic|queue|application\.name|bootstrap-servers", key, re.I):
                value = re.sub(r"//[^/@\s]+@", "//", value)  # drop user:password@ from URLs
                config.append({"key": key, "value": value, "ref": ref(root, name, path, i)})
    return config


def scan_other(root, name):
    other = {"openapi": [], "workflows": [], "terraform": []}
    for p in files(root, ".yml", ".yaml", ".json"):
        rel = p.relative_to(root).as_posix()
        if re.search(r"openapi|swagger|api-docs", p.name, re.I):
            other["openapi"].append(f"{name}/{rel}")
    wf = root / ".github" / "workflows"
    if wf.is_dir():
        other["workflows"] = [f"{name}/.github/workflows/{p.name}" for p in sorted(wf.glob("*.y*ml"))]
    for p in files(root, ".tf"):
        for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            m = re.match(r'\s*(resource|module)\s+"([^"]+)"(?:\s+"([^"]+)")?', line)
            if m:
                other["terraform"].append({"kind": m.group(2), "name": m.group(3) or m.group(2), "ref": ref(root, name, p, i)})
    return other


def scan(root, name):
    try:
        commit = subprocess.run(["git", "-C", str(root), "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        commit = None
    facts = {"repo": name, "commit": commit, **scan_java(root, name)}
    facts["endpoints"] += scan_python(root, name)
    facts["config"] = scan_config(root, name)
    facts.update(scan_other(root, name))
    facts["summary"] = {k: len(v) for k, v in facts.items() if isinstance(v, list)}
    return facts


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("repo", type=pathlib.Path)
    ap.add_argument("--name")
    ap.add_argument("--out", type=pathlib.Path)
    args = ap.parse_args()
    root = args.repo.resolve()
    if not root.is_dir():
        sys.exit(f"Not a folder: {root}")
    text = json.dumps(scan(root, args.name or root.name), indent=1)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
        print(f"Wrote {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
