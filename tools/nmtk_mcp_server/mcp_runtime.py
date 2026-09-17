from __future__ import annotations

import json
from typing import Any

import requests

from .prompts import PromptTemplate
from .resources import load_cnl_grammar, load_support_matrix
from .runtime_config import RuntimeConfig
from .server_blueprint import build_server_blueprint
from .tool_handlers import ToolHandlerContext

try:  # pragma: no cover - exercised with monkeypatch in tests when absent.
    from mcp.server.fastmcp import FastMCP
except ImportError:  # pragma: no cover
    FastMCP = None  # type: ignore[assignment]


def require_fastmcp() -> Any:
    if FastMCP is None:
        raise RuntimeError(
            "FastMCP is required to run the NMTK MCP server. "
            "Install dependencies with: python3 -m pip install -r "
            "tools/nmtk_mcp_server/requirements.txt"
        )
    return FastMCP


def create_mcp_server(config: RuntimeConfig | None = None) -> Any:
    runtime_config = config or RuntimeConfig.from_env()
    fastmcp_cls = require_fastmcp()
    blueprint = build_server_blueprint()
    handlers = ToolHandlerContext(runtime_config)
    server = fastmcp_cls(
        blueprint.name,
        instructions=(
            "NMTK MCP server exposing read-only suite resources, safe local "
            "validation/simulation/deployability helpers, and local DeerFlow state "
            "scaffolding. Privileged deployment is intentionally out of scope."
        ),
        json_response=True,
    )

    _register_resources(server, runtime_config, handlers)
    _register_tools(server, handlers)
    _register_prompts(server, blueprint.prompts)
    return server


def run(config: RuntimeConfig | None = None) -> None:
    runtime_config = config or RuntimeConfig.from_env()
    server = create_mcp_server(runtime_config)
    kwargs: dict[str, Any] = {"transport": runtime_config.transport}
    if runtime_config.transport == "streamable-http":
        kwargs.update({"host": runtime_config.host, "port": runtime_config.port})
    server.run(**kwargs)


def _register_resources(
    server: Any,
    config: RuntimeConfig,
    handlers: ToolHandlerContext,
) -> None:
    @server.resource("nmtk://cnl/grammar/current")
    def cnl_grammar_current() -> str:
        """Return canonical NeuroCNL grammar markdown."""
        return load_cnl_grammar(handlers.paths)

    @server.resource("nmtk://cnl/support-matrix/current")
    def cnl_support_matrix_current() -> str:
        """Return canonical NeuroCNL support matrix markdown."""
        return load_support_matrix(handlers.paths)

    @server.resource("nmtk://suite/modules/current")
    def suite_modules_current() -> str:
        """Return launcher modules manifest JSON."""
        return handlers.load_modules_manifest_resource()

    @server.resource("nmtk://api/openapi/current")
    def suite_openapi_current() -> str:
        """Return suite_api OpenAPI JSON when the service is reachable."""
        url = f"{config.suite_api_base_url.rstrip('/')}/openapi.json"
        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            payload = response.json()
        except requests.RequestException as exc:
            payload = {
                "status": "unavailable",
                "summary": f"suite_api OpenAPI document unavailable from {url}: {exc}",
            }
        except ValueError as exc:
            payload = {
                "status": "invalid_response",
                "summary": f"suite_api OpenAPI response was not valid JSON: {exc}",
            }
        return json.dumps(payload, indent=2, sort_keys=True)


def _register_tools(server: Any, handlers: ToolHandlerContext) -> None:
    @server.tool(name="validate_cnl")
    def validate_cnl(
        spec: str,
        backend: str = "nengo",
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Validate a NeuroCNL spec through suite_api."""
        return handlers.validate_cnl(spec=spec, backend=backend, params=params)

    @server.tool(name="suite_health")
    def suite_health() -> dict[str, Any]:
        """Read suite_api health."""
        return handlers.suite_health()

    @server.tool(name="launcher_doctor")
    def launcher_doctor() -> dict[str, Any]:
        """Read launcher doctor status with explicit preflight semantics."""
        return handlers.launcher_doctor()

    @server.tool(name="list_modules")
    def list_modules(refresh_updates: bool = False) -> dict[str, Any]:
        """Read launcher module status."""
        return handlers.list_modules(refresh_updates=refresh_updates)

    @server.tool(name="get_cnl_authoring_guide")
    def get_cnl_authoring_guide(
        topic: str | None = None,
        max_sections_per_source: int = 2,
    ) -> dict[str, Any]:
        """Build bounded CNL authoring guidance from canonical resources."""
        return handlers.get_cnl_authoring_guide(
            topic=topic,
            max_sections_per_source=max_sections_per_source,
        )

    @server.tool(name="submit_simulation")
    def submit_simulation(
        spec: str,
        duration: float = 1.0,
        dt: float = 0.001,
        backend: str = "nengo",
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Submit a NeuroCNL simulation job through suite_api."""
        return handlers.submit_simulation(
            spec=spec,
            duration=duration,
            dt=dt,
            backend=backend,
            params=params,
        )

    @server.tool(name="poll_simulation_job")
    def poll_simulation_job(job_id: str) -> dict[str, Any]:
        """Poll a suite_api NeuroCNL simulation job."""
        return handlers.poll_simulation_job(job_id)

    @server.tool(name="check_deployability")
    def check_deployability(
        spec: str,
        target: str,
        options: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Check target-specific deployability without device execution."""
        return handlers.check_deployability(spec=spec, target=target, options=options)

    @server.tool(name="prepare_neurochip_handoff")
    def prepare_neurochip_handoff(
        spec: str,
        target: str,
        readiness_summary: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Prepare typed handoff payload scaffolding without deployment."""
        return handlers.prepare_neurochip_handoff(
            spec=spec,
            target=target,
            readiness_summary=readiness_summary,
        )

    @server.tool(name="save_deerflow_packet")
    def save_deerflow_packet(
        packet_id: str,
        payload: dict[str, Any],
        title: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Persist a local DeerFlow packet."""
        return handlers.save_deerflow_packet(
            packet_id=packet_id,
            payload=payload,
            title=title,
            metadata=metadata,
        )

    @server.tool(name="load_local_state")
    def load_local_state() -> dict[str, Any]:
        """Load local MCP state."""
        return handlers.load_local_state()


def _register_prompts(server: Any, prompts: list[Any]) -> None:
    for prompt in prompts:
        _register_prompt(server, prompt)


def _register_prompt(server: Any, prompt: PromptTemplate) -> None:
    template = prompt.template

    @server.prompt(name=prompt.name, description=prompt.description)
    def prompt_template() -> str:
        return template
