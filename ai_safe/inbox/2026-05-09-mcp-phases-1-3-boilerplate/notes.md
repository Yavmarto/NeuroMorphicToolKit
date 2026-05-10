# Notes

## Intent

This is a single large DeerFlow boilerplate packet for Phases 1-3 of the planned MCP service.

The goal is to offload repetitive scaffolding while keeping local ownership of:

- final tool semantics
- deployment safety
- status classification policy
- target normalization rules
- final MCP runtime binding

## Canonical Local Sources

- Grammar:
  - `neurocnl/neurocnl/cnl/cnl_grammar.md`
- Support matrix:
  - `neurocnl/docs/support_matrix.md`
- Launcher manifest:
  - `nmtk/neuro_toolkit/assets/modules.json`
- Suite health route:
  - `GET /api/suite/health`
- Launcher doctor route:
  - `GET /api/launcher/doctor`
- Launcher modules route:
  - `GET /api/launcher/modules`
- NeuroCNL validate route:
  - `POST /api/neurocnl/validate`
- NeuroSim preview route:
  - `POST /api/neurosim/preview`
- Deployability routes:
  - `POST /api/neurocnl/deploy/teensy/network`
  - `POST /api/neurocnl/deploy/pynq/network`

## Why The Blueprint Is Runtime-Neutral

The repo does not yet commit to a concrete MCP runtime dependency. This packet therefore asks for:

- resource metadata
- tool metadata
- prompt metadata
- typed clients
- typed local state helpers

This lets local maintainers wire the final runtime adapter later without discarding the generated code.

## Recommended DeerFlow Output Shape

Good output for this packet is:

- new files for Phase 1-3 scaffolding
- focused unit tests
- small export updates in `__init__.py` only if needed

Bad output for this packet is:

- shell execution helpers
- device deployment code
- new manifest semantics
- concrete MCP runtime framework lock-in
- edits outside `tools/nmtk_mcp_server/`

## Review Guidance After Reintegration

Local reviewers should inspect:

- whether blueprint names match the design doc
- whether prompts stay short and resource-oriented
- whether the module and deployability clients call only approved routes
- whether any final-status semantics were invented where the packet asked for scaffolding only
- whether Phase 4 concerns leaked into the implementation
