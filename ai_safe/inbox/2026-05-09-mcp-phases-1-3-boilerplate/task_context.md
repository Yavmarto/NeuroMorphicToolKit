# Goal

Implement the requested behavior using only the sanitized context in this packet.

# Deliverable

Return a unified diff or a small set of unified diffs against the provided target files.

# Task Summary

Build a large boilerplate slice for NeuroMorphicToolKit's planned MCP service covering Phases 1-3 only:

- Phase 1: read-only resources and safe local tools
- Phase 2: simulation and deployability boilerplate
- Phase 3: DeerFlow packet and local state scaffolding

This task is for scaffolding and integration boilerplate, not final privileged runtime behavior. The existing foundation package already contains:

- canonical resource loaders
- typed NeuroCNL validation client
- typed control-plane health and doctor client

The new work should extend that package in a transport-neutral way so local reviewers can later wire it to the chosen MCP runtime without rewriting core models, prompts, clients, and state helpers.

# Existing Foundation Surface

Assume these files already exist and are authoritative for the current foundation slice:

- `tools/nmtk_mcp_server/__init__.py`
- `tools/nmtk_mcp_server/resources.py`
- `tools/nmtk_mcp_server/models.py`
- `tools/nmtk_mcp_server/neurocnl_client.py`
- `tools/nmtk_mcp_server/control_plane.py`
- `tools/nmtk_mcp_server/control_plane_models.py`

# Required Semantics To Mirror

- `suite_api` is the canonical backend surface.
- `nmtk` manifest semantics are the only runtime registry.
- `neurocnl` owns grammar, validation, backend support, and deploy handoff claims.
- Launcher doctor semantics must remain explicit:
  - fatal count > 0 => `preflight_failed`
  - degraded only => `degraded_optional_capability`
  - otherwise => `ok`
- Phase 1-3 outputs must be honest scaffolding over real routes and local resources; do not invent a second control plane.
- The transport layer must stay runtime-neutral in this packet. Do not choose or require a specific MCP framework.

# Write Scope

Create or update only files under:

- `tools/nmtk_mcp_server/`

Target files to create:

- `tools/nmtk_mcp_server/result_models.py`
- `tools/nmtk_mcp_server/authoring.py`
- `tools/nmtk_mcp_server/module_registry.py`
- `tools/nmtk_mcp_server/simulation_client.py`
- `tools/nmtk_mcp_server/deployability_client.py`
- `tools/nmtk_mcp_server/prompts.py`
- `tools/nmtk_mcp_server/state_store.py`
- `tools/nmtk_mcp_server/server_blueprint.py`
- `tools/nmtk_mcp_server/tests/test_result_models.py`
- `tools/nmtk_mcp_server/tests/test_authoring.py`
- `tools/nmtk_mcp_server/tests/test_module_registry.py`
- `tools/nmtk_mcp_server/tests/test_state_store.py`
- `tools/nmtk_mcp_server/tests/test_server_blueprint.py`

Files allowed to update if needed for exports only:

- `tools/nmtk_mcp_server/__init__.py`

# Non-Goals

- No Phase 4 privileged execution.
- No `deploy_to_target`.
- No raw shell tools.
- No launcher manifest changes.
- No `nmtk`, `suite_api`, `neurocnl`, or `Neurochip` code changes.
- No choosing a concrete MCP runtime library.
- No claims about backend or hardware support beyond the packet interfaces and examples.

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Python standard library
- `pydantic`
- `requests`

# What You Must Not Assume

- Hidden MCP framework helpers already exist
- Privileged deployment behavior is part of this slice
- Unshown target normalization rules may be invented
- Any route not named in this packet is safe to call

# Required Output Format

Use this exact structure:

## Assumptions

- List any assumption that was necessary.

## Implementation

Provide the patch or patches.

## Validation Notes

- Explain how the implementation satisfies the examples and constraints.

## Open Questions

- List only questions that block correctness.

# Completion Criteria

- Phase 1-3 scaffolding exists as a coherent package extension.
- The boilerplate composes around the existing foundation files instead of replacing them.
- The transport layer is runtime-neutral.
- Tests cover blueprint assembly, state persistence helpers, authoring-guide extraction behavior, and module-status shaping.
- No privileged deployment behavior is implemented.
