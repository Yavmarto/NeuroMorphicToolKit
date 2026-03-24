from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        default=Path(__file__).resolve().parents[1],
        type=Path,
        help="Path to gpt5.4-dev-pipeline",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print("| Module | Existing Workflows | Missing Or Broken | Required Updates |")
    print("|---|---|---|---|")
    for config_path in sorted(args.root.glob("*/module.json")):
        module = json.loads(config_path.read_text())
        existing = ", ".join(module["existing_workflows"])
        missing = ", ".join(module["workflow_gaps"])
        required = ", ".join(module["required_updates"])
        print(f"| {module['module_name']} | {existing} | {missing} | {required} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())