"""Persistent server-side workspace registry using SQLite.

Stores the full pipeline/canvas/CNL config for a workspace, keyed by a
slug derived from its name, so a device other than the one that created
it can list and reopen it after connecting to the same backend.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import aiosqlite

DB_PATH = Path(os.environ.get("NEUROCNL_DATA_DIR", Path.home() / ".neurocnl")) / "workspaces.db"


class WorkspaceStore:
    """Persistent workspace-config store using SQLite."""

    def __init__(self, db_path: Path = DB_PATH) -> None:
        self.db_path = db_path

    async def initialize(self) -> None:
        """Initialize the database schema."""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS workspace_configs (
                    slug TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    config TEXT NOT NULL,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
            await db.execute(
                "CREATE INDEX IF NOT EXISTS idx_workspace_configs_updated_at "
                "ON workspace_configs(updated_at)"
            )
            await db.commit()

    async def upsert(self, slug: str, name: str, config: dict[str, Any]) -> None:
        """Create or replace the stored config for *slug*."""
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """
                INSERT INTO workspace_configs (slug, name, config, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(slug) DO UPDATE SET
                    name = excluded.name,
                    config = excluded.config,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (slug, name, json.dumps(config)),
            )
            await db.commit()

    async def get(self, slug: str) -> dict[str, Any] | None:
        """Return the full stored record for *slug*, or None if absent."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT slug, name, config, updated_at FROM workspace_configs WHERE slug = ?",
                (slug,),
            ) as cursor:
                row = await cursor.fetchone()
                if row is None:
                    return None
                return {
                    "slug": row["slug"],
                    "name": row["name"],
                    "config": json.loads(row["config"]),
                    "updated_at": row["updated_at"],
                }

    async def list_summaries(self) -> list[dict[str, Any]]:
        """List every stored workspace's metadata, without its (possibly
        large) config blob — cheap enough for a picker list."""
        async with aiosqlite.connect(self.db_path) as db:
            db.row_factory = aiosqlite.Row
            async with db.execute(
                "SELECT slug, name, updated_at FROM workspace_configs ORDER BY updated_at DESC"
            ) as cursor:
                rows = await cursor.fetchall()
            return [
                {
                    "slug": row["slug"],
                    "name": row["name"],
                    "updated_at": row["updated_at"],
                }
                for row in rows
            ]


# Singleton shared across routers
workspace_store = WorkspaceStore()
