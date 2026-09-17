#!/usr/bin/env python3
"""Merge a legacy SQLite database without replacing canonical records."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path


def main() -> int:
    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    if not source.is_file():
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(target) as connection:
        connection.execute("ATTACH DATABASE ? AS legacy", (str(source),))
        tables = connection.execute(
            "SELECT name FROM legacy.sqlite_master WHERE type = 'table'"
        ).fetchall()
        for (table_name,) in tables:
            if table_name.startswith("sqlite_"):
                continue
            quoted = '"' + table_name.replace('"', '""') + '"'
            exists = connection.execute(
                "SELECT 1 FROM main.sqlite_master WHERE type = 'table' AND name = ?",
                (table_name,),
            ).fetchone()
            if exists:
                connection.execute(
                    f"INSERT OR IGNORE INTO main.{quoted} SELECT * FROM legacy.{quoted}"
                )
        connection.commit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
