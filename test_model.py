#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / "test_model.js"


def test_model() -> None:
    node = shutil.which("node")
    assert node, "node is required to load Model.js"
    proc = subprocess.run(
        [node, str(SCRIPT)],
        cwd=str(ROOT),
        check=False,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr or proc.stdout
    assert proc.stdout.strip() == "ok", proc.stdout


if __name__ == "__main__":
    test_model()
    print("ok")
