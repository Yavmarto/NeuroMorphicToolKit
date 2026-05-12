from __future__ import annotations

from tools.nmtk_mcp_server.result_models import (
    ArtifactRef,
    NextAction,
    ToolResult,
    ToolStatus,
)


def test_tool_result_defaults_are_stable() -> None:
    result = ToolResult(status="ok", summary="done")

    assert result.details == {}
    assert result.artifacts == []
    assert result.next_actions == []


def test_tool_result_accepts_common_statuses_and_artifacts() -> None:
    result = ToolResult(
        status=ToolStatus.needs_attention,
        summary="saved packet",
        artifacts=[
            ArtifactRef(
                kind="deerflow_packet",
                uri="nmtk://state/deerflow/packet-1",
                title="Packet 1",
            )
        ],
        next_actions=[NextAction(action="poll_simulation_job", label="Poll job")],
    )

    assert result.status == "needs_attention"
    assert result.artifacts[0].kind == "deerflow_packet"
    assert result.next_actions[0].action == "poll_simulation_job"
