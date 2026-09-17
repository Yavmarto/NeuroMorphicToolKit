"""SQLAlchemy engine, session, and ORM models for job-registry persistence."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from sqlalchemy import Integer, String, Text, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.sql import func


class Base(DeclarativeBase):
    """Base class for job-registry SQLAlchemy models."""


class JobDB(Base):
    """ORM model backing the ``jobs`` table."""

    __tablename__ = "jobs"

    job_id: Mapped[str] = mapped_column(String, primary_key=True)
    status: Mapped[str] = mapped_column(String, nullable=False)
    result: Mapped[str | None] = mapped_column(Text, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[str] = mapped_column(String, server_default=func.current_timestamp())
    updated_at: Mapped[str] = mapped_column(String, server_default=func.current_timestamp())
    request_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    platform: Mapped[str | None] = mapped_column(Text, nullable=True)
    notebook_path: Mapped[str | None] = mapped_column(Text, nullable=True)


class JobEventDB(Base):
    """ORM model backing the ``job_events`` table."""

    __tablename__ = "job_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    job_id: Mapped[str] = mapped_column(Text, nullable=False)
    event_type: Mapped[str] = mapped_column(Text, nullable=False)
    payload: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[str] = mapped_column(String, server_default=func.current_timestamp())


def make_async_engine(db_path: Path) -> AsyncEngine:
    return create_async_engine(f"sqlite+aiosqlite:///{db_path}")


async def initialize_schema(db_path: Path) -> None:
    """Create tables/indexes and apply idempotent legacy-column migrations.

    ``request_id``/``platform``/``notebook_path`` were added to an
    already-shipped ``jobs`` table after the fact; ``create_all`` only
    creates missing *tables*, not missing *columns* on a table that
    already exists, so a pre-existing on-disk ``jobs.db`` still needs the
    explicit ``ALTER TABLE`` below to pick them up.
    """
    engine = make_async_engine(db_path)
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
            for column in ("request_id", "platform", "notebook_path"):
                try:
                    await conn.exec_driver_sql(f"ALTER TABLE jobs ADD COLUMN {column} TEXT")
                except OperationalError:
                    # Column already exists — idempotent migration, safe to ignore
                    pass
            await conn.execute(
                text("CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON jobs(created_at)")
            )
            await conn.execute(
                text("CREATE INDEX IF NOT EXISTS idx_jobs_updated_at ON jobs(updated_at)")
            )
            await conn.execute(
                text("CREATE INDEX IF NOT EXISTS idx_job_events_job_id ON job_events(job_id, id)")
            )
    finally:
        await engine.dispose()


@asynccontextmanager
async def session_scope(db_path: Path) -> AsyncIterator[AsyncSession]:
    """Yield a session against a fresh, short-lived async engine.

    Mirrors the original per-call ``async with aiosqlite.connect(...)``
    pattern (a fresh connection per operation) rather than holding one
    long-lived engine, so no background aiosqlite worker thread outlives
    a caller/test.
    """
    engine = make_async_engine(db_path)
    try:
        session_factory = async_sessionmaker(engine, expire_on_commit=False)
        async with session_factory() as session:
            yield session
    finally:
        await engine.dispose()
