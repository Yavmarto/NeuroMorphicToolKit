"""Shared output helpers for human-readable and JSON output modes."""

from __future__ import annotations

import json
import sys
from typing import Any


def print_result(data: dict[str, Any] | list[Any], json_mode: bool) -> None:
    """Print *data* as JSON when json_mode is True, otherwise pretty-print."""
    if json_mode:
        print(json.dumps(data, indent=2))
    else:
        _human(data)


def _human(data: dict[str, Any] | list[Any]) -> None:
    if isinstance(data, list):
        for item in data:
            _human(item)
    else:
        for key, value in data.items():
            print(f"  {key}: {value}")


def error_exit(data: dict[str, Any], json_mode: bool, code: int = 1) -> None:
    """Print error *data* and exit with *code*."""
    print_result(data, json_mode)
    sys.exit(code)
