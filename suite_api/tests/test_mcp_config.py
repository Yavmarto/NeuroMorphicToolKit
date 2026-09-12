"""Tests for MCP config helpers."""

from __future__ import annotations

from pathlib import Path

from suite_api.services.mcp_config import (
    build_mcp_server_entry,
    enrich_provider_probe,
)
from tools.nmtk_mcp_server.runtime_config import RuntimeConfig


def test_build_mcp_server_entry_includes_repo_root() -> None:
    config = RuntimeConfig(
        repo_root=Path("/tmp/nmtk"),
        suite_api_base_url="http://127.0.0.1:9000",
        launcher_base_url="http://127.0.0.1:8765",
    )
    entry = build_mcp_server_entry(config, repo_root="/Users/dev/NeuroMorphicToolKit")
    assert entry["server_name"] == "nmtk"
    assert entry["env"]["NMTK_SUITE_API_URL"] == "http://127.0.0.1:9000"
    assert entry["env"]["NMTK_REPO_ROOT"] == "/Users/dev/NeuroMorphicToolKit"


def test_enrich_provider_probe_flags_cli_harnesses() -> None:
    enriched = enrich_provider_probe(
        {
            "provider_id": "claude",
            "label": "Claude Code",
            "available": True,
            "detail": "/usr/local/bin/claude",
        }
    )
    assert enriched["supports_mcp_install"] is True
    assert "claude_desktop_config.json" in enriched["mcp_config_hint"]
