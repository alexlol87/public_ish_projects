"""End-to-end tests: every case runs the real CLI against a temporary database.

Run: python3 -m unittest -v test_mem.py
"""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
MEM = os.path.join(HERE, "mem.py")
sys.path.insert(0, HERE)
import mem  # noqa: E402


def git(cwd, *args):
    subprocess.run(["git", "-C", cwd, *args], check=True, capture_output=True)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "db", "memory.db")
        self.cwd = os.path.join(self.tmp.name, "work", "myproject")  # not a git repo
        os.makedirs(self.cwd)

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, cwd=None, stdin=None, ok=True):
        env = dict(os.environ, LOCAL_MEMORY_DB=self.db)
        p = subprocess.run([sys.executable, MEM, *args], cwd=cwd or self.cwd, env=env,
                           input=stdin, capture_output=True, text=True, timeout=30)
        out = json.loads(p.stdout)  # every command, success or failure, prints JSON
        if ok is None:  # only "valid JSON, no crash" matters
            self.assertIn(p.returncode, (0, 1))
        elif ok:
            self.assertEqual(p.returncode, 0, out)
            self.assertNotIn("error", out)
        else:
            self.assertNotEqual(p.returncode, 0, out)
            self.assertIn("error", out)
        return out

    def add(self, title="Title", content="Body", scope="repo", load="always", expires="never", *extra, **kw):
        return self.run_cli("add", "--title", title, "--content", content, "--scope", scope,
                            "--load", load, "--expires", expires, *extra, **kw)["memory"]

    def sql(self, query, *params):
        con = sqlite3.connect(self.db)
        with con:
            rows = con.execute(query, params).fetchall()
        con.close()
        return rows


class TestAddGetUpdateDelete(Base):
    def test_add_returns_full_memory(self):
        m = self.add("Use tabs", "Indent with tabs in this repo", "repo", "on_demand", "30d")
        self.assertEqual(m["title"], "Use tabs")
        self.assertEqual(m["content"], "Indent with tabs in this repo")
        self.assertEqual(m["scope"], "repo")
        self.assertEqual(m["repo"], "local/myproject")
        self.assertEqual(m["load"], "on_demand")
        self.assertIsInstance(m["id"], int)
        self.assertTrue(m["created_at"].endswith("Z"))
        self.assertEqual(m["created_at"], m["updated_at"])

    def test_global_memory_has_no_repo(self):
        self.assertIsNone(self.add(scope="global")["repo"])

    def test_add_with_explicit_repo(self):
        self.assertEqual(self.add("t", "c", "repo", "always", "never", "--repo", "local/chat")["repo"], "local/chat")

    def test_add_global_with_repo_is_error(self):
        self.run_cli("add", "--title", "t", "--content", "c", "--scope", "global", "--load", "always",
                     "--expires", "never", "--repo", "x/y", ok=False)

    def test_content_from_stdin(self):
        body = 'Line one\nIt\'s "quoted" & $special\n'
        m = self.add("t", "-", stdin=body)
        self.assertEqual(m["content"], body.strip())

    def test_add_requires_every_field(self):
        self.run_cli("add", "--title", "t", "--content", "c", "--scope", "repo", "--load", "always", ok=False)
        self.run_cli("add", "--title", "t", "--content", "c", "--scope", "repo", "--expires", "never", ok=False)

    def test_add_rejects_bad_values(self):
        for args in (["--scope", "team"], ["--load", "sometimes"], ["--expires", "soon"],
                     ["--expires", "2000-01-01"], ["--expires", "0d"], ["--title", ""],
                     ["--title", "two\nlines"], ["--content", "   "]):
            base = {"--title": "t", "--content": "c", "--scope": "repo", "--load": "always", "--expires": "never"}
            base[args[0]] = args[1]
            flat = [x for kv in base.items() for x in kv]
            with self.subTest(args=args):
                self.run_cli("add", *flat, ok=False)

    def test_get(self):
        m = self.add()
        self.assertEqual(self.run_cli("get", str(m["id"]))["memory"], m)

    def test_get_missing(self):
        self.run_cli("get", "999", ok=False)

    def test_update_changes_only_given_fields(self):
        m = self.add("Old", "Old body", "repo", "always", "never")
        u = self.run_cli("update", str(m["id"]), "--content", "New body", "--load", "on_demand")["memory"]
        self.assertEqual(u["title"], "Old")
        self.assertEqual(u["content"], "New body")
        self.assertEqual(u["load"], "on_demand")
        self.assertEqual(u["created_at"], m["created_at"])
        self.assertGreaterEqual(u["updated_at"], m["updated_at"])

    def test_update_scope_moves_repo(self):
        m = self.add(scope="repo")
        self.assertIsNone(self.run_cli("update", str(m["id"]), "--scope", "global")["memory"]["repo"])
        back = self.run_cli("update", str(m["id"]), "--scope", "repo", "--repo", "a/b")["memory"]
        self.assertEqual((back["scope"], back["repo"]), ("repo", "a/b"))

    def test_update_expiry_to_never_and_back(self):
        m = self.add(expires="10d")
        self.assertIsNotNone(m["expires_at"])
        self.assertIsNone(self.run_cli("update", str(m["id"]), "--expires", "never")["memory"]["expires_at"])

    def test_update_nothing_is_error(self):
        self.run_cli("update", str(self.add()["id"]), ok=False)

    def test_update_missing(self):
        self.run_cli("update", "999", "--title", "x", ok=False)

    def test_update_keeps_search_index_in_sync(self):
        m = self.add("alpha", "bravo")
        self.run_cli("update", str(m["id"]), "--title", "charlie", "--content", "delta")
        self.assertEqual(self.run_cli("search", "alpha")["memories"], [])
        self.assertEqual(self.run_cli("search", "delta")["memories"][0]["id"], m["id"])

    def test_delete(self):
        m = self.add("gone", "zulu")
        self.assertEqual(self.run_cli("delete", str(m["id"]))["memory"]["id"], m["id"])
        self.run_cli("get", str(m["id"]), ok=False)
        self.assertEqual(self.run_cli("search", "zulu")["memories"], [])

    def test_delete_missing(self):
        self.run_cli("delete", "999", ok=False)

    def test_bad_id_and_unknown_command_are_json_errors(self):
        self.run_cli("get", "abc", ok=False)
        self.run_cli("explode", ok=False)
        self.run_cli(ok=False)


class TestExpiry(Base):
    def test_parse_formats(self):
        now = datetime(2026, 1, 31, 12, 0, tzinfo=timezone.utc)
        self.assertIsNone(mem.parse_expiry("never", now))
        self.assertEqual(mem.parse_expiry("3d", now), "2026-02-03T12:00:00Z")
        self.assertEqual(mem.parse_expiry("2w", now), "2026-02-14T12:00:00Z")
        self.assertEqual(mem.parse_expiry("1m", now), "2026-03-02T12:00:00Z")
        self.assertEqual(mem.parse_expiry("1y", now), "2027-01-31T12:00:00Z")
        # a date means "valid through that whole day"
        self.assertEqual(mem.parse_expiry("2026-02-01", now), "2026-02-02T00:00:00Z")
        self.assertEqual(mem.parse_expiry("2026-01-31", now), "2026-02-01T00:00:00Z")
        for bad in ("2026-01-30", "0d", "-1d", "3x", "", "2026-13-01"):
            with self.subTest(bad=bad), self.assertRaises(mem.UserError):
                mem.parse_expiry(bad, now)

    def test_expired_rows_are_purged_by_any_command(self):
        keep = self.add("keep", "x")
        old = self.add("old", "expired thing", "global")
        self.sql("UPDATE memories SET expires_at = '2000-01-01T00:00:00Z' WHERE id = ?", old["id"])
        self.run_cli("list")
        self.assertEqual([r[0] for r in self.sql("SELECT id FROM memories")], [keep["id"]])
        self.assertEqual(self.sql("SELECT rowid FROM memories_fts WHERE memories_fts MATCH 'expired'"), [])

    def test_expired_never_returned(self):
        old = self.add("old", "stale", "global", "always")
        self.sql("UPDATE memories SET expires_at = '2000-01-01T00:00:00Z' WHERE id = ?", old["id"])
        self.run_cli("get", str(old["id"]), ok=False)
        self.assertEqual(self.run_cli("search", "stale")["memories"], [])
        self.assertNotIn("stale", self.context())

    def context(self, cwd=None):
        stdin = json.dumps({"cwd": cwd or self.cwd, "hook_event_name": "SessionStart"})
        return self.run_cli("context", stdin=stdin)["hookSpecificOutput"]["additionalContext"]


class TestScopes(Base):
    def setUp(self):
        super().setUp()
        self.g = self.add("global rule", "shared word", "global")
        self.mine = self.add("mine", "shared word", "repo")
        self.other = self.add("other", "shared word", "repo", "always", "never", "--repo", "acme/other")

    def ids(self, out):
        return sorted(m["id"] for m in out["memories"])

    def test_list_default_is_global_plus_current_repo(self):
        self.assertEqual(self.ids(self.run_cli("list")), sorted([self.g["id"], self.mine["id"]]))

    def test_list_other_repo(self):
        self.assertEqual(self.ids(self.run_cli("list", "--repo", "acme/other")), sorted([self.g["id"], self.other["id"]]))

    def test_list_all_repos(self):
        self.assertEqual(len(self.run_cli("list", "--all-repos")["memories"]), 3)

    def test_list_filters(self):
        self.assertEqual(self.ids(self.run_cli("list", "--scope", "global")), [self.g["id"]])
        self.assertEqual(self.ids(self.run_cli("list", "--scope", "repo")), [self.mine["id"]])
        od = self.add("od", "x", "global", "on_demand")
        self.assertEqual(self.ids(self.run_cli("list", "--load", "on_demand")), [od["id"]])

    def test_list_titles_only(self):
        for m in self.run_cli("list", "--titles")["memories"]:
            self.assertNotIn("content", m)
            self.assertIn("title", m)

    def test_list_repo_and_all_repos_conflict(self):
        self.run_cli("list", "--repo", "a/b", "--all-repos", ok=False)

    def test_list_newest_first(self):
        self.run_cli("update", str(self.g["id"]), "--title", "touched")
        self.assertEqual(self.run_cli("list")["memories"][0]["id"], self.g["id"])

    def test_search_scopes(self):
        self.assertEqual(self.ids(self.run_cli("search", "shared")), sorted([self.g["id"], self.mine["id"]]))
        self.assertEqual(self.ids(self.run_cli("search", "shared", "--repo", "acme/other")),
                         sorted([self.g["id"], self.other["id"]]))
        self.assertEqual(len(self.run_cli("search", "shared", "--all-repos")["memories"]), 3)


class TestSearch(Base):
    def test_all_terms_must_match(self):
        a = self.add("deploy", "run the staging pipeline", "global")
        self.add("deploy", "production only", "global")
        self.assertEqual([m["id"] for m in self.run_cli("search", "deploy staging")["memories"]], [a["id"]])

    def test_terms_as_separate_args(self):
        a = self.add("deploy", "run the staging pipeline", "global")
        self.assertEqual([m["id"] for m in self.run_cli("search", "deploy", "staging")["memories"]], [a["id"]])

    def test_prefix_match(self):
        a = self.add("Testing", "we use pytest fixtures", "global")
        self.assertEqual([m["id"] for m in self.run_cli("search", "fixture")["memories"]], [a["id"]])

    def test_case_and_diacritics_insensitive(self):
        a = self.add("Agenți", "Configurare", "global")
        self.assertEqual([m["id"] for m in self.run_cli("search", "AGENTI configurare")["memories"]], [a["id"]])

    def test_phrase(self):
        a = self.add("x", "never push to main", "global")
        self.add("x", "push main never", "global")
        self.assertEqual([m["id"] for m in self.run_cli("search", '"push to main"')["memories"]], [a["id"]])

    def test_ranking_prefers_more_relevant(self):
        weak = self.add("misc", "python is mentioned once among many other words here", "global")
        strong = self.add("python", "python python", "global")
        self.assertEqual([m["id"] for m in self.run_cli("search", "python")["memories"]], [strong["id"], weak["id"]])

    def test_special_characters_never_crash(self):
        self.add("c++ and c#", "uses AND OR NOT NEAR operators * ^", "global")
        for q in ('"', "*", "AND", "NOT", "c++", "a:b", "(x", "--", "'", "^", "NEAR(", "-x", "\\"):
            with self.subTest(q=q):
                self.run_cli("search", q, ok=None)

    def test_operator_words_are_plain_terms(self):
        a = self.add("x", "uses AND OR NOT NEAR operators", "global")
        self.assertEqual([m["id"] for m in self.run_cli("search", "NOT")["memories"]], [a["id"]])

    def test_empty_query_is_error(self):
        self.run_cli("search", "   ", ok=False)
        self.run_cli("search", ok=False)

    def test_limit(self):
        for i in range(5):
            self.add("item %d" % i, "common", "global")
        self.assertEqual(len(self.run_cli("search", "common", "--limit", "2")["memories"]), 2)


class TestRepoKey(Base):
    def test_from_url(self):
        cases = {
            "git@github.com:landing_zone/repo_name.git": "landing_zone/repo_name",
            "https://github.com/landing_zone/repo_name.git": "landing_zone/repo_name",
            "https://github.com/landing_zone/repo_name": "landing_zone/repo_name",
            "https://github.com/landing_zone/repo_name/": "landing_zone/repo_name",
            "ssh://git@host:7999/landing_zone/repo_name.git": "landing_zone/repo_name",
            "https://dev.azure.com/org/landing_zone/_git/repo_name": "landing_zone/repo_name",
            "git@ssh.dev.azure.com:v3/org/landing_zone/repo_name": "landing_zone/repo_name",
            "https://user@gitlab.com/group/landing_zone/repo_name.git": "landing_zone/repo_name",
        }
        for url, key in cases.items():
            with self.subTest(url=url):
                self.assertEqual(mem.key_from_url(url), key)

    def test_git_repo_with_origin(self):
        git(self.cwd, "init", "-q")
        git(self.cwd, "remote", "add", "origin", "git@github.com:lz/app.git")
        sub = os.path.join(self.cwd, "src", "deep")
        os.makedirs(sub)
        self.assertEqual(mem.repo_key(sub), "lz/app")
        self.assertEqual(self.add(cwd=sub)["repo"], "lz/app")

    def test_git_repo_without_origin_uses_top_folder(self):
        git(self.cwd, "init", "-q")
        sub = os.path.join(self.cwd, "src")
        os.makedirs(sub)
        self.assertEqual(mem.repo_key(sub), "local/myproject")

    def test_plain_folder_and_no_folder(self):
        self.assertEqual(mem.repo_key(self.cwd), "local/myproject")
        self.assertEqual(mem.repo_key(None), "local/chat")
        self.assertEqual(mem.repo_key(""), "local/chat")
        self.assertEqual(mem.repo_key(os.path.join(self.tmp.name, "missing")), "local/missing")


class TestContext(Base):
    def context(self, stdin):
        out = self.run_cli("context", stdin=stdin)
        self.assertEqual(set(out), {"hookSpecificOutput"})
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "SessionStart")
        return out["hookSpecificOutput"]["additionalContext"]

    def hook_input(self, cwd):
        return json.dumps({"timestamp": "2026-10-15T10:00:00Z", "cwd": cwd, "session_id": "s",
                           "hook_event_name": "SessionStart", "source": "new"})

    def test_contents(self):
        self.add("G always", "global body", "global", "always")
        self.add("G demand", "global hidden body", "global", "on_demand")
        self.add("R always", "repo body", "repo", "always")
        self.add("R demand", "repo hidden body", "repo", "on_demand")
        self.add("Other", "other repo body", "repo", "always", "never", "--repo", "x/y")
        text = self.context(self.hook_input(self.cwd))
        self.assertIn("local/myproject", text)
        self.assertIn("mem.py", text)  # header tells the agent how to fetch on_demand memories
        for s in ("G always", "global body", "R always", "repo body", "G demand", "R demand"):
            self.assertIn(s, text)
        for s in ("global hidden body", "repo hidden body", "Other", "other repo body"):
            self.assertNotIn(s, text)

    def test_no_cwd_is_chat(self):
        self.add("chat note", "c", "repo", "always", "never", "--repo", "local/chat")
        self.assertIn("chat note", self.context(json.dumps({"hook_event_name": "SessionStart"})))

    def test_bad_stdin_still_returns_hook_json(self):
        self.add("g", "global body", "global")
        self.assertIn("global body", self.context("not json"))
        self.assertIn("global body", self.context(""))

    def test_empty_database(self):
        self.assertIn("local/myproject", self.context(self.hook_input(self.cwd)))

    def test_truncated_at_40kb_newest_first(self):
        big = "x" * 1000
        for i in range(60):
            self.add("memory %02d" % i, big, "global")
        text = self.context(self.hook_input(self.cwd))
        self.assertLessEqual(len(text.encode("utf-8")), 40 * 1024)
        self.assertIn("memory 59", text)
        self.assertNotIn("memory 00", text)
        self.assertRegex(text, r"\d+ more")

    def test_broken_database_never_breaks_session(self):
        os.makedirs(os.path.dirname(self.db))
        with open(self.db, "w") as f:
            f.write("this is not a database" * 100)
        text = self.context(self.hook_input(self.cwd))
        self.assertIn("unavailable", text)


class TestMultiRepoWorkspace(Base):
    """A workspace folder that holds several repositories: products and apps/applications."""
    def setUp(self):
        super().setUp()
        self.products = os.path.join(self.cwd, "products")
        self.apps = os.path.join(self.cwd, "apps", "applications")
        for path, url in ((self.products, "git@github.com:lz/products.git"),
                          (self.apps, "https://github.com/lz/applications")):
            os.makedirs(os.path.join(path, "src"))
            git(path, "init", "-q")
            git(path, "remote", "add", "origin", url)
        os.makedirs(os.path.join(self.cwd, "node_modules", "dep", ".git"))  # skipped
        self.add("G rule", "global body", "global")
        self.add("P rule", "products body", "repo", "always", "never", "--repo", "lz/products")
        self.add("P demand", "products hidden", "repo", "on_demand", "never", "--repo", "lz/products")
        self.add("A rule", "applications body", "repo", "always", "never", "--repo", "lz/applications")

    def hook(self, event, session="s1", **fields):
        stdin = json.dumps(dict(fields, hook_event_name=event, session_id=session, cwd=self.cwd))
        return self.run_cli("context", stdin=stdin)

    def tool(self, tool_input, session="s1", **kw):
        out = self.hook("PostToolUse", session, tool_name="read_file", tool_input=tool_input, **kw)
        return out["hookSpecificOutput"]["additionalContext"] if out else ""

    def test_session_start_lists_repositories_and_loads_only_global(self):
        text = self.hook("SessionStart")["hookSpecificOutput"]["additionalContext"]
        self.assertIn("global body", text)
        self.assertIn("products: key lz/products, 2 memories", text)
        self.assertIn(os.path.join("apps", "applications") + ": key lz/applications, 1 memories", text)
        self.assertNotIn("node_modules", text)
        for s in ("products body", "applications body", "P rule", "local/myproject"):
            self.assertNotIn(s, text)

    def test_tool_in_repo_loads_that_repo_once(self):
        self.hook("SessionStart")
        text = self.tool({"filePath": os.path.join(self.products, "src", "a.py")})
        self.assertIn("lz/products", text)
        self.assertIn("products body", text)
        self.assertIn("P demand", text)
        self.assertNotIn("products hidden", text)
        self.assertNotIn("applications body", text)
        self.assertNotIn("global body", text)  # already given at session start
        self.assertEqual(self.tool({"filePath": os.path.join(self.products, "README.md")}), "")
        self.assertIn("applications body", self.tool({"file_path": os.path.join(self.apps, "src")}))

    def test_each_session_loads_separately(self):
        path = {"filePath": os.path.join(self.products, "x")}
        self.assertIn("products body", self.tool(path, session="s1"))
        self.assertIn("products body", self.tool(path, session="s2"))
        self.assertEqual(self.tool(path, session="s1"), "")

    def test_path_forms(self):
        cases = [
            {"path": "products/src"},  # relative to cwd
            {"filePath": "file://" + os.path.join(self.products, "a%20b.py")},
            {"replacements": [{"filePath": os.path.join(self.products, "a.py"), "newString": "x"}]},
            '{"filePath": "%s"}' % os.path.join(self.products, "a.py"),  # arguments as a JSON string
        ]
        for i, tool_input in enumerate(cases):
            with self.subTest(tool_input=tool_input):
                self.assertIn("products body", self.tool(tool_input, session="p%d" % i))

    def test_one_tool_touching_two_repos(self):
        text = self.tool({"files": [os.path.join(self.products, "a"), os.path.join(self.apps, "b")]})
        self.assertIn("products body", text)
        self.assertIn("applications body", text)

    def test_repo_without_memories_still_names_its_key(self):
        empty = os.path.join(self.cwd, "empty")
        os.makedirs(empty)
        git(empty, "init", "-q")
        self.assertIn("local/empty", self.tool({"filePath": os.path.join(empty, "f")}))

    def test_nothing_to_add(self):
        for tool_input in ({"filePath": os.path.join(self.cwd, "notes.txt")},  # not in a repository
                           {"content": os.path.join(self.products, "a")},  # not a path key
                           {"command": "ls products"}, {}, "not json"):
            with self.subTest(tool_input=tool_input):
                self.assertEqual(self.tool(tool_input), "")
        self.assertEqual(self.tool({"filePath": os.path.join(self.products, "a")}, session=""), "")

    def test_broken_database_is_silent_for_tools(self):
        os.remove(self.db)
        with open(self.db, "w") as f:
            f.write("this is not a database" * 100)
        self.assertEqual(self.tool({"filePath": os.path.join(self.products, "a")}), "")

    def test_session_start_in_one_repo_counts_as_loaded(self):
        stdin = json.dumps({"hook_event_name": "SessionStart", "session_id": "s9", "cwd": self.products})
        text = self.run_cli("context", stdin=stdin)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("products body", text)
        self.assertNotIn("Repositories", text)
        self.assertEqual(self.tool({"filePath": os.path.join(self.products, "a")}, session="s9"), "")

    def test_old_session_records_are_purged(self):
        self.tool({"filePath": os.path.join(self.products, "a")})
        self.sql("UPDATE session_loads SET loaded_at = '2000-01-01T00:00:00Z'")
        self.run_cli("list")
        self.assertEqual(self.sql("SELECT count(*) FROM session_loads")[0][0], 0)

    def test_path_option(self):
        m = self.add("via path", "c", "repo", "always", "never", "--path", os.path.join(self.apps, "src"))
        self.assertEqual(m["repo"], "lz/applications")
        titles = [x["title"] for x in self.run_cli("list", "--path", self.products)["memories"]]
        self.assertEqual(sorted(titles), ["G rule", "P demand", "P rule"])
        self.assertEqual(self.run_cli("update", str(m["id"]), "--path", self.products)["memory"]["repo"], "lz/products")
        self.run_cli("list", "--path", os.path.join(self.cwd, "missing"), ok=False)
        self.run_cli("list", "--path", self.products, "--repo", "a/b", ok=False)
        self.run_cli("add", "--title", "t", "--content", "c", "--scope", "global", "--load", "always",
                     "--expires", "never", "--path", self.products, ok=False)


class TestConcurrencyAndFiles(Base):
    def test_parallel_writers(self):
        env = dict(os.environ, LOCAL_MEMORY_DB=self.db)
        self.add()  # create schema first
        script = ("import subprocess,sys\n"
                  "for i in range(25): subprocess.run([sys.executable, %r, 'add', '--title', 't', '--content', 'c',"
                  " '--scope', 'global', '--load', 'always', '--expires', 'never'], check=True, capture_output=True)" % MEM)
        procs = [subprocess.Popen([sys.executable, "-c", script], env=env, cwd=self.cwd) for _ in range(4)]
        for p in procs:
            self.assertEqual(p.wait(timeout=120), 0)
        self.assertEqual(self.sql("SELECT count(*) FROM memories")[0][0], 101)

    def test_db_folder_created_private(self):
        self.add()
        self.assertEqual(os.stat(os.path.dirname(self.db)).st_mode & 0o777, 0o700)


if __name__ == "__main__":
    unittest.main()
