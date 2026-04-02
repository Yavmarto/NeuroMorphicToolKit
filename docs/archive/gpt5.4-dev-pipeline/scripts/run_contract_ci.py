from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


PHASES = {
    "setup": ["setup_commands"],
    "baseline": ["setup_commands", "baseline_commands"],
    "migration": ["setup_commands", "migration_commands"],
    "all": ["setup_commands", "baseline_commands", "migration_commands"],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--phase", choices=PHASES, default="all")
    return parser.parse_args()


def run_command(command: str, cwd: Path) -> None:
    print(f"::group::{command}")
    subprocess.run(command, cwd=cwd, shell=True, executable="/bin/bash", check=True)
    print("::endgroup::")


def main() -> int:
    args = parse_args()
    config = json.loads(args.config.read_text())
    workspace_root = args.config.resolve().parents[3]

    for key in PHASES[args.phase]:
        for command in config.get(key, []):
            run_command(command, workspace_root)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
