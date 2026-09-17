"""Map MCP tool results to Studio pipeline step names.

Must stay aligned with
``nmtk/neuro_toolkit/lib/features/neurocnl/models/studio_pipeline_steps.dart``.
"""

from __future__ import annotations

from typing import Any

STUDIO_PIPELINE_STEP_NAMES: tuple[str, ...] = (
    "selectData",
    "defineModel",
    "defineTrain",
    "defineEval",
    "run",
    "deployHardware",
    "deployReview",
)

TOOL_TO_PIPELINE_STEP: dict[str, str] = {
    "validate_cnl": "defineModel",
    "get_cnl_authoring_guide": "defineModel",
    "submit_simulation": "run",
    "poll_simulation_job": "run",
    "check_deployability": "deployHardware",
    "prepare_neurochip_handoff": "deployHardware",
}

NEXT_ACTION_TO_PIPELINE_STEP: dict[str, str] = {
    "submit_simulation": "run",
    "poll_simulation_job": "run",
}


def pipeline_step_for_tool(tool_name: str) -> str | None:
    step = TOOL_TO_PIPELINE_STEP.get(tool_name)
    if step is None or step not in STUDIO_PIPELINE_STEP_NAMES:
        return None
    return step


def pipeline_steps_from_tool_result(
    tool_name: str,
    result: dict[str, Any],
) -> list[dict[str, Any]]:
    """Return ``step_suggested`` payloads for a finished tool result."""
    suggestions: list[dict[str, Any]] = []
    seen: set[str] = set()

    tool_step = pipeline_step_for_tool(tool_name)
    if tool_step is not None and tool_step not in seen:
        seen.add(tool_step)
        suggestions.append(
            {
                "step": tool_step,
                "reason": "tool",
                "tool": tool_name,
            }
        )

    for action in result.get("next_actions", []):
        if not isinstance(action, dict):
            continue
        action_name = action.get("action")
        if not isinstance(action_name, str):
            continue
        step = NEXT_ACTION_TO_PIPELINE_STEP.get(action_name)
        if step is None or step not in STUDIO_PIPELINE_STEP_NAMES or step in seen:
            continue
        seen.add(step)
        suggestions.append(
            {
                "step": step,
                "reason": "next_action",
                "action": action_name,
                "label": action.get("label"),
            }
        )

    return suggestions
