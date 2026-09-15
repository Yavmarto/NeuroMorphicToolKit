# CEL-231: Chat cannot connect

**Status:** Fixed (2026-09-13)

## Problem

Studio assistant chat returned HTTP 404 on `/api/studio/agent/*` against the dev backend (`192.168.2.90:9000`). After a partial sync, `suite_api` crash-looped with `ModuleNotFoundError: No module named 'tools'`.

## Root cause

1. CEL-214 studio agent routes were never deployed to the dev host (404).
2. `tools/nmtk_mcp_server/` was missing from `scripts/rsync-excludes.txt`, so `make dev-update` could not ship the MCP package the studio agent imports at startup.

## Fix

- Added `+ /tools/` and `+ /tools/nmtk_mcp_server/***` to `scripts/rsync-excludes.txt`.
- Synced `tools/nmtk_mcp_server/` to `~/nmtk-deploy` and restarted `suite_api`.

## Verification

```bash
curl http://192.168.2.90:9000/api/studio/agent/providers   # 200
curl -X POST http://192.168.2.90:9000/api/studio/agent/sessions -d '{}'  # 200 + session_id
```

## Follow-up UX (2026-09-13)

Studio assistant now auto-selects the first desktop CLI harness (Claude, Codex, etc.) when none is active, so chat works without manual provider selection when a CLI is on PATH.

## Residual (expected when no harness exists)

If no CLI is installed on the desktop and no Ollama/LM Studio runs on the backend, chat still reports that no local LLM harness is available.
