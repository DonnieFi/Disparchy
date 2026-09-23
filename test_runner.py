#!/usr/bin/env python3
"""Sanity checks for bin/disparchy-run argv. No network. No real CLIs."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import subprocess
import sys
from pathlib import Path

from test_model import test_model

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
    for cli in mod.CLI_ALLOWED:
        cmd = mod.argv_for(cli, cli, "m", "hello")
        joined = " ".join(cmd)
        for flag in FORBIDDEN:
            assert flag not in cmd, (cli, cmd)
            assert flag not in joined, (cli, joined)
        assert "hello" in cmd
        assert cmd[0] == cli


def test_cursor_model_uses_long_flag():
    mod = load()
    cmd = mod.argv_for("cursor", "cursor-agent", "auto", "q")
    assert "--model" in cmd
    assert "auto" in cmd
    assert "-m" not in cmd


def test_live_model_parsers():
    mod = load()
    codex = mod.parse_codex_models(
        '{"models":[{"slug":"gpt-6-sol","display_name":"GPT-6-Sol","visibility":"public"},'
        '{"slug":"hidden-one","display_name":"Nope","visibility":"hidden"}]}'
    )
    assert codex == [("gpt-6-sol", "GPT-6-Sol")]
    grok = mod.parse_grok_models("Default model: grok-4.7\nAvailable models:\n  * grok-4.7 (default)\n  - grok-4.6\n")
    assert ("grok-4.7", "grok-4.7") in grok
    assert ("grok-4.6", "grok-4.6") in grok
    cursor = mod.parse_dash_models("auto - Auto\ngpt-5.4 - GPT-5.4\n")
    assert cursor[0] == ("auto", "Auto")
    agy = mod.parse_tab_models("Fetching available models...\ngemini-3.8-flash-high\tGemini 3.8 Flash\n")
    assert agy == [("gemini-3.8-flash-high", "Gemini 3.8 Flash")]


def test_openclaw_uses_gateway_when_asked():
    mod = load()
    cmd = mod.argv_for("openclaw", "openclaw", "sonnet", "ignored", "/tmp/prompt.txt", True)
    assert cmd == ["openclaw", "agent", "--message-file", "/tmp/prompt.txt", "--model", "sonnet"]
    assert "exec" not in cmd


def test_codex_exec_argv():
    mod = load()
    assert mod.argv_for("codex", "codex", "", "hi") == [
        "codex", "exec", "--skip-git-repo-check", "--", "hi"
    ]
    assert mod.argv_for("codex", "codex", "gpt-6-sol", "hi") == [
        "codex", "exec", "--skip-git-repo-check", "--model", "gpt-6-sol", "--", "hi"
    ]


def test_file_prompt_argv():
    mod = load()
    claw = mod.argv_for("openclaw", "openclaw", "sonnet", "ignored", "/tmp/prompt.txt")
    assert claw == ["openclaw", "agent", "exec", "--message-file", "/tmp/prompt.txt", "--model", "sonnet"]
    hermes = mod.argv_for("hermes", "hermes", "", "ignored", "/tmp/prompt.txt")
    assert hermes == ["hermes", "chat", "--oneshot", "--query-file", "/tmp/prompt.txt"]
    assert "-m" not in hermes


def test_empty_model_omits_flag():
    mod = load()
    cmd = mod.argv_for("claude", "claude", "", "q")
    assert "--model" not in cmd
    cmd = mod.argv_for("antigravity", "agy", "", "q")
    assert "--model" not in cmd
    assert cmd.index("--output-format") < cmd.index("--print")
    assert "q" in cmd


def test_discover_exits_zero():
    proc = subprocess.run(
        [sys.executable, str(RUNNER), "--discover"],
        check=False,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    found = {line.strip() for line in proc.stdout.splitlines() if line.strip()}
    assert found <= {
        "claude", "codex", "grok", "antigravity", "cursor",
        "openclaw", "hermes", "ollama", "lmstudio",
    }


def test_status_rows():
    proc = subprocess.run(
        [sys.executable, str(RUNNER), "--status"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, proc.stderr
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    assert len(lines) == 9, lines
    seen = set()
    for line in lines:
        cli, installed, _auth = line.split("\t")
        assert installed in {"installed", "missing"}, line
        seen.add(cli)
    assert seen == {
        "claude", "codex", "grok", "antigravity", "cursor",
        "openclaw", "hermes", "ollama", "lmstudio",
    }


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
    test_cursor_model_uses_long_flag()
    test_live_model_parsers()
    test_openclaw_uses_gateway_when_asked()
    test_codex_exec_argv()
    test_file_prompt_argv()
    test_empty_model_omits_flag()
    test_discover_exits_zero()
    test_status_rows()
    test_missing_args_fail()
    test_model()
    print("ok")
