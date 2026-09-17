"""Pydantic schemas for suite configuration in NeuroHub."""

from typing import Any

from pydantic import BaseModel


class SuiteConfig(BaseModel):
    """Schema for the overall suite configuration."""

    neurosim_url: str = "http://localhost:8000"
    neurochip_url: str = "http://localhost:8002"
    neurobench_url: str = "http://localhost:8003"
    neurosense_url: str = "http://localhost:8004"
    neurocnl_url: str = "http://localhost:8000"
    shared_storage_path: str = "./shared_assets"
    default_project_settings: dict[str, Any] = {}
