from __future__ import annotations

import os
from pathlib import Path

from pydantic import BaseModel, Field

from .resources import find_repo_root


class RuntimeConfig(BaseModel):
    repo_root: Path = Field(default_factory=find_repo_root)
    suite_api_base_url: str = "http://127.0.0.1:9000"
    launcher_base_url: str = "http://127.0.0.1:8765"
    state_path: Path | None = None
    transport: str = "stdio"
    host: str = "127.0.0.1"
    port: int = 8000

    @property
    def resolved_state_path(self) -> Path:
        if self.state_path is not None:
            return self.state_path
        return self.repo_root / ".nmtk" / "mcp" / "state.json"

    @classmethod
    def from_env(cls) -> "RuntimeConfig":
        repo_root = (
            Path(os.environ["NMTK_REPO_ROOT"])
            if "NMTK_REPO_ROOT" in os.environ
            else find_repo_root()
        )
        state_path = (
            Path(os.environ["NMTK_MCP_STATE_PATH"])
            if "NMTK_MCP_STATE_PATH" in os.environ
            else None
        )
        return cls(
            repo_root=repo_root,
            suite_api_base_url=os.environ.get(
                "NMTK_SUITE_API_URL",
                "http://127.0.0.1:9000",
            ),
            launcher_base_url=os.environ.get(
                "NMTK_LAUNCHER_URL",
                "http://127.0.0.1:8765",
            ),
            state_path=state_path,
            transport=os.environ.get("NMTK_MCP_TRANSPORT", "stdio"),
            host=os.environ.get("NMTK_MCP_HOST", "127.0.0.1"),
            port=int(os.environ.get("NMTK_MCP_PORT", "8000")),
        )
