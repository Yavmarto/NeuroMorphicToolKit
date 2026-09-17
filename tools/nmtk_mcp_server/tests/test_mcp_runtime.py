from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from tools.nmtk_mcp_server import mcp_runtime
from tools.nmtk_mcp_server.mcp_runtime import create_mcp_server, require_fastmcp
from tools.nmtk_mcp_server.runtime_config import RuntimeConfig


class _FakeFastMCP:
    def __init__(self, name: str, **kwargs: Any) -> None:
        self.name = name
        self.kwargs = kwargs
        self.resources: dict[str, Any] = {}
        self.tools: dict[str, Any] = {}
        self.prompts: dict[str, Any] = {}
        self.runs: list[dict[str, Any]] = []

    def resource(self, uri: str, **kwargs: Any) -> Any:
        def decorator(func: Any) -> Any:
            self.resources[uri] = {"func": func, "kwargs": kwargs}
            return func

        return decorator

    def tool(self, name: str | None = None, **kwargs: Any) -> Any:
        def decorator(func: Any) -> Any:
            self.tools[name or func.__name__] = {"func": func, "kwargs": kwargs}
            return func

        return decorator

    def prompt(self, name: str | None = None, **kwargs: Any) -> Any:
        def decorator(func: Any) -> Any:
            self.prompts[name or func.__name__] = {"func": func, "kwargs": kwargs}
            return func

        return decorator

    def run(self, **kwargs: Any) -> None:
        self.runs.append(kwargs)


def test_create_mcp_server_registers_expected_surface(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setattr(mcp_runtime, "FastMCP", _FakeFastMCP)

    server = create_mcp_server(
        RuntimeConfig(repo_root=tmp_path, state_path=tmp_path / "state.json")
    )

    assert set(server.resources) >= {
        "nmtk://cnl/grammar/current",
        "nmtk://cnl/support-matrix/current",
        "nmtk://suite/modules/current",
        "nmtk://api/openapi/current",
    }
    assert set(server.tools) >= {
        "validate_cnl",
        "suite_health",
        "launcher_doctor",
        "list_modules",
        "get_cnl_authoring_guide",
        "submit_simulation",
        "poll_simulation_job",
        "check_deployability",
        "prepare_neurochip_handoff",
        "save_deerflow_packet",
        "load_local_state",
    }
    assert "deploy_to_target" not in server.tools
    assert "run_shell" not in server.tools
    assert "deerflow_packet_scaffold" in server.prompts


def test_missing_fastmcp_dependency_is_actionable(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(mcp_runtime, "FastMCP", None)

    with pytest.raises(RuntimeError, match="pip install"):
        require_fastmcp()
