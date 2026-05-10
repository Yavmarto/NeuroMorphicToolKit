from dataclasses import dataclass


@dataclass(frozen=True)
class PromptTemplate:
    name: str
    description: str
    resource_uris: list[str]
    template: str


def load_prompt_templates() -> list[PromptTemplate]:
    """Return versioned prompt metadata for Phase 1-3 workflows."""
    return [
        PromptTemplate(
            name="cnl_authoring_assistant",
            description="Guide CNL authoring with grammar and examples",
            resource_uris=[
                "nmtk://cnl/grammar/current",
                "nmtk://cnl/support-matrix/current",
            ],
            template="Use the CNL grammar and support matrix to guide authoring. Intent: {intent}. Backend: {backend}.",
        ),
        PromptTemplate(
            name="suite_diagnostics",
            description="Diagnose suite health and module status",
            resource_uris=[
                "nmtk://suite/modules/current",
                "nmtk://api/openapi/current",
            ],
            template="Check suite health and module status. Report any degraded or failed components.",
        ),
        PromptTemplate(
            name="simulation_workflow",
            description="Guide NeuroCNL simulation and preview",
            resource_uris=[
                "nmtk://cnl/grammar/current",
                "nmtk://api/openapi/current",
            ],
            template="Validate CNL spec: {spec}. Backend: {backend}. Mode: {mode}.",
        ),
        PromptTemplate(
            name="deployability_check",
            description="Check deployability for target hardware",
            resource_uris=[
                "nmtk://cnl/support-matrix/current",
                "nmtk://api/openapi/current",
            ],
            template="Check deployability for target: {target}. Spec: {spec}.",
        ),
    ]
