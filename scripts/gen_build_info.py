# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

"""Stamp the build identity into src/build_info/build_info.json.

Both fields are properties of the commit, never of the machine or the moment,
so every checkout of the same ref produces a byte-identical file.
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
INFO_PATH = REPO_ROOT / "src" / "build_info" / "build_info.json"

EMPTY = {"commit": "", "built_at": ""}


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), *args],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def build_info() -> dict[str, str]:
    epoch = int(git("show", "-s", "--format=%ct", "HEAD"))
    committed_at = datetime.fromtimestamp(epoch, timezone.utc)
    return {
        "commit": git("rev-parse", "--short", "HEAD"),
        "built_at": committed_at.strftime("%Y%m%dT%H%MZ"),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reset",
        action="store_true",
        help="write empty values, the state the file is committed in",
    )
    args = parser.parse_args()

    info = EMPTY if args.reset else build_info()
    with open(INFO_PATH, "w", encoding="utf-8", newline="\n") as file:
        file.write(json.dumps(info, indent="\t") + "\n")

    print(f"{INFO_PATH.relative_to(REPO_ROOT)}: {info['commit'] or '<empty>'} {info['built_at']}")


if __name__ == "__main__":
    main()
