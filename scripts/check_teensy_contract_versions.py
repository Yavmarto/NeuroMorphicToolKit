#!/usr/bin/env python3
"""Fail CI if mirrored Teensy contract versions diverge."""

from __future__ import annotations

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_FILES = {
    "Neurochip": ROOT / "Neurochip" / "neurochip" / "contracts" / "teensy_deployment_contract.py",
    "neurocnl": ROOT / "neurocnl" / "neurocnl" / "contracts" / "teensy_deployment_contract.py",
}
VERSION_FIELD = "CONTRACT_VERSION"


def load_contract_version(path: Path) -> str:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in tree.body:
        if not isinstance(node, ast.AnnAssign):
            continue
        if not isinstance(node.target, ast.Name) or node.target.id != VERSION_FIELD:
            continue
        value = ast.literal_eval(node.value)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{path}: {VERSION_FIELD} must be a non-empty string")
        return value
    raise ValueError(f"{path}: missing {VERSION_FIELD}")


def main() -> int:
    versions = {name: load_contract_version(path) for name, path in CONTRACT_FILES.items()}
    unique_versions = set(versions.values())
    if len(unique_versions) != 1:
        joined = ", ".join(f"{name}={version}" for name, version in versions.items())
        raise SystemExit(f"Teensy contract versions diverged: {joined}")

    version = unique_versions.pop()
    print(f"Teensy contract versions are in sync at {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
