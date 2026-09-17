"""MCP server entry templates for external desktop LLM harnesses."""

from __future__ import annotations

from typing import Any

from tools.nmtk_mcp_server.runtime_config import RuntimeConfig

MCP_HARNESS_PROVIDER_IDS: frozenset[str] = frozenset(
    {"claude", "codex", "cursor-agent", "opencode", "antigravity"}
)

MCP_CONFIG_HINTS: dict[str, str] = {
    "claude": "~/Library/Application Support/Claude/claude_desktop_config.json",
    "cursor-agent": "~/.cursor/mcp.json",
    "codex": "~/.codex/config.toml (manual MCP section)",
    "opencode": "~/.config/opencode/config.json (manual MCP section)",
    "antigravity": "~/.gemini/antigravity-cli/settings.json (/mcp panel)",
}


def build_mcp_server_entry(
    config: RuntimeConfig,
    *,
    repo_root: str | None = None,
) -> dict[str, Any]:
    """Return the MCP server block Studio can merge into a harness config file."""
    env: dict[str, str] = {
        "NMTK_SUITE_API_URL": config.suite_api_base_url,
        "NMTK_LAUNCHER_URL": config.launcher_base_url,
    }
    if repo_root:
        env["NMTK_REPO_ROOT"] = repo_root
    return {
        "server_name": "nmtk",
        "command": "python3",
        "args": ["-m", "tools.nmtk_mcp_server"],
        "env": env,
        "requires_repo_root": True,
    }


def enrich_provider_probe(probe: dict[str, Any]) -> dict[str, Any]:
    provider_id = str(probe.get("provider_id", ""))
    enriched = dict(probe)
    enriched["supports_mcp_install"] = provider_id in MCP_HARNESS_PROVIDER_IDS
    enriched["mcp_config_hint"] = MCP_CONFIG_HINTS.get(provider_id)
    # ponytail: probes run on the suite_api host; desktop CLIs on the Flutter
    # machine are invisible unless installed on the backend too.
    enriched["probe_host"] = "backend"
    return enriched
