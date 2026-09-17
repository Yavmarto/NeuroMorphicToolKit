"""Service for persisting projects, backed by a typed SQLAlchemy repository."""

import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import ClassVar

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from ...contracts.design_contracts import CanvasGraph, Project, ProjectSummary
from .project_db import ProjectDB, create_tables_sync, make_async_engine


class ProjectStore:
    """SQLAlchemy-backed project store using an async SQLite engine.

    Scope: a single SQLite file at ``db_path`` (default: ``projects.db`` in the
    current working directory). SQLite provides process-safe file locking, but
    projects are global to the database and are not namespaced by user or session.
    """

    _default_store: ClassVar["ProjectStore | None"] = None

    def __init__(self, db_path: str | None = None) -> None:
        """Initialize the project store.

        Args:
            db_path (str): Path to the SQLite database file.
        """
        self.db_path = db_path or _default_project_db_path()
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        """Create the projects table synchronously at construction time."""
        create_tables_sync(self.db_path)

    @asynccontextmanager
    async def _session(self) -> AsyncIterator[AsyncSession]:
        """Yield a session against a fresh, short-lived async engine.

        The original implementation opened and closed a fresh
        ``aiosqlite`` connection per call rather than holding one open for
        the store's lifetime; mirroring that here (instead of caching one
        long-lived ``AsyncEngine``) avoids leaving a background aiosqlite
        worker thread running past a test's teardown.
        """
        engine = make_async_engine(self.db_path)
        try:
            session_factory = async_sessionmaker(engine, expire_on_commit=False)
            async with session_factory() as session:
                yield session
        finally:
            await engine.dispose()

    @classmethod
    async def initialize(cls, db_path: str | None = None) -> "ProjectStore":
        """Initialize and cache the shared project store for the app lifespan.

        Args:
            db_path (str): Path to the SQLite database file.

        Returns:
            ProjectStore: The shared project store instance.
        """
        resolved_path = db_path or _default_project_db_path()
        if cls._default_store is None or cls._default_store.db_path != resolved_path:
            cls._default_store = cls(resolved_path)
        else:
            cls._default_store._init_db()
        return cls._default_store

    @classmethod
    def get_default(cls) -> "ProjectStore":
        """Return the shared project store, creating it lazily if needed.

        Returns:
            ProjectStore: The shared project store instance.
        """
        if cls._default_store is None:
            cls._default_store = cls()
        return cls._default_store

    @classmethod
    async def close(cls) -> None:
        """Release the shared project store reference at shutdown."""
        cls._default_store = None

    async def save_project(self, project: Project) -> None:
        """Save or update a project.

        Args:
            project (Project): The project to save.
        """
        async with self._session() as session:
            await session.merge(
                ProjectDB(
                    id=project.id,
                    name=project.name,
                    description=project.description,
                    updated_at=project.updated_at,
                    graph=project.graph.model_dump_json(),
                    cnl_spec=project.cnl_spec,
                )
            )
            await session.commit()

    async def get_project(self, project_id: str) -> Project | None:
        """Retrieve a project by its ID.

        Args:
            project_id (str): The ID of the project to retrieve.

        Returns:
            Project | None: The project if found, None otherwise.
        """
        async with self._session() as session:
            row = await session.get(ProjectDB, project_id)
            if row is None:
                return None
            # description/cnl_spec are nullable at the storage layer (a
            # pre-existing looseness carried over unchanged from the raw
            # sqlite3 implementation); Project/ProjectSummary declare them
            # as plain `str`, so a NULL row would already have failed
            # Pydantic validation before this migration too.
            return Project(
                id=row.id,
                name=row.name,
                description=row.description,
                updated_at=row.updated_at,
                graph=CanvasGraph.model_validate_json(row.graph),
                cnl_spec=row.cnl_spec,
            )

    async def list_projects(
        self, skip: int = 0, limit: int = 50
    ) -> list[ProjectSummary]:
        """List all projects with pagination.

        Args:
            skip (int): Number of projects to skip.
            limit (int): Maximum number of projects to return.

        Returns:
            list[ProjectSummary]: A list of project summaries.
        """
        async with self._session() as session:
            stmt = (
                select(ProjectDB)
                .order_by(ProjectDB.updated_at.desc())
                .limit(limit)
                .offset(skip)
            )
            rows = (await session.execute(stmt)).scalars().all()
            return [
                ProjectSummary(
                    id=row.id,
                    name=row.name,
                    description=row.description,
                    updated_at=row.updated_at,
                )
                for row in rows
            ]

    async def delete_project(self, project_id: str) -> bool:
        """Delete a project.

        Args:
            project_id (str): The ID of the project to delete.

        Returns:
            bool: True if a project was deleted, False otherwise.
        """
        async with self._session() as session:
            result = await session.execute(
                delete(ProjectDB).where(ProjectDB.id == project_id)
            )
            await session.commit()
            return (result.rowcount or 0) > 0  # type: ignore[attr-defined]

    async def ping(self) -> bool:
        """Run a lightweight health check against the backing SQLite database.

        Returns:
            bool: True if the database is reachable.
        """
        async with self._session() as session:
            await session.execute(select(1))
        return True


def _default_project_db_path() -> str:
    explicit = os.environ.get("NEUROSIM_PROJECT_DB", "").strip()
    if explicit:
        return explicit
    data_dir = os.environ.get("NEUROCNL_DATA_DIR", "").strip()
    return (
        str(Path(data_dir) / "neurosim" / "projects.db") if data_dir else "projects.db"
    )
