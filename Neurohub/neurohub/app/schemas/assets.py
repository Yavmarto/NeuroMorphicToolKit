"""Pydantic schemas for shared assets in NeuroHub."""

from typing import Any, Literal

from pydantic import BaseModel, Field

from neurohub.contracts.bundle_contracts import SharedAsset


class ShareCreateRequest(BaseModel):
    """Client-facing request for creating a share entry from the UI."""

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
    tags: list[str] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)


__all__ = ["SharedAsset", "ShareCreateRequest"]
