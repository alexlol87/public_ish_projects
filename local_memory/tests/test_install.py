"""Tests for install.py and install.sh. Run from the repo root: python3 -I -m unittest discover local_memory/tests"""
import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import install  # noqa: E402

# An awkward Copilot home: apostrophe, hash, ampersand, backslash-free but with spaces.
AWKWARD = "Jane's #1 & co"


class InstallTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.home = self.tmp / AWKWARD / "copilot"
        self.env = {**os.environ, "COPILOT_HOME": str(self.home)}
        self.mem = self.home / "local-memory" / "mem.py"

    def run_installer(self, *args, script="install.py"):
        cmd = ["bash", str(HERE / "install.sh"), *args] if script == "install.sh" \
            else [sys.executable, "-I", str(HERE / "install.py"), *args]
        return subprocess.run(cmd, env=self.env, capture_output=True, text=True, check=True)

    def hook_commands(self, shell):
        config = json.loads((self.home / "hooks" / "local-memory.json").read_text(encoding="utf-8"))
        return [entry[shell] for entries in config["hooks"].values() for entry in entries]


class InstallTests(InstallTestCase):
    def test_install_writes_everything_under_copilot_home(self):
        self.run_installer()
        self.assertTrue(self.mem.is_file())
        for skill in ("alx-remember", "alx-reflect"):
            self.assertTrue((self.home / "skills" / skill / "SKILL.md").is_file())
        self.assertTrue((self.home / "hooks" / "local-memory.json").is_file())
        self.assertTrue((self.home / "instructions" / "local-memory.instructions.md").is_file())

    def test_bash_hooks_run_the_interpreter_and_mem_path_exactly(self):
        self.run_installer()
        commands = self.hook_commands("bash")
        self.assertEqual(len(commands), 4)
        for cmd in commands:
            words = shlex.split(cmd)
            self.assertEqual(words[:2], [sys.executable, str(self.mem)])
            self.assertNotIn("__CMD__", cmd)
        # The awkward path survives a real shell run.
        result = subprocess.run(commands[0], shell=True, executable="/bin/bash", env=self.env,
                                input="", capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_powershell_hooks_quote_apostrophes_and_use_call_operator(self):
        self.run_installer()
        for cmd in self.hook_commands("powershell"):
            self.assertTrue(cmd.startswith("& '"), cmd)
            self.assertIn("Jane''s #1 & co", cmd)
            self.assertNotIn("__CMD__", cmd)

    def test_skills_use_the_real_path_and_no_placeholder_or_bare_python(self):
        self.run_installer()
        text = (self.home / "skills" / "alx-remember" / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn(shlex.quote(str(self.mem)) + " recall", text)
        self.assertNotIn("__CMD__", text)

    def test_no_hooks_removes_the_hooks_file(self):
        self.run_installer()
        self.assertTrue((self.home / "hooks" / "local-memory.json").exists())
        self.run_installer("--no-hooks")
        self.assertFalse((self.home / "hooks" / "local-memory.json").exists())

    def test_uninstall_keeps_saved_memory(self):
        self.run_installer()
        saved = self.home / "local-memory" / "user.md"
        saved.write_text("- keep me\n", encoding="utf-8")
        self.run_installer("--uninstall")
        self.assertFalse(self.mem.exists())
        self.assertFalse((self.home / "hooks" / "local-memory.json").exists())
        self.assertFalse((self.home / "skills" / "alx-remember").exists())
        self.assertEqual(saved.read_text(encoding="utf-8"), "- keep me\n")

    def test_disable_and_enable_round_trip(self):
        self.run_installer()
        hooks = self.home / "hooks" / "local-memory.json"
        instr = self.home / "instructions" / "local-memory.instructions.md"
        skill = self.home / "skills" / "alx-remember" / "SKILL.md"
        before = hooks.read_text(encoding="utf-8")
        run = lambda cmd: subprocess.run([sys.executable, "-I", str(self.mem), cmd], env=self.env,
                                         capture_output=True, text=True, check=True)
        run("disable")
        self.assertFalse(hooks.exists())
        self.assertFalse(instr.exists())
        self.assertIn("disable-model-invocation: true", skill.read_text(encoding="utf-8"))
        run("sync")  # must not bring the instructions file back while paused
        self.assertFalse(instr.exists())
        run("enable")
        self.assertEqual(hooks.read_text(encoding="utf-8"), before)
        self.assertTrue(instr.exists())
        self.assertIn("disable-model-invocation: false", skill.read_text(encoding="utf-8"))
        self.assertIn("disable-model-invocation: true",
                      (self.home / "skills" / "alx-disable-memory" / "SKILL.md").read_text(encoding="utf-8"))

    def test_install_sh_wrapper_delegates_to_install_py(self):
        self.run_installer(script="install.sh")
        self.assertTrue(self.mem.is_file())


class QuotingTests(unittest.TestCase):
    def test_ps_quote_doubles_every_powershell_quote_character(self):
        self.assertEqual(install.ps_quote("a'b\u2019c"), "'a''b\u2019\u2019c'")

    def test_command_prefix_per_shell(self):
        self.assertEqual(install.command_prefix("bash", "/usr/bin/python3", "/h/mem.py"), "/usr/bin/python3 /h/mem.py")
        self.assertEqual(install.command_prefix("bash", "/p/py", "/x y/mem.py"), "/p/py '/x y/mem.py'")
        self.assertEqual(install.command_prefix("powershell", "C:\\Py\\python.exe", "C:\\it's\\mem.py"),
                         "& 'C:\\Py\\python.exe' 'C:\\it''s\\mem.py'")


if __name__ == "__main__":
    unittest.main()
