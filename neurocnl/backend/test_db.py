import sqlite3
from pathlib import Path

db_path = Path("test.db")
if db_path.exists():
    db_path.unlink()

with sqlite3.connect(db_path) as db:
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS dataset_downloads (
            dataset_id TEXT PRIMARY KEY,
            local_path TEXT NOT NULL,
            storage_path TEXT NOT NULL,
            content_sha256 TEXT,
            size_bytes INTEGER,
            downloaded_at TEXT NOT NULL,
            status TEXT NOT NULL,
            error_message TEXT
        )
        """
    )
    db.execute(
        """
        INSERT INTO dataset_downloads (
            dataset_id, local_path, storage_path, content_sha256,
            size_bytes, downloaded_at, status, error_message
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(dataset_id) DO UPDATE SET
            local_path=excluded.local_path,
            storage_path=excluded.storage_path,
            content_sha256=excluded.content_sha256,
            size_bytes=excluded.size_bytes,
            downloaded_at=excluded.downloaded_at,
            status=excluded.status,
            error_message=excluded.error_message
        """,
        ("id", "lp", "sp", "c", 1, "d", "s", "e"),
    )
print("SUCCESS")
