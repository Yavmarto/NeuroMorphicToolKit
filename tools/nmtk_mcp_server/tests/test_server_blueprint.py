from __future__ import annotations

from tools.nmtk_mcp_server.server_blueprint import build_server_blueprint


def test_blueprint_assembles_phase_one_to_three_surface() -> None:
    blueprint = build_server_blueprint()

    resource_uris = {resource.uri for resource in blueprint.resources}
    tool_names = {tool.name for tool in blueprint.tools}
    prompt_names = {prompt.name for prompt in blueprint.prompts}

    assert {
        "nmtk://cnl/grammar/current",
        "nmtk://cnl/support-matrix/current",
        "nmtk://suite/modules/current",
    }.issubset(resource_uris)
    assert {
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
    }.issubset(tool_names)
    assert "deerflow_packet_scaffold" in prompt_names


def test_blueprint_excludes_privileged_or_runtime_specific_tools() -> None:
    blueprint = build_server_blueprint()
    tool_names = {tool.name for tool in blueprint.tools}

    assert "deploy_to_target" not in tool_names
    assert "run_shell" not in tool_names
    assert blueprint.transport == "runtime-neutral"
