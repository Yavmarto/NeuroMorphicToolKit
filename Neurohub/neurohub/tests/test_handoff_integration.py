"""Integration tests for module handoff payloads."""

import pytest
from datetime import datetime, UTC
from sqlalchemy.orm import Session

from neurohub.app.services.bundle_service import prepare_handoff_bundle
from neurohub.db.models import ProjectDB


def test_prepare_handoff_bundle(db_session: Session) -> None:
    """Test preparing a handoff bundle from a project in the database."""
    # 1. Setup: Create a project in the database
    project_id = "handoff_proj_1"
    now = datetime.now(UTC).isoformat()
    db_project = ProjectDB(
        id=project_id,
        name="Handoff Project",
        description="Testing handoff",
        created_at=now,
        updated_at=now,
        owner="user1",
        members=[],
        links={},
        tags=[],
    )
    db_session.add(db_project)
    db_session.commit()

    # 2. Execute: Prepare handoff bundle
    target = "neurosim"
    workflow_id = "wf_123"
    bundle = prepare_handoff_bundle(db_session, project_id, target, workflow_id)

    # 3. Verify: Check contract requirements
    assert bundle.target == target
    assert bundle.project_id == project_id
    assert bundle.workflow_id == workflow_id
    assert len(bundle.contents) > 0
    assert len(bundle.bundle_hash) == 64  # SHA-256 hex length

    # Verify standardized relative paths
    for path in bundle.contents:
        assert not path.startswith("/")
        assert ".." not in path
        assert project_id in path


def test_prepare_handoff_bundle_invalid_project(db_session: Session) -> None:
    """Test that preparing a handoff for a non-existent project raises ValueError."""
    with pytest.raises(ValueError, match="Project not found"):
        prepare_handoff_bundle(db_session, "non_existent", "neurosim", "wf1")


def test_prepare_handoff_bundle_invalid_target(db_session: Session) -> None:
    """Test that preparing a handoff with an invalid target raises ValidationError."""
    # Setup project
    project_id = "handoff_proj_2"
    now = datetime.now(UTC).isoformat()
    db_project = ProjectDB(
        id=project_id,
        name="Handoff Project 2",
        description="Testing handoff",
        created_at=now,
        updated_at=now,
        owner="user1",
        members=[],
        links={},
        tags=[],
    )
    db_session.add(db_project)
    db_session.commit()

    from pydantic import ValidationError

    with pytest.raises(ValidationError, match="Invalid target module"):
        prepare_handoff_bundle(db_session, project_id, "invalid_module", "wf1")
