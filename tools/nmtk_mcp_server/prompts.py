from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PromptTemplate:
    name: str
    description: str
    resource_uris: list[str]
    template: str


def load_prompt_templates() -> list[PromptTemplate]:
    """Return versioned prompt metadata for the current MCP workflow surface."""
    return [
        PromptTemplate(
            name="cnl_authoring_assistant",
            description="Guide CNL authoring with grammar and support constraints.",
            resource_uris=[
                "nmtk://cnl/grammar/current",
                "nmtk://cnl/support-matrix/current",
            ],
            template=(
                "Use the CNL grammar and support matrix to guide authoring. "
                "Intent: {intent}. Backend: {backend}."
            ),
        ),
        PromptTemplate(
            name="suite_diagnostics",
            description="Inspect suite health, manifest state, and degraded capabilities.",
            resource_uris=[
                "nmtk://suite/modules/current",
                "nmtk://api/openapi/current",
            ],
            template=(
                "Check suite health and module status. Report any degraded or "
                "failed components."
            ),
        ),
        PromptTemplate(
            name="simulation_workflow",
            description="Guide validation-first NeuroCNL simulation and preview flows.",
            resource_uris=[
                "nmtk://cnl/grammar/current",
                "nmtk://api/openapi/current",
            ],
            template="Validate CNL spec: {spec}. Backend: {backend}. Mode: {mode}.",
        ),
        PromptTemplate(
            name="deployability_check",
            description="Guide target-specific deployability and exportability checks.",
            resource_uris=[
                "nmtk://cnl/support-matrix/current",
                "nmtk://api/openapi/current",
            ],
            template="Check deployability for target: {target}. Spec: {spec}.",
        ),
        PromptTemplate(
            name="deerflow_packet_scaffold",
            description="Prepare local DeerFlow packet context without dispatching it.",
            resource_uris=[
                "nmtk://suite/modules/current",
                "nmtk://cnl/support-matrix/current",
            ],
            template=(
                "Create a local DeerFlow packet scaffold for intent: {intent}. "
                "Do not claim deployment or hardware execution."
            ),
        ),
    ]
