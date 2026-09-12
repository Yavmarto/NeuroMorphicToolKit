# CEL-215: Studio agent API + MCP handler bridge

**Status:** Done

## Delivered

- `run_tool(name, args, ctx)` + `TOOL_NAMES` in `tools/nmtk_mcp_server/tool_handlers.py`
- `suite_api/routers/studio_agent.py` — session CRUD + SSE `POST /api/studio/agent/chat`
- `suite_api/routers/studio_agent_step_map.py` — tool/next_action → `kStudioPipelineStepNames`
- Router registered in `suite_api/main.py`; Docker copies `tools/nmtk_mcp_server/`

## SSE contract

Events: `assistant_delta`, `tool_started`, `tool_finished`, `step_suggested`, `done`

## Verification

```bash
PYTHONPATH=".:neurocnl:Neurochip:Neurosense:Neurobench/neurobench:Neurohub" \
  suite_api/.venv/bin/python -m pytest \
  suite_api/tests/test_studio_agent.py \
  tools/nmtk_mcp_server/tests/test_tool_handlers.py \
  tools/nmtk_mcp_server/tests/test_mcp_runtime.py -q
```

9 passed (Sep 2026).
