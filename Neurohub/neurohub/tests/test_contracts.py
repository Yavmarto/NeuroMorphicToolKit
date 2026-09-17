"""Tests for NeuroHub Pydantic contracts."""

from typing import cast

import pytest
from pydantic import ValidationError

from neurohub.contracts.bundle_contracts import BundleFormat, ExportBundle, SharedAsset
from neurohub.contracts.project_contracts import ProjectConfig
from neurohub.contracts.workflow_contracts import (
    ContractWorkflowStep,
    WorkflowDefinition,
    WorkflowStep,
    WorkflowTemplate,
)


class TestProjectConfig:
    """Tests for the ProjectConfig contract."""

    def test_valid_project_config(self) -> None:
        """Test with valid data."""
        config = ProjectConfig(
            name="Test Project", owner="Alice", module_list=["neurosim", "neurochip"]
        )
        assert config.name == "Test Project"
        assert config.owner == "Alice"
        assert config.module_list == ["neurosim", "neurochip"]

    def test_empty_name(self) -> None:
        """Test that empty name raises ValidationError."""
        with pytest.raises(ValidationError, match="Project name cannot be empty"):
            ProjectConfig(name=" ", owner="Alice", module_list=["neurosim"])

    def test_empty_owner(self) -> None:
        """Test that empty owner raises ValidationError."""
        with pytest.raises(ValidationError, match="Project owner cannot be empty"):
            ProjectConfig(name="Test", owner="", module_list=["neurosim"])

    def test_invalid_module(self) -> None:
        """Test that invalid module raises ValidationError."""
        with pytest.raises(ValidationError, match="Invalid module reference: invalid_app"):
            ProjectConfig(name="Test", owner="Alice", module_list=["neurosim", "invalid_app"])


class TestWorkflowDefinition:
    """Tests for the WorkflowDefinition contract."""

    def test_valid_workflow(self) -> None:
        """Test with valid DAG and references."""
        step1 = ContractWorkflowStep(id="step1")
        step2 = ContractWorkflowStep(id="step2", depends_on=["step1"])
        workflow = WorkflowDefinition(steps=[step1, step2], execution_order=["step1", "step2"])
        assert len(workflow.steps) == 2
        assert workflow.execution_order == ["step1", "step2"]

    def test_missing_step_reference_in_order(self) -> None:
        """Test that missing step reference in execution_order raises ValidationError."""
        step1 = ContractWorkflowStep(id="step1")
        msg = "Execution order step reference not found: step2"
        with pytest.raises(ValidationError, match=msg):
            WorkflowDefinition(steps=[step1], execution_order=["step1", "step2"])

    def test_missing_dependency_reference(self) -> None:
        """Test that missing dependency reference raises ValidationError."""
        step1 = ContractWorkflowStep(id="step1", depends_on=["missing_step"])
        msg = "Dependency step reference not found: missing_step"
        with pytest.raises(ValidationError, match=msg):
            WorkflowDefinition(steps=[step1], execution_order=["step1"])

    def test_cyclic_workflow(self) -> None:
        """Test that cyclic graph raises ValidationError."""
        step1 = ContractWorkflowStep(id="step1", depends_on=["step2"])
        step2 = ContractWorkflowStep(id="step2", depends_on=["step1"])
        with pytest.raises(ValidationError, match="Workflow graph contains cycles"):
            WorkflowDefinition(steps=[step1, step2], execution_order=["step1", "step2"])

    def test_self_cycle(self) -> None:
        """Test that self-referencing step raises ValidationError."""
        step1 = ContractWorkflowStep(id="step1", depends_on=["step1"])
        with pytest.raises(ValidationError, match="Workflow graph contains cycles"):
            WorkflowDefinition(steps=[step1], execution_order=["step1"])


class TestWorkflowTemplate:
    """Tests for the WorkflowTemplate contract."""

    def _make_step(self, step_id: str, depends_on: list[str] | None = None) -> WorkflowStep:
        return WorkflowStep(
            id=step_id,
            name=f"Step {step_id}",
            app="neurosim",
            endpoint="/test",
            method="GET",
            parameters={},
            success_criteria="ok",
            on_failure="halt",
            depends_on=depends_on or [],
        )

    def test_valid_dag(self) -> None:
        """Test with a valid DAG."""
        s1 = self._make_step("s1")
        s2 = self._make_step("s2", depends_on=["s1"])
        template = WorkflowTemplate(
            id="wf1",
            name="Valid WF",
            description="Test",
            steps=[s1, s2],
            builtin=False,
        )
        assert len(template.steps) == 2

    def test_self_cycle(self) -> None:
        """Test that a self-cycle raises ValidationError."""
        s1 = self._make_step("s1", depends_on=["s1"])
        with pytest.raises(ValidationError, match="contains cycles"):
            WorkflowTemplate(
                id="wf1", name="Invalid", description="Test", steps=[s1], builtin=False
            )

    def test_simple_cycle(self) -> None:
        """Test that a simple 2-step cycle raises ValidationError."""
        s1 = self._make_step("s1", depends_on=["s2"])
        s2 = self._make_step("s2", depends_on=["s1"])
        with pytest.raises(ValidationError, match="contains cycles"):
            WorkflowTemplate(
                id="wf1", name="Invalid", description="Test", steps=[s1, s2], builtin=False
            )

    def test_deep_cycle(self) -> None:
        """Test that a deeper cycle raises ValidationError."""
        s1 = self._make_step("s1", depends_on=["s3"])
        s2 = self._make_step("s2", depends_on=["s1"])
        s3 = self._make_step("s3", depends_on=["s2"])
        with pytest.raises(ValidationError, match="contains cycles"):
            WorkflowTemplate(
                id="wf1", name="Invalid", description="Test", steps=[s1, s2, s3], builtin=False
            )

    def test_missing_dependency(self) -> None:
        """Test that a missing dependency reference raises ValidationError."""
        s1 = self._make_step("s1", depends_on=["missing"])
        with pytest.raises(ValidationError, match="Dependency step reference not found"):
            WorkflowTemplate(
                id="wf1", name="Invalid", description="Test", steps=[s1], builtin=False
            )

    def test_isolated_step(self) -> None:
        """Test that an isolated step raises ValidationError in multi-step workflow."""
        s1 = self._make_step("s1")
        s2 = self._make_step("s2")
        with pytest.raises(ValidationError, match="is isolated"):
            WorkflowTemplate(
                id="wf1", name="Invalid", description="Test", steps=[s1, s2], builtin=False
            )

    def test_single_step_is_not_isolated(self) -> None:
        """Test that a single-step workflow is valid."""
        s1 = self._make_step("s1")
        template = WorkflowTemplate(
            id="wf1", name="Valid", description="Test", steps=[s1], builtin=False
        )
        assert len(template.steps) == 1


class TestExportBundle:
    """Tests for the ExportBundle contract."""

    VALID_HASH = "a" * 64

    def test_valid_bundle(self) -> None:
        """Test with valid data."""
        bundle = ExportBundle(
            format=BundleFormat.ZIP,
            contents=["projects/p1/file1.txt", "projects/p1/file2.txt"],
            bundle_hash=self.VALID_HASH,
            target="neurosim",
            project_id="p1",
            workflow_id="w1",
        )
        assert bundle.format == BundleFormat.ZIP
        assert bundle.bundle_hash == self.VALID_HASH
        assert bundle.target == "neurosim"
        assert bundle.project_id == "p1"

    def test_workspace_asset_type_is_supported(self) -> None:
        """Test that the studio_workspace asset type is accepted."""
        asset = SharedAsset(
            id="asset-1",
            name="Workspace",
            description="Workspace file",
            type="studio_workspace",
            version=1,
            author="alice",
            tags=[],
            created_at="2026-06-09T00:00:00Z",
            file_path="shared_assets/workspace.json",
            file_size_bytes=1,
            sha256=self.VALID_HASH,
            metadata={},
        )

        assert asset.type == "studio_workspace"

    def test_invalid_hash_format(self) -> None:
        """Test that invalid SHA-256 format raises ValidationError."""
        with pytest.raises(ValidationError, match="Bundle hash must be a valid SHA-256 hex string"):
            ExportBundle(
                format=BundleFormat.TAR,
                contents=["f1.txt"],
                bundle_hash="too_short",
                target="neurosim",
                project_id="p1",
                workflow_id="w1",
            )

    def test_invalid_hash_chars(self) -> None:
        """Test that non-hex characters in hash raise ValidationError."""
        with pytest.raises(ValidationError, match="Bundle hash must be a valid SHA-256 hex string"):
            ExportBundle(
                format=BundleFormat.TAR,
                contents=["f1.txt"],
                bundle_hash="z" * 64,
                target="neurosim",
                project_id="p1",
                workflow_id="w1",
            )

    def test_invalid_format_enum(self) -> None:
        """Test that invalid format raises ValidationError."""
        with pytest.raises(ValidationError):
            ExportBundle(
                format=cast(BundleFormat, "INVALID"),
                contents=["f1.txt"],
                bundle_hash=self.VALID_HASH,
                target="neurosim",
                project_id="p1",
                workflow_id="w1",
            )

    def test_empty_contents(self) -> None:
        """Test that empty contents list raises ValidationError."""
        with pytest.raises(ValidationError, match="Export bundle must contain at least one file"):
            ExportBundle(
                format=BundleFormat.ZIP,
                contents=[],
                bundle_hash=self.VALID_HASH,
                target="neurosim",
                project_id="p1",
                workflow_id="w1",
            )

    def test_absolute_path_in_contents(self) -> None:
        """Test that absolute paths in contents raise ValidationError."""
        with pytest.raises(ValidationError, match="must be a relative path"):
            ExportBundle(
                format=BundleFormat.ZIP,
                contents=["/absolute/path.txt"],
                bundle_hash=self.VALID_HASH,
                target="neurosim",
                project_id="p1",
                workflow_id="w1",
            )

    def test_traversal_in_contents(self) -> None:
        """Test that directory traversal in contents raises ValidationError."""
        with pytest.raises(ValidationError, match="cannot contain directory traversal"):
            ExportBundle(
                format=BundleFormat.ZIP,
                contents=["../traversal.txt"],
                bundle_hash=self.VALID_HASH,
                target="neurosim",
                project_id="p1",
                workflow_id="w1",
            )

    def test_invalid_target(self) -> None:
        """Test that invalid target module raises ValidationError."""
        with pytest.raises(ValidationError, match="Invalid target module"):
            ExportBundle(
                format=BundleFormat.ZIP,
                contents=["f1.txt"],
                bundle_hash=self.VALID_HASH,
                target="invalid_module",
                project_id="p1",
                workflow_id="w1",
            )


class TestSharedAsset:
    """Tests for the SharedAsset contract."""

    def test_valid_shared_asset(self) -> None:
        """Test with valid data."""
        asset = SharedAsset(
            id="a1",
            name="Asset 1",
            description="Desc",
            type="nir",
            version=1,
            author="Alice",
            tags=[],
            created_at="2023-01-01T00:00:00Z",
            file_path="models/m1.nir",
            file_size_bytes=1024,
            sha256="a" * 64,
            metadata={},
        )
        assert asset.file_path == "models/m1.nir"

    def test_absolute_file_path(self) -> None:
        """Test that absolute file_path raises ValidationError."""
        with pytest.raises(ValidationError, match="Asset file_path must be a relative path"):
            SharedAsset(
                id="a1",
                name="A",
                description="D",
                type="nir",
                version=1,
                author="A",
                tags=[],
                created_at="T",
                file_path="/absolute/path",
                file_size_bytes=0,
                sha256="a" * 64,
                metadata={},
            )

    def test_traversal_file_path(self) -> None:
        """Test that traversal in file_path raises ValidationError."""
        with pytest.raises(ValidationError, match="cannot contain directory traversal"):
            SharedAsset(
                id="a1",
                name="A",
                description="D",
                type="nir",
                version=1,
                author="A",
                tags=[],
                created_at="T",
                file_path="models/../../secret",
                file_size_bytes=0,
                sha256="a" * 64,
                metadata={},
            )
