"""SQLAlchemy engine and ORM model for project persistence."""

from __future__ import annotations

from sqlalchemy import String, Text, create_engine
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    """Base class for project-store SQLAlchemy models."""


class ProjectDB(Base):
    """ORM model backing the ``projects`` table."""

    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    updated_at: Mapped[str] = mapped_column(String, nullable=False)
    graph: Mapped[str] = mapped_column(Text, nullable=False)
    cnl_spec: Mapped[str | None] = mapped_column(Text, nullable=True)


def create_tables_sync(db_path: str) -> None:
    """Create the ``projects`` table if missing, synchronously.

    ``ProjectStore.__init__`` must finish table creation without an event
    loop (it is constructed from plain sync code in several call sites),
    so this uses a throwaway sync engine rather than the async one used
    for the actual CRUD methods.
    """
    sync_engine = create_engine(f"sqlite:///{db_path}")
    try:
        Base.metadata.create_all(sync_engine)
    finally:
        sync_engine.dispose()


def make_async_engine(db_path: str) -> AsyncEngine:
    return create_async_engine(f"sqlite+aiosqlite:///{db_path}")
