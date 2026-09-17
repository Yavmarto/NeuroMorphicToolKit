"""Tests for Pydantic contract invariants in NeuroHub."""

import pytest
from pydantic import ValidationError

from neurohub.contracts.bundle_contracts import BundleFormat, ExportBundle
from neurohub.contracts.project_contracts import Project
from neurohub.contracts.workflow_contracts import WorkflowStep, WorkflowTemplate


def test_project_requires_non_empty_name() -> None:
    """Project name must not be blank."""
    with pytest.raises(ValidationError, match="Project name cannot be empty"):
        Project(
            id="p1",
            name="   ",
            description="A test project",
            created_at="2026-01-01T00:00:00Z",
            updated_at="2026-01-01T00:00:00Z",
            owner="user1",
            members=[],
            tags=[],
        )


def test_workflow_isolated_step() -> None:
    """Test that a workflow cannot have isolated steps."""
    step1 = WorkflowStep(
        id="step1",
        name="Step 1",
        app="neurosim",
        endpoint="/api/v1/run",
        method="POST",
        parameters={},
        success_criteria="status == 200",
        on_failure="halt",
    )
    step2 = WorkflowStep(
        id="step2",
        name="Step 2",
        app="neurochip",
        endpoint="/api/v1/deploy",
        method="POST",
        parameters={},
        success_criteria="status == 200",
        on_failure="halt",
    )

    # step1 and step2 are isolated from each other
    with pytest.raises(ValidationError, match="is isolated"):
        WorkflowTemplate(
            id="w1",
            name="Isolated Workflow",
            description="Should fail",
            steps=[step1, step2],
            builtin=False,
        )


def test_bundle_empty_contents() -> None:
    """Test that an export bundle must have contents."""
    with pytest.raises(ValidationError, match="Export bundle must contain at least one file"):
        ExportBundle(format=BundleFormat.ZIP, contents=[], checksum="a" * 64)


def test_bundle_invalid_checksum() -> None:
    """Test that an export bundle must have a valid SHA-256 checksum."""
    with pytest.raises(ValidationError, match="Bundle hash must be a valid SHA-256 hex string"):
        ExportBundle(format=BundleFormat.ZIP, contents=["file1.txt"], checksum="not-a-hash")
