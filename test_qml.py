#!/usr/bin/env python3
"""Compile every plugin QML file with qmltestrunner.

Qt rejects a method whose name is a JavaScript global. `function escape()`
is one of those names, so this script fails while that method exists.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IMPORTS = ROOT / "tests" / "qmlimports"
RUNNER = Path("/usr/lib/qt6/bin/qmltestrunner")
FILES = ["Panel.qml", "BarWidget.qml", "DisparchyIcon.qml"]


def compile_file(path: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.setdefault("XDG_RUNTIME_DIR", "/tmp/runtime-ubuntu")
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["QT_QUICK_CONTROLS_STYLE"] = "Basic"
    return subprocess.run(
        [str(RUNNER), "-import", str(IMPORTS), "-input", str(path)],
        cwd=str(ROOT),
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def errors_of(output: str) -> list[str]:
    diagnostics = []
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("/") and ": " in stripped and "produced " not in stripped:
            diagnostics.append(stripped)
    return diagnostics


def main() -> int:
    runner = shutil.which(str(RUNNER)) or (str(RUNNER) if RUNNER.is_file() else "")
    if not runner:
        print("qmltestrunner is required", file=sys.stderr)
        return 1
    failed = False
    for name in FILES:
        path = ROOT / name
        proc = compile_file(path)
        output = (proc.stdout or "") + (proc.stderr or "")
        diagnostics = errors_of(output)
        print(f"--- {name} exit {proc.returncode} ---")
        if diagnostics:
            print("\n".join(diagnostics))
        else:
            print("compiled")
        if "Illegal method name" in output:
            print(f"FAIL {name}: Illegal method name")
            failed = True
            continue
        if proc.returncode != 0 or diagnostics:
            print(f"FAIL {name}")
            failed = True
    if failed:
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
