"""Audit workflow readiness across all modules.

Reads each module.json and prints a Markdown table showing existing
workflows, known gaps, and required updates.

Usage:
    python scripts/audit_workflows.py
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit CI/CD workflow readiness across all NMTK modules.",
    )
    parser.add_argument(
        "--root",
        default=Path(__file__).resolve().parents[1],
        type=Path,
        help="Path to unified-dev-pipeline directory",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print("| Module | Framework | Existing Workflows | Missing / Broken | Required Updates |")
    print("|---|---|---|---|---|")
    for config_path in sorted(args.root.glob("*/module.json")):
        module = json.loads(config_path.read_text())
        framework = module.get("framework", "unknown")
        existing = ", ".join(module.get("existing_workflows", [])) or "—"
        missing = ", ".join(module.get("workflow_gaps", [])) or "—"
        required = ", ".join(module.get("required_updates", [])) or "—"
        print(f"| {module['module_name']} | {framework} | {existing} | {missing} | {required} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
