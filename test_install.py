#!/usr/bin/env python3
"""Install into a temporary HOME and prove the copy, the swap, and cleanup."""
from __future__ import annotations

import hashlib
import os
import stat
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
INSTALL = ROOT / "install"
PLUGIN = "dkfiander.disparchy"
SHIPPED = (
    "manifest.json",
    "BarWidget.qml",
    "Panel.qml",
    "Model.js",
    "DisparchyIcon.qml",
    "bin/disparchy-run",
)


def snapshot(root: Path) -> list[tuple[str, int, str]]:
    rows: list[tuple[str, int, str]] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            path = Path(dirpath) / name
            rel = path.relative_to(root).as_posix()
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            rows.append((rel, stat.S_IMODE(path.stat().st_mode), digest))
    return rows


def layout(home: Path, extra: set[str]) -> None:
    omarchy = home / ".config" / "omarchy"
    plugins = omarchy / "plugins"
    names = sorted(path.name for path in plugins.iterdir())
    assert names == sorted({PLUGIN, *extra}), names
    leftover = sorted(
        path.name for path in omarchy.iterdir() if path.name.startswith(".disparchy-")
    )
    assert leftover == [], leftover


def run_install(home: Path, fail: str | None = None) -> subprocess.CompletedProcess[str]:
    env = {
        "HOME": str(home),
        "PATH": os.environ["PATH"],
        "TMPDIR": str(home),
    }
    if fail:
        env["DISPARCHY_INSTALL_FAIL"] = fail
    return subprocess.run(
        [str(INSTALL)],
        cwd=str(home),
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def make_home(root: Path) -> tuple[Path, Path, Path]:
    home = root / "home"
    plugins = home / ".config" / "omarchy" / "plugins"
    plugins.mkdir(parents=True)
    other = plugins / "other.plugin"
    other.mkdir()
    (other / "keep.txt").write_bytes(b"stay\n")
    state = home / ".local" / "state" / "omarchy" / PLUGIN
    state.mkdir(parents=True, mode=0o700)
    (state / "selection.json").write_bytes(b'{"enabled":["claude"]}\n')
    (state / "auth.json").write_bytes(b'{"k":"secret"}\n')
    os.chmod(state / "selection.json", 0o600)
    os.chmod(state / "auth.json", 0o600)
    return home, plugins / PLUGIN, state


def assert_shipped(target: Path) -> None:
    assert target.is_dir()
    assert not target.is_symlink()
    found = []
    for dirpath, dirnames, filenames in os.walk(target):
        dirnames.sort()
        for name in filenames:
            found.append((Path(dirpath) / name).relative_to(target).as_posix())
    assert sorted(found) == sorted(SHIPPED), found
    for rel in SHIPPED:
        assert (target / rel).read_bytes() == (ROOT / rel).read_bytes()
    assert os.access(target / "bin" / "disparchy-run", os.X_OK)


def test_install() -> None:
    with tempfile.TemporaryDirectory(prefix="disparchy-install.") as raw:
        home, target, state = make_home(Path(raw))
        state_before = snapshot(state)
        other_file = home / ".config" / "omarchy" / "plugins" / "other.plugin" / "keep.txt"
        other_before = other_file.read_bytes()

        linked = home / "linked-plugin"
        linked.mkdir()
        (linked / "sentinel.txt").write_bytes(b"do-not-clobber\n")
        target.symlink_to(linked)

        first = run_install(home)
        assert first.returncode == 0, first.stderr
        assert_shipped(target)
        assert (linked / "sentinel.txt").read_bytes() == b"do-not-clobber\n"
        assert snapshot(state) == state_before
        layout(home, {"other.plugin"})

        original = (target / "Panel.qml").read_bytes()
        (target / "Panel.qml").write_bytes(b"stale-panel\n")
        (target / "stray.txt").write_bytes(b"not-shipped\n")
        refreshed = run_install(home)
        assert refreshed.returncode == 0, refreshed.stderr
        assert (target / "Panel.qml").read_bytes() == original
        assert not (target / "stray.txt").exists()
        assert_shipped(target)
        assert snapshot(state) == state_before
        layout(home, {"other.plugin"})

        (target / "marker-old-install.txt").write_bytes(b"old-install-bytes\n")
        before_copy = snapshot(target)
        copied = run_install(home, fail="copy")
        assert copied.returncode != 0, copied.stdout
        assert snapshot(target) == before_copy
        assert (target / "marker-old-install.txt").read_bytes() == b"old-install-bytes\n"
        assert snapshot(state) == state_before
        layout(home, {"other.plugin"})

        before_swap = snapshot(target)
        swapped = run_install(home, fail="swap")
        assert swapped.returncode != 0, swapped.stdout
        assert snapshot(target) == before_swap, "old install restored byte-identical"
        assert (target / "marker-old-install.txt").read_bytes() == b"old-install-bytes\n"
        assert snapshot(state) == state_before
        layout(home, {"other.plugin"})
        assert other_file.read_bytes() == other_before

        # A missing target is one rename, with the same cleanup.
        os.rename(target, home / "held-aside")
        missing = run_install(home)
        assert missing.returncode == 0, missing.stderr
        assert_shipped(target)
        assert snapshot(state) == state_before
        layout(home, {"other.plugin"})


if __name__ == "__main__":
    test_install()
    print("ok")
