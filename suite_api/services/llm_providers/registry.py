"""Desktop LLM provider registry with auto-detection.

Flutter settings hook: read/write `studio_llm_provider` via suite_api Settings
(`STUDIO_LLM_PROVIDER` env var today; expose through a future settings API).
When set, `resolve_active_provider()` returns that provider if it probes
available; otherwise it falls back to the first available provider in priority
order (Ollama → LM Studio → CLI harnesses).
"""

from __future__ import annotations

from typing import Any

from suite_api.config import settings
from suite_api.services.llm_providers.base import LlmProvider, ProviderProbe
from suite_api.services.llm_providers.lmstudio import LmStudioProvider
from suite_api.services.llm_providers.ollama import OllamaProvider
from suite_api.services.llm_providers.subprocess_cli import (
    CLI_HARNESSES,
    SubprocessCliProvider,
)
from tools.nmtk_mcp_server.tool_handlers import TOOL_NAMES

# ponytail: module-level singletons; per-request factory if tests need isolation.
_providers: list[LlmProvider] | None = None
_runtime_provider_id: str | None = None
_runtime_model: str | None = None


def get_active_provider_id() -> str | None:
    return _runtime_provider_id or settings.studio_llm_provider


def get_active_model() -> str | None:
    return _runtime_model or settings.studio_llm_model


def set_active_provider(
    provider_id: str | None,
    *,
    model: str | None = None,
) -> None:
    """Set the in-process Studio assistant provider override."""
    global _runtime_provider_id, _runtime_model
    _runtime_provider_id = provider_id.strip() if provider_id else None
    if model is not None:
        _runtime_model = model.strip() or None


def reset_runtime_selection_for_tests() -> None:
    global _runtime_provider_id, _runtime_model
    _runtime_provider_id = None
    _runtime_model = None


def all_providers() -> list[LlmProvider]:
    global _providers
    if _providers is None:
        _providers = [
            OllamaProvider(
                base_url=settings.ollama_base_url,
                default_model=settings.studio_llm_model or "llama3.2",
            ),
            LmStudioProvider(
                base_url=settings.lmstudio_base_url,
                default_model=settings.studio_llm_model or "local-model",
            ),
            *[SubprocessCliProvider(spec) for spec in CLI_HARNESSES],
        ]
    return _providers


def reset_providers_for_tests() -> None:
    """Clear cached provider list (tests only)."""
    global _providers
    _providers = None
    reset_runtime_selection_for_tests()


async def probe_all() -> list[ProviderProbe]:
    results: list[ProviderProbe] = []
    for provider in all_providers():
        results.append(await provider.probe())
    return results


async def resolve_active_provider() -> LlmProvider | None:
    override = get_active_provider_id()
    if override:
        for provider in all_providers():
            if provider.provider_id == override:
                probe = await provider.probe()
                if probe.available:
                    return provider
                return None
    for provider in all_providers():
        probe = await provider.probe()
        if probe.available:
            return provider
    return None


def studio_agent_tool_schemas() -> list[dict[str, Any]]:
    """OpenAI-style tool schemas for Studio MCP tools."""
    schemas = [
        {
            "type": "function",
            "function": {
                "name": "validate_cnl",
                "description": "Validate a NeuroCNL network specification.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "spec": {"type": "string"},
                        "backend": {"type": "string"},
                    },
                    "required": ["spec"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "suite_health",
                "description": "Read suite_api health status.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
        {
            "type": "function",
            "function": {
                "name": "launcher_doctor",
                "description": "Run launcher doctor diagnostics.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
        {
            "type": "function",
            "function": {
                "name": "list_modules",
                "description": "List launcher modules.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
        {
            "type": "function",
            "function": {
                "name": "get_cnl_authoring_guide",
                "description": "Load CNL authoring guidance.",
                "parameters": {
                    "type": "object",
                    "properties": {"topic": {"type": "string"}},
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "submit_simulation",
                "description": "Submit a NeuroCNL simulation job through suite_api.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "spec": {"type": "string"},
                        "duration": {"type": "number"},
                        "dt": {"type": "number"},
                        "backend": {"type": "string"},
                        "params": {"type": "object"},
                    },
                    "required": ["spec"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "poll_simulation_job",
                "description": "Poll a suite_api NeuroCNL simulation job.",
                "parameters": {
                    "type": "object",
                    "properties": {"job_id": {"type": "string"}},
                    "required": ["job_id"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "check_deployability",
                "description": (
                    "Check target-specific deployability without device execution."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "spec": {"type": "string"},
                        "target": {"type": "string"},
                        "options": {"type": "object"},
                    },
                    "required": ["spec", "target"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "prepare_neurochip_handoff",
                "description": (
                    "Prepare typed handoff payload scaffolding without deployment."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "spec": {"type": "string"},
                        "target": {"type": "string"},
                        "readiness_summary": {"type": "object"},
                    },
                    "required": ["spec", "target"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "save_deerflow_packet",
                "description": (
                    "Persist a local DeerFlow packet for later runtime wiring."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "packet_id": {"type": "string"},
                        "payload": {"type": "object"},
                        "title": {"type": "string"},
                        "metadata": {"type": "object"},
                    },
                    "required": ["packet_id", "payload"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "load_local_state",
                "description": "Load local MCP state from the configured JSON path.",
                "parameters": {"type": "object", "properties": {}},
            },
        },
    ]
    exposed = {item["function"]["name"] for item in schemas}
    assert exposed == set(TOOL_NAMES), (
        f"studio_agent_tool_schemas mismatch: {sorted(exposed)} vs {sorted(TOOL_NAMES)}"
    )
    return schemas
