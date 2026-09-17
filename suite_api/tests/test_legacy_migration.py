"""Upgrade migration preserves canonical rows and is retry-safe."""

from __future__ import annotations

import sqlite3
import subprocess
import sys
from pathlib import Path

MIGRATOR = (
    Path(__file__).resolve().parents[2]
    / "nmtk"
    / "neuro_toolkit"
    / "assets"
    / "deployment"
    / "migrate_legacy.py"
)


def _database(path: Path, rows: list[tuple[str, str]]) -> None:
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE records (id TEXT PRIMARY KEY, value TEXT)")
        connection.executemany("INSERT INTO records VALUES (?, ?)", rows)


def test_migration_is_idempotent_and_preserves_canonical_conflicts(
    tmp_path: Path,
) -> None:
    source = tmp_path / "legacy.db"
    target = tmp_path / "canonical.db"
    _database(source, [("shared", "legacy"), ("legacy-only", "imported")])
    _database(target, [("shared", "canonical")])

    for _attempt in range(2):
        subprocess.run(
            [sys.executable, str(MIGRATOR), str(source), str(target)],
            check=True,
        )

    with sqlite3.connect(target) as connection:
        rows = connection.execute(
            "SELECT id, value FROM records ORDER BY id"
        ).fetchall()
    assert rows == [("legacy-only", "imported"), ("shared", "canonical")]
