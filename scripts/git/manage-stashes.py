#!/usr/bin/env python3
"""CLI wrapper pointing to manage_stashes.py."""

from pathlib import Path
import runpy

target = Path(__file__).parent / "manage_stashes.py"
runpy.run_path(str(target), run_name="__main__")
