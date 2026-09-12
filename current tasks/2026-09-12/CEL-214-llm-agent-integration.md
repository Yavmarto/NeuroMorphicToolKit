# CEL-214: LLM Agent Integration

**Status:** Done — CEL-218 audit + CEL-219 spot-check pass (2026-09-12)

## Summary

Add in-app Studio assistant chat that drives NMTK MCP tools through local LLM harnesses (Ollama, LM Studio, Claude Code, Codex, Cursor, OpenCode). Progressive build UI shows tool steps one at a time instead of batch-applying workspace state.

## Architecture

- Flutter `StudioAssistantPanel` → SSE `POST /api/studio/agent/chat`
- `suite_api` reuses `tools/nmtk_mcp_server/tool_handlers.py`
- Desktop provider registry probes PATH + localhost APIs

## Delegated issues

| Issue | Scope |
|-------|-------|
| CEL-215 | Studio agent API + MCP handler bridge |
| CEL-216 | Desktop LLM provider registry |
| CEL-217 | Studio assistant chat + progressive build UI |

## Key existing assets

- `tools/nmtk_mcp_server/` — MCP server (Phases 1–3 done)
- `studio_pipeline_steps.dart` + `step_unlock_provider.dart` — progressive unlock
- `result_models.py` — `ToolResult` envelope for chat cards
