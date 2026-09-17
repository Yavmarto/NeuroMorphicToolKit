"""SQLAlchemy engine, session, and ORM model for dataset-registry persistence."""

from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager, contextmanager
from pathlib import Path

from sqlalchemy import Engine, Integer, Text, create_engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


class Base(DeclarativeBase):
    """Base class for dataset-registry SQLAlchemy models."""


class DatasetDownloadDB(Base):
    """ORM model backing the ``dataset_downloads`` table."""

    __tablename__ = "dataset_downloads"

    dataset_id: Mapped[str] = mapped_column(Text, primary_key=True)
    local_path: Mapped[str] = mapped_column(Text, nullable=False)
    storage_path: Mapped[str] = mapped_column(Text, nullable=False)
    content_sha256: Mapped[str | None] = mapped_column(Text, nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    downloaded_at: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    job_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(Text, nullable=False, server_default="firebase")


# Columns added after the original schema shipped. Applied to databases that
# predate them; a fresh database already has them from `create_all`, and the
# duplicate-column error is the expected no-op.
_MIGRATIONS = (
    "ALTER TABLE dataset_downloads ADD COLUMN job_id TEXT",
    "ALTER TABLE dataset_downloads ADD COLUMN source TEXT NOT NULL DEFAULT 'firebase'",
)


def make_async_engine(db_path: Path) -> AsyncEngine:
    return create_async_engine(f"sqlite+aiosqlite:///{db_path}")


def make_sync_engine(db_path: Path) -> Engine:
    return create_engine(f"sqlite:///{db_path}")


async def _ensure_schema_async(engine: AsyncEngine) -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        for statement in _MIGRATIONS:
            try:
                await conn.exec_driver_sql(statement)
            except OperationalError:  # column already present
                pass


def _ensure_schema_sync(engine: Engine) -> None:
    with engine.begin() as conn:
        Base.metadata.create_all(conn)
        for statement in _MIGRATIONS:
            try:
                conn.exec_driver_sql(statement)
            except OperationalError:  # column already present
                pass


@asynccontextmanager
async def session_scope(db_path: Path) -> AsyncIterator[AsyncSession]:
    """Yield a session against a fresh, short-lived async engine, schema ensured first.

    Mirrors the original per-call ``async with aiosqlite.connect(...)`` pattern
    (a fresh connection per operation) so no background aiosqlite worker
    thread outlives a caller/test.
    """
    engine = make_async_engine(db_path)
    try:
        await _ensure_schema_async(engine)
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        async with session_factory() as session:
            yield session
    finally:
        await engine.dispose()


@asynccontextmanager
async def raw_session_scope(db_path: Path) -> AsyncIterator[AsyncSession]:
    """Like `session_scope`, but does not create/migrate the schema first.

    Used by read paths whose original implementation tolerated a missing
    table by catching the resulting "no such table" error, rather than
    creating one.
    """
    engine = make_async_engine(db_path)
    try:
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        async with session_factory() as session:
            yield session
    finally:
        await engine.dispose()


@contextmanager
def sync_session_scope(db_path: Path) -> Iterator[Session]:
    """Yield a session against a fresh, short-lived sync engine, schema ensured first."""
    engine = make_sync_engine(db_path)
    try:
        _ensure_schema_sync(engine)
        session_factory = sessionmaker(engine, expire_on_commit=False)
        with session_factory() as session:
            yield session
    finally:
        engine.dispose()
