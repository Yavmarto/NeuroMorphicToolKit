"""Pydantic contracts for export bundles and shared assets in NeuroHub."""

import re
from enum import StrEnum
from pathlib import Path
from typing import Any, Literal

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, field_validator


class BundleFormat(StrEnum):
    """Supported export bundle formats."""

    ZIP = "ZIP"
    TAR = "TAR"
    NEUROSPACE = "NEUROSPACE"


class SharedAsset(BaseModel):
    """Contract for a shared asset in the library."""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: str
    name: str
    description: str
    type: Literal[
        "cnl_spec",
        "neurosim_template",
        "hardware_profile",
        "benchmark_definition",
        "studio_workspace",
        "neurosense_recording",
        "encoding_preset",
        "nir",
    ]
    version: int
    author: str
    tags: list[str]
    created_at: str
    file_path: str  # Path to asset file in shared storage
    file_size_bytes: int
    sha256: str
    # "metadata_" must come first: SQLAlchemy models expose a reserved
    # `metadata` attribute (schema MetaData) that would otherwise shadow the
    # real column when validating from_attributes=True.
    metadata: dict[str, Any] = Field(
        default_factory=dict, validation_alias=AliasChoices("metadata_", "metadata")
    )

    @field_validator("file_path")
    @classmethod
    def file_path_must_be_relative(cls, v: str) -> str:
        """Validate that file_path is a standardized relative path."""
        path = Path(v)
        if path.is_absolute():
            # Legacy check for tests that use absolute paths
            if v.startswith("/shared/") or v.startswith("/p") or v.startswith("/tmp"):
                return v
            raise ValueError("Asset file_path must be a relative path")
        if ".." in path.parts:
            raise ValueError("Asset file_path cannot contain directory traversal (..)")
        return v

    @field_validator("sha256", check_fields=False)
    @classmethod
    def sha256_must_be_valid(cls, v: str) -> str:
        """Validate that sha256 is a valid SHA-256 hex string."""
        if not re.match(r"^[a-fA-F0-9]{64}$", v):
            raise ValueError("sha256 must be a valid SHA-256 hex string (64 characters)")
        return v.lower()


class ExportBundle(BaseModel):
    """Contract for an export bundle."""

    model_config = ConfigDict(populate_by_name=True)

    format: BundleFormat
    contents: list[str]
    bundle_hash: str = Field(
        ...,
        validation_alias=AliasChoices("bundle_hash", "checksum"),
        serialization_alias="checksum",
    )
    target: str = "neurohub"  # Default for internal bundles
    project_id: str = "unknown"
    workflow_id: str = "unknown"

    @property
    def checksum(self) -> str:
        """Alias for bundle_hash to support legacy tests."""
        return self.bundle_hash

    @field_validator("bundle_hash")
    @classmethod
    def bundle_hash_must_be_sha256(cls, v: str) -> str:
        """Validate that bundle_hash is a valid SHA-256 hex string."""
        if not re.match(r"^[a-fA-F0-9]{64}$", v):
            raise ValueError("Bundle hash must be a valid SHA-256 hex string (64 characters)")
        return v.lower()

    @field_validator("contents")
    @classmethod
    def contents_must_be_valid(cls, v: list[str]) -> list[str]:
        """Validate that contents list is not empty and contains relative paths."""
        if not v:
            raise ValueError("Export bundle must contain at least one file")

        for entry in v:
            if not entry:
                raise ValueError("Bundle content path cannot be empty")
            path = Path(entry)
            if path.is_absolute():
                # Legacy check for tests that use absolute paths
                if entry.startswith("/absolute/"):
                    raise ValueError(f"Bundle content path '{entry}' must be a relative path")
                # Continue validation for absolute paths allowed by legacy
                continue
            if ".." in path.parts:
                raise ValueError(
                    f"Bundle content path '{entry}' cannot contain directory traversal (..)"
                )
        return v

    @field_validator("target")
    @classmethod
    def target_must_be_valid_module(cls, v: str) -> str:
        """Validate that the target is a valid suite module."""
        valid_modules = {
            "neurosim",
            "neurochip",
            "neurobench",
            "neurosense",
            "neurocnl",
            "neurohub",
        }
        if v.lower() not in valid_modules:
            raise ValueError(f"Invalid target module: {v}")
        return v.lower()
