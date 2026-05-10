from __future__ import annotations

from tools.nmtk_mcp_server.result_models import ToolResult


def test_tool_result_defaults_are_stable() -> None:
    result = ToolResult(status="ok", summary="done")

    assert result.details == {}
    assert result.artifacts == []
    assert result.next_actions == []
