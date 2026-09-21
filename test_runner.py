#!/usr/bin/env python3
"""Sanity checks for bin/disparchy-run argv. No network. No real CLIs."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNNER = ROOT / "bin" / "disparchy-run"
FORBIDDEN = (
    "--force",
    "--yolo",
    "--always-approve",
    "--dangerously-skip-permissions",
)


def load():
    loader = importlib.machinery.SourceFileLoader("disparchy_run", str(RUNNER))
    spec = importlib.util.spec_from_loader("disparchy_run", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def test_argv_is_frozen():
    mod = load()
    for cli in mod.ALLOWED:
        cmd = mod.argv_for(cli, cli, "m", "hello")
        joined = " ".join(cmd)
        for flag in FORBIDDEN:
            assert flag not in cmd, (cli, cmd)
            assert flag not in joined, (cli, joined)
        assert "hello" in cmd
        assert cmd[0] == cli


def test_empty_model_omits_flag():
    mod = load()
    cmd = mod.argv_for("claude", "claude", "", "q")
    assert "--model" not in cmd
    cmd = mod.argv_for("gemini", "gemini", "", "q")
    assert "-m" not in cmd


def test_discover_exits_zero():
    proc = subprocess.run(
        [sys.executable, str(RUNNER), "--discover"],
        check=False,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    found = {line.strip() for line in proc.stdout.splitlines() if line.strip()}
    assert found <= {"claude", "codex", "grok", "gemini", "cursor"}


def test_missing_args_fail():
    proc = subprocess.run(
        [sys.executable, str(RUNNER)],
        check=False,
        capture_output=True,
        text=True,
    )
    assert proc.returncode != 0


if __name__ == "__main__":
    test_argv_is_frozen()
    test_empty_model_omits_flag()
    test_discover_exits_zero()
    test_missing_args_fail()
    print("ok")
