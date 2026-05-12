from __future__ import annotations

from tools.nmtk_mcp_server.prompts import load_prompt_templates


def test_prompt_templates_cover_core_workflows() -> None:
    templates = load_prompt_templates()

    assert [template.name for template in templates] == [
        "cnl_authoring_assistant",
        "suite_diagnostics",
        "simulation_workflow",
        "deployability_check",
        "deerflow_packet_scaffold",
    ]
    assert all(template.resource_uris for template in templates)
