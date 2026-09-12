# CEL-216: Desktop LLM provider registry

**Status:** Done

## Delivered

- `suite_api/services/llm_providers/` — Ollama, LM Studio, SubprocessCli adapters
- Supported harnesses: `ollama`, `lmstudio`, `claude`, `codex`, `cursor-agent`, `opencode`
- PATH + localhost TCP probing (no shell injection; argv-list subprocess only)
- Settings hook: `STUDIO_LLM_PROVIDER`, `STUDIO_LLM_MODEL`, `OLLAMA_BASE_URL`, `LMSTUDIO_BASE_URL` in `suite_api/config.py`
- `GET /api/studio/agent/providers` — probe matrix for Flutter settings UI
- Studio chat auto-selects first available provider when message has no explicit `tool_calls`

## Verification

```bash
PYTHONPATH=".:neurocnl:Neurochip:Neurosense:Neurobench/neurobench:Neurohub" \
  suite_api/.venv/bin/python -m pytest \
  suite_api/tests/test_llm_providers.py \
  suite_api/tests/test_studio_agent.py -q
```

15 passed (Sep 2026).

## Provider matrix (dev machine)

| Provider | Detection |
|----------|-----------|
| ollama | TCP 11434 |
| lmstudio | TCP 1234 |
| claude | PATH `claude` |
| codex | PATH `codex` |
| cursor-agent | PATH `cursor-agent` |
| opencode | PATH `opencode` |
