from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

from .prompts import load_prompt_templates


class ResourceDescriptor(BaseModel):
    uri: str
    name: str
    description: str
    read_only: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)


class ToolDescriptor(BaseModel):
    name: str
    description: str
    phase: str
    safe_local: bool = True
    route: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class PromptDescriptor(BaseModel):
    name: str
    description: str
    resource_uris: list[str] = Field(default_factory=list)
    template: str


class ServerBlueprint(BaseModel):
    name: str = "nmtk_mcp_server"
    transport: str = "runtime-neutral"
    resources: list[ResourceDescriptor] = Field(default_factory=list)
    tools: list[ToolDescriptor] = Field(default_factory=list)
    prompts: list[PromptDescriptor] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)


def build_server_blueprint() -> ServerBlueprint:
    """Return declarative MCP surface metadata without binding a runtime."""
    prompts = [
        PromptDescriptor(
            name=template.name,
            description=template.description,
            resource_uris=list(template.resource_uris),
            template=template.template,
        )
        for template in load_prompt_templates()
    ]
    return ServerBlueprint(
        resources=[
            ResourceDescriptor(
                uri="nmtk://cnl/grammar/current",
                name="Current NeuroCNL grammar",
                description="Canonical NeuroCNL grammar markdown loaded from this checkout.",
            ),
            ResourceDescriptor(
                uri="nmtk://cnl/support-matrix/current",
                name="Current NeuroCNL support matrix",
                description="Canonical backend support matrix loaded from this checkout.",
            ),
            ResourceDescriptor(
                uri="nmtk://suite/modules/current",
                name="Launcher module manifest",
                description="Launcher module registry loaded from nmtk modules.json.",
            ),
            ResourceDescriptor(
                uri="nmtk://api/openapi/current",
                name="Suite API OpenAPI document",
                description="Read-only suite_api OpenAPI document when exposed by the running service.",
            ),
        ],
        tools=[
            ToolDescriptor(
                name="validate_cnl",
                description="Validate a NeuroCNL spec through suite_api.",
                phase="1",
                route="/api/neurocnl/validate",
            ),
            ToolDescriptor(
                name="suite_health",
                description="Read suite_api health.",
                phase="1",
                route="/api/suite/health",
            ),
            ToolDescriptor(
                name="launcher_doctor",
                description="Read launcher doctor status with explicit preflight semantics.",
                phase="1",
                route="/api/launcher/doctor",
            ),
            ToolDescriptor(
                name="list_modules",
                description="Read launcher module status from the launcher control plane.",
                phase="1",
                route="/api/launcher/modules",
            ),
            ToolDescriptor(
                name="get_cnl_authoring_guide",
                description="Build bounded authoring guidance from canonical local resources.",
                phase="1",
            ),
            ToolDescriptor(
                name="submit_simulation",
                description="Submit a NeuroCNL simulation job through suite_api.",
                phase="2",
                route="/api/neurocnl/simulate",
            ),
            ToolDescriptor(
                name="poll_simulation_job",
                description="Poll a suite_api NeuroCNL simulation job.",
                phase="2",
                route="/api/neurocnl/jobs/{job_id}",
            ),
            ToolDescriptor(
                name="check_deployability",
                description="Check target-specific deployability without device execution.",
                phase="2",
                route="/api/neurocnl/deploy/{target}/network",
            ),
            ToolDescriptor(
                name="prepare_neurochip_handoff",
                description="Prepare typed handoff payload scaffolding without deployment.",
                phase="2",
            ),
            ToolDescriptor(
                name="save_deerflow_packet",
                description="Persist a local DeerFlow packet for later runtime wiring.",
                phase="3",
            ),
            ToolDescriptor(
                name="load_local_state",
                description="Load local MCP state from a caller-provided JSON path.",
                phase="3",
            ),
        ],
        prompts=prompts,
        metadata={
            "phases": ["1", "2", "3"],
            "privileged_execution": False,
            "runtime_dependency": None,
        },
    )
