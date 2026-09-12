# CEL-218 QA Audit Report — CEL-214 LLM Agent Integration

**Auditor:** QA  
**Date:** 2026-09-12  
**Verdict:** **Partial pass — fix list required before CEL-214 can close**

## Test execution

| Suite | Command | Result |
|-------|---------|--------|
| Flutter assistant widgets | `flutter test test/features/neurocnl/features/studio/assistant/` | **8/8 pass** |
| Python studio agent + providers | `cd suite_api && uv run pytest tests/test_studio_agent.py tests/test_llm_providers.py tests/test_studio_assistant_skill.py` | **23/23 pass** |
| Python bare pytest | `python3 -m pytest suite_api/tests/test_llm_providers.py` | **3/8 pass** — 5 async tests fail without `pytest-asyncio` plugin |
| Dart static analysis | `dart analyze lib/features/neurocnl/features/studio/assistant/` | **0 errors**, 4 info lints |

## Flutter audit (nmtk-flutter-review)

### Pass

- Riverpod notifier/service split is clean; `TextEditingController` disposed correctly.
- Progressive build UI: SSE timeline, guarded `applyStepSuggestion` via `unlockedStepsProvider`, no batch workspace apply in tests.
- Zeta semantic colors used for status (positive/warning/negative).
- Widget tests cover tool cards, timeline, step unlock guard, provider setup bar.

### Findings

| Sev | Finding | Location |
|-----|---------|----------|
| **P1** | `_syncFromState()` mutates `_selectedProviderId` / controller text inside `build()` without `setState` — violates nmtk widget sync rules; dropdown can desync from provider state | `studio_assistant_setup_bar.dart:29-55` |
| **P2** | Raw `BorderRadius.circular(12)` instead of `NmtkShellTokens.radiusSm` | `build_timeline.dart:90` |
| **P2** | `DropdownButtonFormField.value` deprecated; use `initialValue` pattern | `studio_assistant_setup_bar.dart:100` |
| **P3** | Example repo path in hint uses developer-specific absolute path | `studio_assistant_setup_bar.dart:184` |

## Python audit (nmtk-python-review)

### Pass

- Router delegates to services; typed exception handling on LLM turn (`OSError`, `RuntimeError`, `ValueError`, `httpx.HTTPError`).
- MCP bridge reuses `run_tool()` + `ToolHandlerContext`; session skill injection once per session.
- Tests mock httpx/subprocess cleanly under `uv run`.

### Findings

| Sev | Finding | Location |
|-----|---------|----------|
| **P0** | Hardcoded `config.suite_api_base_url = "http://127.0.0.1:9000"` breaks Docker/multi-port and remote backend topologies | `studio_agent.py:63` |
| **P1** | LLM tool schema exposes **5/11** MCP tools; simulation/deploy/handoff tools callable via `run_tool` but invisible to LLM | `registry.py:studio_agent_tool_schemas()` vs `tool_handlers.py:TOOL_NAMES` |
| **P1** | CLI/HTTP provider probing runs on **suite_api host**, not Flutter desktop — remote backend users won't see local `claude`/`cursor-agent` | `suite_api/services/llm_providers/` |
| **P2** | In-process `_sessions` dict not multi-worker safe (ponytail comment present; document or persist) | `studio_agent.py:28-29` |
| **P2** | `python3 -m pytest` from repo root skips `pytest-asyncio` even though declared in `suite_api/pyproject.toml` — CI/dev footgun | `test_llm_providers.py` |

## Alignment with Engineer requirements review

Engineer verdict **partial** is confirmed. Chat/timeline/progressive UI pass; architecture gaps (server-side harness, partial MCP schema, hardcoded loopback) remain blocking for **done**.

## Recommended owner: Engineer

1. Fix `suite_api_base_url` from runtime config.
2. Decide + implement harness topology (server-side vs desktop-side probing) or document accepted limitation with UX messaging.
3. Expose remaining MCP tools in LLM schema or document intentional subset with user-visible scope.
4. Fix `_syncFromState` pattern in setup bar (use `ref.listen` + `setState`).
5. Ensure root-level pytest loads asyncio plugin for suite_api tests (or document `uv run pytest` as canonical).

## QA disposition

Audit complete. [CEL-214](/CEL/issues/CEL-214) may unblock for Engineer reconciliation; QA does not mark CEL-214 done.
