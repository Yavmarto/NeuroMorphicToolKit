"""Snapshot tests for Neurohub adapter — config service and project service.

These tests exercise the two primary data-processing services that shape
the structured payloads sent back to Flutter: the suite configuration
round-trip and project creation/retrieval.

An in-memory SQLite session is constructed for isolation (same pattern as
Neurohub's own conftest.py).  Timestamps and UUIDs generated inside the
service layer are monkeypatched to fixed values so snapshots are stable
across runs.

PYTHONPATH must include NeuroMorphicToolKit/Neurohub so that
`neurohub.*` is importable.
"""

from __future__ import annotations

from collections.abc import Generator
from datetime import datetime, timezone
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

# ---------------------------------------------------------------------------
# In-memory database fixture
# ---------------------------------------------------------------------------

_FIXED_TS = "2024-06-01T00:00:00+00:00"
_FIXED_UUID = "00000000-0000-0000-0000-000000000001"


@pytest.fixture(scope="module")
def _neurohub_engine() -> Any:
    """One shared in-memory SQLite engine for all Neurohub snapshot tests."""
    from neurohub.db.database import Base

    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    return engine


@pytest.fixture()
def db(  # noqa: D103
    _neurohub_engine: Any,
) -> Generator[Session, None, None]:
    """Isolated session with automatic rollback after each test."""
    connection = _neurohub_engine.connect()
    transaction = connection.begin()
    TestSession = sessionmaker(bind=connection)
    session = TestSession()
    yield session
    session.close()
    transaction.rollback()
    connection.close()


# ---------------------------------------------------------------------------
# 1. Config service — no timestamps, fully deterministic
# ---------------------------------------------------------------------------


def test_get_default_config_snapshot(db: Session, snapshot: object) -> None:
    """Pin the default SuiteConfig returned when no config row exists."""
    from neurohub.app.services.config_service import get_config

    config = get_config(db)
    assert config.model_dump() == snapshot


def test_update_and_get_config_snapshot(db: Session, snapshot: object) -> None:
    """Pin the SuiteConfig after an explicit update round-trip."""
    from neurohub.app.schemas.config import SuiteConfig
    from neurohub.app.services.config_service import get_config, update_config

    new_cfg = SuiteConfig(
        neurosim_url="http://neurosim.internal:8000",
        neurochip_url="http://neurochip.internal:8002",
        neurobench_url="http://neurobench.internal:8003",
        neurosense_url="http://neurosense.internal:8004",
        neurocnl_url="http://neurocnl.internal:8000",
        shared_storage_path="/mnt/shared",
        default_project_settings={"auto_save": True, "theme": "dark"},
    )
    update_config(db, new_cfg)
    retrieved = get_config(db)
    assert retrieved.model_dump() == snapshot


# ---------------------------------------------------------------------------
# 2. Project service — timestamps and UUIDs are pinned via monkeypatching
# ---------------------------------------------------------------------------


def test_create_project_stable_fields_snapshot(
    db: Session, monkeypatch: pytest.MonkeyPatch, snapshot: object
) -> None:
    """Pin the stable fields of a created ProjectDB (name, owner, status, tags)."""
    import uuid as _uuid_mod

    from neurohub.app.services import project_service as _svc

    # Patch datetime.now so updated_at is deterministic
    fixed_dt = datetime(2024, 6, 1, 0, 0, 0, tzinfo=timezone.utc)

    class _FakeDatetime:
        @staticmethod
        def now(tz: Any = None) -> datetime:
            return fixed_dt

    monkeypatch.setattr(_svc, "datetime", _FakeDatetime)
    monkeypatch.setattr(_svc.uuid, "uuid4", lambda: _uuid_mod.UUID(_FIXED_UUID))

    from neurohub.contracts.project_contracts import Project, ProjectLinks
    from neurohub.app.services.project_service import create_project

    project = Project(
        id=_FIXED_UUID,
        name="SNN Prosthetic Study",
        description="Drop-test benchmark suite",
        owner="test-user",
        status="in_progress",
        tags=["snn", "prosthetic"],
        created_at=_FIXED_TS,
        updated_at=_FIXED_TS,
        members=[],
        links=ProjectLinks(),
        milestones=[],
    )
    db_project = create_project(db, project)

    stable = {
        "name": db_project.name,
        "description": db_project.description,
        "owner": db_project.owner,
        "status": db_project.status,
        "tags": db_project.tags,
    }
    assert stable == snapshot


def test_get_projects_empty_snapshot(db: Session, snapshot: object) -> None:
    """Pin the empty list returned when no projects exist."""
    from neurohub.app.services.project_service import get_projects

    result = get_projects(db)
    assert result == snapshot
