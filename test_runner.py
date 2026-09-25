#!/usr/bin/env python3
"""Sanity checks for bin/disparchy-run argv. No network. No real CLIs."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
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


def test_chat_request_sends_bearer():
    mod = load()
    url, body, headers = mod.chat_request("openclaw", "", "", "Hello", "sekret")
    assert url == "http://127.0.0.1:18789/v1/chat/completions"
    assert body["model"] == "openclaw/default"
    assert body["messages"] == [{"role": "user", "content": "Hello"}]
    assert headers["Authorization"] == "Bearer sekret"
    assert "sekret" not in url
    url, body, headers = mod.chat_request("hermes", "http://10.0.0.5:8642/", "custom", "Hi", "k")
    assert url == "http://10.0.0.5:8642/v1/chat/completions"
    assert body["model"] == "custom"
    assert headers["Authorization"] == "Bearer k"


FAKE_OPENCLAW = "fixture-openclaw-key"
FAKE_HERMES = "fixture-hermes-key"


def _isolated_env(folder: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["XDG_STATE_HOME"] = str(folder)
    env.pop("DISPARCHY_AUTH", None)
    return env


def test_read_bearer_requires_mode_600():
    mod = load()
    with tempfile.TemporaryDirectory() as folder:
        os.environ["XDG_STATE_HOME"] = folder
        try:
            state = Path(folder) / "omarchy" / "dkfiander.disparchy"
            state.mkdir(parents=True, mode=0o700)
            path = state / "auth.json"
            path.write_text('{"openclaw": "%s"}\n' % FAKE_OPENCLAW, encoding="utf-8")
            os.chmod(path, 0o644)
            try:
                mod.read_bearer("openclaw")
            except SystemExit as exc:
                assert "mode 600" in str(exc)
            else:
                raise AssertionError("loose auth file was accepted")
            os.chmod(path, 0o600)
            assert mod.read_bearer("openclaw") == FAKE_OPENCLAW
            assert mod.read_bearer("hermes") == ""
        finally:
            os.environ.pop("XDG_STATE_HOME", None)


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
    with tempfile.TemporaryDirectory() as folder:
        proc = subprocess.run(
            [sys.executable, str(RUNNER), "--status"],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
            env=_isolated_env(Path(folder)),
        )
    assert proc.returncode == 0, proc.stderr
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    assert len(lines) == 9, lines
    seen = set()
    for line in lines:
        cli, installed, _auth, key = line.split("\t")
        assert installed in {"installed", "missing"}, line
        assert key in {"key:saved", "key:none"}, line
        assert FAKE_OPENCLAW not in line
        seen.add(cli)
    assert seen == {
        "claude", "codex", "grok", "antigravity", "cursor",
        "openclaw", "hermes", "ollama", "lmstudio",
    }
    assert FAKE_OPENCLAW not in proc.stdout
    assert FAKE_OPENCLAW not in proc.stderr
    assert FAKE_HERMES not in proc.stdout
    assert FAKE_HERMES not in proc.stderr


def _run_set_key(folder: Path, cli: str, payload: str, umask: int | None = None):
    if umask is None:
        return subprocess.run(
            [sys.executable, str(RUNNER), "--set-key", cli],
            input=payload,
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
            env=_isolated_env(folder),
        )
    wrapper = (
        "import os, sys\n"
        "os.umask(%d)\n"
        "os.execv(sys.executable, [sys.executable, %r, '--set-key', %r])\n"
        % (umask, str(RUNNER), cli)
    )
    return subprocess.run(
        [sys.executable, "-c", wrapper],
        input=payload,
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
        env=_isolated_env(folder),
    )


def test_set_key_mode_under_umask():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        proc = _run_set_key(root, "openclaw", FAKE_OPENCLAW + "\n", umask=0o022)
        assert proc.returncode == 0, proc.stderr
        state = root / "omarchy" / "dkfiander.disparchy"
        auth = state / "auth.json"
        assert stat_mode(state) == 0o700
        assert stat_mode(auth) == 0o600
        assert FAKE_OPENCLAW not in proc.stdout
        assert FAKE_OPENCLAW not in proc.stderr


def stat_mode(path: Path) -> int:
    return path.stat().st_mode & 0o777


def test_set_key_temp_is_same_directory():
    mod = load()
    opened = []
    real_open = os.open

    def wrapped(path, flags, mode=0o777, *args, **kwargs):
        if flags & os.O_CREAT and flags & os.O_EXCL:
            opened.append(os.path.abspath(path))
        return real_open(path, flags, mode, *args, **kwargs)

    with tempfile.TemporaryDirectory() as folder:
        os.environ["XDG_STATE_HOME"] = folder
        os.open = wrapped
        try:
            mod.set_key("hermes", FAKE_HERMES + "\n")
        finally:
            os.open = real_open
            os.environ.pop("XDG_STATE_HOME", None)
        state = Path(folder) / "omarchy" / "dkfiander.disparchy"
        assert opened, "temp file was not created with O_CREAT|O_EXCL"
        assert Path(opened[0]).parent == state
        assert not list(state.glob(".auth-*.tmp"))


def test_set_key_refuses_symlink_dir():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        target = root / "real-state"
        target.mkdir()
        marker = target / "untouched.txt"
        marker.write_text("leave-me\n", encoding="utf-8")
        link_parent = root / "xdg" / "omarchy"
        link_parent.mkdir(parents=True)
        link = link_parent / "dkfiander.disparchy"
        link.symlink_to(target, target_is_directory=True)
        before = marker.read_bytes()
        proc = _run_set_key(root / "xdg", "openclaw", FAKE_OPENCLAW + "\n")
        assert proc.returncode != 0, proc.stdout
        assert marker.read_bytes() == before
        assert link.is_symlink()
        assert not (target / "auth.json").exists()


def test_set_key_refuses_symlink_file():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        state = root / "omarchy" / "dkfiander.disparchy"
        state.mkdir(parents=True, mode=0o700)
        outside = root / "outside.json"
        outside.write_text('{"hermes": "leave-hermes"}\n', encoding="utf-8")
        os.chmod(outside, 0o600)
        auth = state / "auth.json"
        auth.symlink_to(outside)
        before = outside.read_bytes()
        proc = _run_set_key(root, "openclaw", FAKE_OPENCLAW + "\n")
        assert proc.returncode != 0, proc.stdout
        assert outside.read_bytes() == before
        assert auth.is_symlink()
        assert FAKE_OPENCLAW not in outside.read_text(encoding="utf-8")


def test_set_key_stores_and_removes_within_timeout():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        saved = _run_set_key(root, "openclaw", FAKE_OPENCLAW + "\n")
        assert saved.returncode == 0, saved.stderr
        other = _run_set_key(root, "hermes", FAKE_HERMES + "\n")
        assert other.returncode == 0, other.stderr
        auth = root / "omarchy" / "dkfiander.disparchy" / "auth.json"
        text = auth.read_text(encoding="utf-8")
        assert FAKE_OPENCLAW in text and FAKE_HERMES in text
        removed = _run_set_key(root, "openclaw", "")
        assert removed.returncode == 0, removed.stderr
        after = auth.read_text(encoding="utf-8")
        assert FAKE_OPENCLAW not in after
        assert FAKE_HERMES in after
        status = subprocess.run(
            [sys.executable, str(RUNNER), "--status"],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
            env=_isolated_env(root),
        )
        assert status.returncode == 0, status.stderr
        rows = {line.split("\t")[0]: line.split("\t")[-1] for line in status.stdout.splitlines() if line.strip()}
        assert rows["openclaw"] == "key:none"
        assert rows["hermes"] == "key:saved"
        assert rows["claude"] == "key:none"
        blob = status.stdout + status.stderr
        assert FAKE_OPENCLAW not in blob
        assert FAKE_HERMES not in blob


def _loose_auth(root: Path, body: str) -> Path:
    state = root / "omarchy" / "dkfiander.disparchy"
    state.mkdir(parents=True, mode=0o700)
    auth = state / "auth.json"
    auth.write_text(body, encoding="utf-8")
    os.chmod(auth, 0o644)
    return auth


def test_set_key_repairs_loose_auth_file():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        auth = _loose_auth(root, '{"hermes": "%s"}\n' % FAKE_HERMES)
        assert stat_mode(auth) == 0o644
        proc = _run_set_key(root, "openclaw", FAKE_OPENCLAW + "\n")
        assert proc.returncode == 0, proc.stderr
        assert stat_mode(auth) == 0o600
        text = auth.read_text(encoding="utf-8")
        assert FAKE_HERMES in text
        assert FAKE_OPENCLAW in text
        assert FAKE_OPENCLAW not in proc.stdout + proc.stderr


def test_set_key_removes_from_loose_auth_file():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        auth = _loose_auth(
            root,
            '{"openclaw": "%s", "hermes": "%s"}\n' % (FAKE_OPENCLAW, FAKE_HERMES),
        )
        proc = _run_set_key(root, "openclaw", "")
        assert proc.returncode == 0, proc.stderr
        assert stat_mode(auth) == 0o600
        text = auth.read_text(encoding="utf-8")
        assert FAKE_OPENCLAW not in text
        assert FAKE_HERMES in text


def test_send_refuses_loose_auth_file():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        auth = _loose_auth(root, '{"openclaw": "%s"}\n' % FAKE_OPENCLAW)
        before = auth.read_bytes()
        prompt = root / "prompt.txt"
        prompt.write_text("hello\n", encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(RUNNER), "--cli", "openclaw", "--prompt-file", str(prompt)],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
            env=_isolated_env(root),
        )
        assert proc.returncode != 0, proc.stdout
        blob = proc.stdout + proc.stderr
        assert "mode 600" in blob
        assert FAKE_OPENCLAW not in blob
        assert auth.read_bytes() == before
        assert stat_mode(auth) == 0o644


def test_status_key_refused_when_read_would_refuse():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        auth = _loose_auth(root, '{"openclaw": "%s"}\n' % FAKE_OPENCLAW)

        def rows_of():
            proc = subprocess.run(
                [sys.executable, str(RUNNER), "--status"],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
                env=_isolated_env(root),
            )
            assert proc.returncode == 0, proc.stderr
            blob = proc.stdout + proc.stderr
            assert FAKE_OPENCLAW not in blob
            assert FAKE_HERMES not in blob
            return {
                line.split("\t")[0]: line.split("\t")[-1]
                for line in proc.stdout.splitlines()
                if line.strip()
            }

        loose = rows_of()
        assert loose["openclaw"] == "key:refused"
        assert loose["hermes"] == "key:refused"
        assert loose["claude"] == "key:none"
        os.chmod(auth, 0o600)
        assert stat_mode(auth) == 0o600
        tight = rows_of()
        assert tight["openclaw"] == "key:saved"
        assert tight["hermes"] == "key:none"
        assert tight["claude"] == "key:none"
        outside = root / "outside.json"
        outside.write_text('{"openclaw": "%s"}\n' % FAKE_OPENCLAW, encoding="utf-8")
        os.chmod(outside, 0o600)
        before = outside.read_bytes()
        auth.unlink()
        auth.symlink_to(outside)
        linked = rows_of()
        assert linked["openclaw"] == "key:refused"
        assert linked["hermes"] == "key:refused"
        assert outside.read_bytes() == before
        assert auth.is_symlink()


def test_set_key_clears_refused_status():
    replaced = "fixture-openclaw-replaced"
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        auth = _loose_auth(root, '{"openclaw": "%s"}\n' % FAKE_OPENCLAW)

        def rows_of():
            proc = subprocess.run(
                [sys.executable, str(RUNNER), "--status"],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
                env=_isolated_env(root),
            )
            assert proc.returncode == 0, proc.stderr
            blob = proc.stdout + proc.stderr
            assert FAKE_OPENCLAW not in blob
            assert FAKE_HERMES not in blob
            assert replaced not in blob
            return {
                line.split("\t")[0]: line.split("\t")[-1]
                for line in proc.stdout.splitlines()
                if line.strip()
            }

        before = rows_of()
        assert before["openclaw"] == "key:refused"
        assert before["hermes"] == "key:refused"
        proc = _run_set_key(root, "openclaw", replaced + "\n")
        assert proc.returncode == 0, proc.stderr
        written = proc.stdout + proc.stderr
        assert FAKE_OPENCLAW not in written
        assert replaced not in written
        assert stat_mode(auth) == 0o600
        stored = auth.read_text(encoding="utf-8")
        assert replaced in stored
        assert FAKE_HERMES not in stored
        after = rows_of()
        assert after["openclaw"] == "key:saved"
        assert after["hermes"] == "key:none"


def test_set_key_refuses_other_owner():
    mod = load()
    real_getuid = os.getuid
    with tempfile.TemporaryDirectory() as folder:
        os.environ["XDG_STATE_HOME"] = folder
        os.getuid = lambda: real_getuid() + 1
        try:
            root = Path(folder)
            auth = _loose_auth(root, '{"hermes": "%s"}\n' % FAKE_HERMES)
            before = auth.read_bytes()
            try:
                mod.set_key("openclaw", FAKE_OPENCLAW + "\n")
            except SystemExit as exc:
                assert "refused" in str(exc)
            else:
                raise AssertionError("other uid was accepted")
            assert auth.read_bytes() == before
            assert stat_mode(auth) == 0o644
            assert FAKE_OPENCLAW not in auth.read_text(encoding="utf-8")
        finally:
            os.getuid = real_getuid
            os.environ.pop("XDG_STATE_HOME", None)


def test_auth_file_flag_is_rejected():
    proc = subprocess.run(
        [sys.executable, str(RUNNER), "--auth-file", "unused.json"],
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert proc.returncode != 0
    assert "unrecognized arguments" in proc.stderr
    assert "--auth-file" in proc.stderr


def test_qml_does_not_touch_keys():
    banned = ("parseAuth", "secretFor", "setSecret", "serializeAuth", "copySecrets")
    for path in ROOT.glob("*.qml"):
        body = path.read_text(encoding="utf-8")
        assert "auth.json" not in body, path.name
        for name in banned:
            assert name not in body, (path.name, name)


def test_set_key_command_is_stdin_only():
    text = (ROOT / "Panel.qml").read_text(encoding="utf-8")
    match = re.search(r'command\s*=\s*\[([^\]]*"--set-key"[^\]]*)\]', text)
    assert match, "set-key command missing"
    array = match.group(1)
    assert ".text" not in array
    assert "environment" not in array
    assert "console.log" not in text[match.start(): match.end() + 200]
    for line in text.splitlines():
        if "secretEdit.text" not in line and "field.text" not in line:
            continue
        if re.search(r'(secretEdit|field)\.text\s*=\s*""', line):
            continue
        if "write(" in line:
            continue
        raise AssertionError("key text left the field: " + line.strip())


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
    test_chat_request_sends_bearer()
    test_read_bearer_requires_mode_600()
    test_discover_exits_zero()
    test_status_rows()
    test_set_key_mode_under_umask()
    test_set_key_temp_is_same_directory()
    test_set_key_refuses_symlink_dir()
    test_set_key_refuses_symlink_file()
    test_set_key_stores_and_removes_within_timeout()
    test_set_key_repairs_loose_auth_file()
    test_set_key_removes_from_loose_auth_file()
    test_send_refuses_loose_auth_file()
    test_status_key_refused_when_read_would_refuse()
    test_set_key_clears_refused_status()
    test_set_key_refuses_other_owner()
    test_auth_file_flag_is_rejected()
    test_qml_does_not_touch_keys()
    test_set_key_command_is_stdin_only()
    test_missing_args_fail()
    test_model()
    print("ok")
